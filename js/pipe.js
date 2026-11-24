// Pipes: how sealed frames (js/pair.js) get between the phones. None of them is trusted; the courtship is what
// authenticates. On the web: the relay (worker/), then a direct WebRTC data channel when the networks allow it.
// The iPhone app adds Multipeer (Bluetooth + peer-to-peer Wi-Fi, the AirDrop machinery).
import * as P from './pair.js';

export const RELAY = (() => { const q = new URLSearchParams(location.search).get('relay'); return q || 'wss://opulation-relay.samuelling.workers.dev'; })();
export const DIRECT_OK = !!window.RTCPeerConnection && !new URLSearchParams(location.search).has('nodirect');   // ?nodirect: relay only (for testing)
export const ICE = [{ urls: 'stun:stun.cloudflare.com:3478' }, { urls: 'stun:stun.l.google.com:19302' }];

/** a room on the relay. onframe(Uint8Array); onpeer(); ongone() */
export class RelayPipe {
  constructor(room, role, { onframe = () => {}, onpeer = () => {}, ongone = () => {} } = {}) {
    Object.assign(this, { onframe, onpeer, ongone, kind: 'relay', peer: false });
    this.ws = new WebSocket(`${RELAY}/r/${P.hex(room)}?role=${role}`); this.ws.binaryType = 'arraybuffer';
    this.ready = new Promise((res, rej) => { this.ws.onopen = () => res(this); this.ws.onerror = () => rej(new Error('relay unreachable')); });
    this.ws.onmessage = (e) => {
      if (typeof e.data === 'string') { if (e.data === 'peer') { this.peer = true; this.onpeer(); } else if (e.data === 'gone') { this.peer = false; this.ongone(); } return; }
      this.onframe(new Uint8Array(e.data));
    };
    this.ws.onclose = () => { if (this.peer) { this.peer = false; this.ongone(); } };
    this.ping = setInterval(() => { if (this.ws.readyState === 1) this.ws.send('ping'); }, 25000);
  }
  send(b) { if (this.ws.readyState === 1) this.ws.send(b); }
  get buffered() { return this.ws.bufferedAmount; }
  close() { clearInterval(this.ping); try { this.ws.close(); } catch (e) {} }
}
/** a WebRTC data channel as a pipe */
export class DirectPipe {
  constructor(pc, dc, { onframe = () => {}, ongone = () => {} } = {}) {
    Object.assign(this, { pc, dc, onframe, ongone, kind: 'direct' }); dc.binaryType = 'arraybuffer';
    dc.onmessage = (e) => { if (typeof e.data !== 'string') this.onframe(new Uint8Array(e.data)); };
    dc.onclose = () => this.ongone();
  }
  send(b) { if (this.dc.readyState === 'open') this.dc.send(b); }
  get buffered() { return this.dc.bufferedAmount; }
  close() { try { this.dc.close(); this.pc.close(); } catch (e) {} }
}
const dbg = (pc, who) => { if (window.__opul) { pc.addEventListener('connectionstatechange', () => console.warn(who, 'pc', pc.connectionState)); pc.addEventListener('iceconnectionstatechange', () => console.warn(who, 'ice', pc.iceConnectionState)); } };
const gathered = (pc, ms = 1800) => new Promise((res) => { if (pc.iceGatheringState === 'complete') return res();
  const t = setTimeout(res, ms); pc.addEventListener('icegatheringstatechange', () => { if (pc.iceGatheringState === 'complete') { clearTimeout(t); res(); } }); });
const opened = (dc, ms) => new Promise((res) => { if (dc.readyState === 'open') return res(true); const t = setTimeout(() => res(false), ms);
  dc.addEventListener('open', () => { clearTimeout(t); res(true); }, { once: true }); });

/**
 * The secure channel: a Session over whichever pipe is live. Sealed control messages go to `oncontrol`; nest data
 * is offered to js/link.js's Nest through a data-channel-like face (send, onmessage, bufferedAmount).
 */
export class Channel {
  constructor(session, pipe, { oncontrol = () => {}, ongone = () => {} } = {}) {
    Object.assign(this, { session, pipe, oncontrol, ongone, onmessage: null, binaryType: 'arraybuffer', bufferedAmountLowThreshold: 1 << 20, waiters: [] });
    this.attach(pipe);
  }
  attach(pipe) { pipe.onframe = (f) => this.frame(f); pipe.ongone = () => { if (pipe === this.pipe) this.ongone(); }; }
  frame(f) {
    const m = this.session.open(f); if (!m) return;
    if (m.type === P.M.NEST) { if (!this.onmessage) return; const k = m.body[0], d = m.body.subarray(1);
      this.onmessage({ data: k === 0x4a ? P.untext(d) : d.slice().buffer }); return; }
    this.oncontrol(m);
  }
  control(type, body) { this.pipe.send(this.session.seal(type, body)); }
  /** what js/link.js's Nest calls */
  send(d) { const body = typeof d === 'string' ? P.cat(Uint8Array.of(0x4a), P.text(d)) : P.cat(Uint8Array.of(0x42), d instanceof Uint8Array ? d : new Uint8Array(d)); this.pipe.send(this.session.seal(P.M.NEST, body)); }
  get bufferedAmount() { return this.pipe.buffered; }
  addEventListener(ev, cb) { if (ev !== 'bufferedamountlow') return; const t = setInterval(() => { if (this.pipe.buffered <= this.bufferedAmountLowThreshold) { clearInterval(t); cb(); } }, 40); }
  close() { this.pipe.close(); if (this.relay && this.relay !== this.pipe) this.relay.close(); }

  /**
   * After she accepts, try to go direct. He offers, she answers (SDP sealed, so the DTLS fingerprints are bound to
   * the courtship); once the data channel is open both say READY on it, and he decides: DIRECT on the new channel,
   * or RELAY on the old one (after `ms`). Nest data only flows after his decision, so frames never cross pipes.
   * Returns 'direct' | 'relay'.
   */
  /** his side, early (while he sings): make the offer and gather addresses, so going direct costs no extra time */
  prepare() {
    if (this.prep || !DIRECT_OK) return this.prep;
    return this.prep = (async () => { const pc = new RTCPeerConnection({ iceServers: ICE }); dbg(pc, 'm'); const dc = pc.createDataChannel('nest', { ordered: true });
      await pc.setLocalDescription(await pc.createOffer()); await gathered(pc); return { pc, dc }; })().catch(() => null);
  }
  async goDirect(role, { ms = 9000, wanted = true } = {}) {
    const relay = this.pipe; this.relay = relay;
    if (role === 'm') {
      let pc = null, dpipe = null, readyFromHer = false;
      const prep = wanted && DIRECT_OK ? await this.prepare() : null; if (!wanted && this.prep) this.prep.then(p => p && p.pc.close());
      if (prep) {
        pc = prep.pc; dpipe = new DirectPipe(pc, prep.dc); dpipe.onframe = (f) => { const m = this.session.open(f); if (m && m.type === P.M.READY) readyFromHer = true; };
        this.control(P.M.SIGNAL, P.text(JSON.stringify({ type: 'offer', sdp: pc.localDescription.sdp })));
      }
      const answer = new Promise((res) => { const prev = this.oncontrol; this.oncontrol = (m) => { if (m.type === P.M.SIGNAL) { res(JSON.parse(P.untext(m.body))); this.oncontrol = prev; } else prev(m); }; });
      const until = performance.now() + ms;
      if (pc) {
        const a = await Promise.race([answer, new Promise(r => setTimeout(() => r(null), ms))]);
        if (a && a.type === 'answer') { await pc.setRemoteDescription(a); if (await opened(dpipe.dc, Math.max(0, until - performance.now()))) {
          while (!readyFromHer && performance.now() < until) await new Promise(r => setTimeout(r, 40));
          if (readyFromHer) { this.pipe = dpipe; this.attach(dpipe); this.control(P.M.DIRECT); return 'direct'; } } }
        try { pc.close(); } catch (e) {}
      }
      this.control(P.M.RELAY); return 'relay';
    }
    // her side: answer his offer if one comes; wait for his decision on either pipe
    return new Promise((res) => {
      let dpipe = null; const prev = this.oncontrol;
      const decide = (m, via) => { if (m.type === P.M.DIRECT && via) { this.pipe = via; this.attach(via); this.oncontrol = prev; res('direct'); return true; }
        if (m.type === P.M.RELAY) { if (dpipe) dpipe.close(); this.oncontrol = prev; res('relay'); return true; } return false; };
      this.oncontrol = async (m) => {
        if (decide(m, null)) return;
        if (m.type !== P.M.SIGNAL || !DIRECT_OK) return;
        const o = JSON.parse(P.untext(m.body)); if (o.type !== 'offer') return;
        const pc = new RTCPeerConnection({ iceServers: ICE }); dbg(pc, 'f');
        pc.ondatachannel = (e) => { dpipe = new DirectPipe(pc, e.channel); dpipe.onframe = (f) => { const x = this.session.open(f); if (x) decide(x, dpipe); };
          opened(e.channel, ms + 2000).then((ok) => { if (ok) dpipe.send(this.session.seal(P.M.READY)); }); };
        await pc.setRemoteDescription(o); await pc.setLocalDescription(await pc.createAnswer()); await gathered(pc);
        this.control(P.M.SIGNAL, P.text(JSON.stringify({ type: 'answer', sdp: pc.localDescription.sdp })));
      };
    });
  }
}
