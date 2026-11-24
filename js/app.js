// OPUlation: the courtship is the pairing. Her face gives him her key; the phones meet on the relay (or, between
// iPhones, Multipeer); his key song proves to her that the key she received is his; she accepts, and an end-to-end
// encrypted chat opens, going direct over WebRTC when the networks allow. js/pair.js has the protocol.
import * as Pair from './pair.js';
import { RelayPipe, Channel, DIRECT_OK } from './pipe.js';
import * as Song from './song.js';
import { FemaleBrain, personality } from './female.js';
import { MaleCircuit } from './male.js';
import * as F from './flycode.js';
import { Nest } from './link.js';
import { FlyEye } from './eye.js';
import { maleStage } from './flyart.js';
let eye = null;
const $ = (id) => document.getElementById(id);
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const FS = 48000;
let S, meta, bin, M;
let role = 'male';

// ---------------------------------------------------------------- loading
const boot = (async () => {
  await sodium.ready; S = sodium;
  const [m, b, mm] = await Promise.all([fetch('data/ear.json').then(r => r.json()), fetch('data/ear.bin').then(r => r.arrayBuffer()), fetch('data/female-model.json').then(r => r.json())]);
  meta = m; bin = b; M = mm; prepNet();
})();

// ---------------------------------------------------------------- setup screen
function setRole(r) {
  role = r; $('roleMale').setAttribute('aria-checked', String(r === 'male')); $('roleFemale').setAttribute('aria-checked', String(r === 'female'));
  $('giftField').hidden = r !== 'male'; $('go').textContent = r === 'male' ? 'Begin courtship' : 'Wait to be courted';
}
$('roleMale').onclick = () => setRole('male'); $('roleFemale').onclick = () => setRole('female');
// after a rejection she is wary for a while (10 s, doubling, up to 10 min); a mating resets it
const memory = {
  get s() { try { return JSON.parse(localStorage.getItem('opulation2') || 'null') || { rejects: 0, until: 0 }; } catch (e) { return { rejects: 0, until: 0 }; } },
  save(s) { try { localStorage.setItem('opulation2', JSON.stringify(s)); } catch (e) {} },
  refractory() { return Math.max(0, this.s.until - Date.now()); },
  rejected() { const s = this.s; s.rejects++; s.until = Date.now() + Math.min(600, 10 * 2 ** (s.rejects - 1)) * 1000; this.save(s); },
  mated() { this.save({ rejects: 0, until: 0 }); },
};
$('go').onclick = async () => {
  $('go').disabled = true;
  try { await boot; await startAudio(); } catch (e) { $('go').disabled = false; return showSetupMsg(e.message); }
  document.body.classList.remove('male', 'female'); document.body.classList.add(role);
  $('setup').hidden = true; $('ritual').hidden = false; resetNest(); window.scrollTo({ top: $('ritual').offsetTop - 8, behavior: 'smooth' });
  run = { id: Math.random() };
  if (role === 'male' && !eye) { eye = new FlyEye(); eye.ready.catch((e) => console.warn('fly eye', e)); }   // his optic lobe takes ~2 s to wake
  if (role === 'male') maleFlow($('gift').value.trim(), run); else femaleFlow(run);
};
let live = null;   // the channel of the current ritual
$('again').onclick = () => { document.body.classList.remove('male', 'female'); run = null; stopListening(); hangUp(); $('look').hidden = true; closeNest(); $('ritual').hidden = true; $('setup').hidden = false; $('go').disabled = false; resetScene(); };
function hangUp() { if (live) { try { live.control(Pair.M.BYE); } catch (e) {} try { live.close(); } catch (e) {} live = null; } }
addEventListener('pagehide', hangUp);
const openHow = () => { const d = $('how'); if (d.showModal) d.showModal(); else d.setAttribute('open', ''); };
$('howBtn').onclick = openHow; $('howBtn2').onclick = openHow;
const showSetupMsg = (t) => { $('setupMsg').textContent = t; $('setupMsg').hidden = false; };
let run = null;
const alive = (r) => run === r;

// ---------------------------------------------------------------- audio
let ctx = null, micNode = null, micStream = null, ignoreUntil = 0;
const listeners = new Set();
async function startAudio() {
  if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)({ latencyHint: 'interactive' });
  if (ctx.state !== 'running') await ctx.resume();
  if (micNode) return;
  if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) throw new Error('This browser can\'t use the microphone here (it needs https).');
  micStream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false, channelCount: 1 } });
  await ctx.audioWorklet.addModule(new URL('./capture.js', import.meta.url));
  const src = ctx.createMediaStreamSource(micStream); micNode = new AudioWorkletNode(ctx, 'opul-capture');
  micNode.port.onmessage = (e) => { if (performance.now() < ignoreUntil) return; for (const l of listeners) l(e.data); };
  src.connect(micNode); const sink = ctx.createGain(); sink.gain.value = 0; micNode.connect(sink).connect(ctx.destination);
}
function stopListening() { listeners.clear(); }
/** play samples at 48 kHz; resolves when done. The phone ignores its own microphone meanwhile. */
function play(x, onTime) {
  const buf = ctx.createBuffer(1, x.length, FS); buf.copyToChannel(x, 0);
  const src = ctx.createBufferSource(); src.buffer = buf; src.connect(ctx.destination);
  const dur = x.length / FS, t0 = ctx.currentTime + 0.05; ignoreUntil = performance.now() + (dur + 0.35) * 1000;
  if (window.__opul) window.__opul.played.push(x);
  src.start(t0);
  return new Promise(res => {
    const tick = () => { const t = ctx.currentTime - t0; if (onTime) onTime(Math.max(0, t)); if (t >= dur) { ignoreUntil = performance.now() + 300; res(); } else requestAnimationFrame(tick); };
    requestAnimationFrame(tick);
  });
}

// ---------------------------------------------------------------- the stage
const STAGES = ['orient', 'tap', 'sing', 'decide', 'mate'];
function stage(s, bad = false) {
  if (s === 'orient') { scene.kick = 0; scene.finished = 0; scene.mating = 0; }
  const i = STAGES.indexOf(s);
  for (const li of $('stages').children) { const j = STAGES.indexOf(li.dataset.s); li.className = j < i ? 'done' : j === i ? (bad ? 'bad' : 'now') : ''; }
  scene.stage = s; scene.bad = bad; scene.t0 = performance.now();
}
const caption = (t) => { $('caption').textContent = t; $('fCaption').textContent = t; };
/** the plain instruction: what to do with your phone right now */
const todo = (t, done = false) => { $('todoT').textContent = t; $('todo').classList.toggle('done', done); };
const air = (t) => { $('air').textContent = t; };

// ---------------------------------------------------------------- the male
const KEEP = 'Keep your phone near hers and stay quiet: his song is the proof.';
async function maleFlow(giftText, r) {
  $('brainMale').classList.remove('dim'); $('fTitle').textContent = 'Her, as his phone predicts her';
  stage('orient'); caption('He looks for her.'); air(''); todo('Point your camera at her screen and fill the frame with her face. Hold still until it locks.');
  const face = await lookForHer(r);
  if (!alive(r) || !face) return;
  scene.sees = 1; caption('He sees her, and turns toward her.');
  const me = Pair.male(face, Pair.F.RELAY | (DIRECT_OK ? Pair.F.WEBRTC : 0)), keys = Pair.derive(me), session = new Pair.Session('m', keys);
  // the song she was made to want (from both keys), and her brain, which he can build too
  const sy = Song.symbolsOf(keys.song), sch = Song.schedule(sy, M);
  const brain = new FemaleBrain(meta, bin, M, personality(S, keys.seed, meta.n));
  const snaps = []; const L = new Song.Listener(brain, sy, M); L.onFrame = (st, b) => snaps.push({ st, r: snapR(b) }); L.advance(sy, true);
  // meet her in her room on the relay; she is already there
  stage('tap'); caption('He approaches and taps her.'); air('finding her…'); todo('Got her. ' + KEEP);
  const relay = new RelayPipe(me.room, 'm');
  try { await relay.ready; } catch (e) { caption('He can\'t reach her.'); todo('No internet connection to the relay. Check your connection and Start over.', true); return; }
  let verdict = null, gone = false;
  const ch = live = new Channel(session, relay, { oncontrol: (m) => { if (m.type === Pair.M.ACCEPT) verdict = 'accept'; else if (m.type === Pair.M.KICK) verdict = 'kick'; },
    ongone: () => { gone = true; } });
  relay.onpeer = () => relay.send(me.hello);
  if (relay.peer) relay.send(me.hello);
  for (let t = 0; !relay.peer && t < 100 && alive(r); t++) await sleep(100);
  if (!alive(r)) return;
  if (!relay.peer) { hangUp(); caption('She isn\'t there.'); todo('Her phone isn\'t in the room any more. Ask her to Start over, and read her new face.', true); return; }
  scene.tastes = 1; await sleep(500); scene.tastes = 0.3;
  if ((face.flags & Pair.F.WEBRTC) && DIRECT_OK) ch.prepare();   // the direct link's offer, ready by the time she decides
  // he sings in bouts until she answers
  stage('sing'); caption('He extends one wing and sings: sine song, then pulse song. The song is the check that her key and his are the ones they really swapped.');
  for (let bout = 0; bout < 10 && !verdict && !gone && alive(r); bout++) {
    todo(KEEP + (bout ? ' He sings again.' : ''));
    await singKey(sch, snaps);
    stage('decide'); air('waiting for her…');
    for (let t = 0; t < 20 && !verdict && !gone; t++) await sleep(100);
    if (!verdict) stage('sing');
  }
  if (!alive(r)) return;
  if (verdict !== 'accept') {
    hangUp(); stage('decide', true); air('');
    if (verdict === 'kick') { scene.kick = performance.now(); caption('She kicks him away.'); todo('She rejected the song: usually noise, or the phones too far apart. Move closer, quieter room, and Start over on both (she may need a few seconds to calm down).', true); }
    else { caption(gone ? 'She left.' : 'No answer from her.'); todo(gone ? 'Her phone left the room. Start over on both.' : 'Nothing from her. Volume up, phones closer, quieter room, then Start over on both.', true); }
    return;
  }
  stage('mate'); caption('She slows and opens. They mate.'); air('connecting…'); todo('She accepted. One moment while the private chat opens.'); scene.mating = 0.5;
  const how = await ch.goDirect('m', { wanted: !!(face.flags & Pair.F.WEBRTC) && DIRECT_OK });
  if (!alive(r)) return;
  scene.mating = 1; memory.mated();
  openNest(ch, giftText, how); caption('Mated. The nest is open: send her photos and files.'); air('mated');
  todo('You\'re in. Chat and drop photos or files below. Leaving the page ends it.', true);
}
/** his camera, until he has read her face */
async function lookForHer(r) {
  $('look').hidden = false; $('face').hidden = true; $('cam').hidden = false; $('lookCap').textContent = 'Point your camera at her face. Her eyes hold her key and her room.';
  let stream = null; const fake = window.__opul;
  if (!fake) {
    try { stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment', width: { ideal: 1280 }, height: { ideal: 720 } }, audio: false }); }
    catch (e) { $('lookCap').textContent = 'He needs the camera to see her (' + e.message + ').'; todo('Allow camera access for this page (browser settings), then Start over.', true); return null; }
  }
  const v = $('video'); if (stream) { v.srcObject = stream; await v.play().catch(() => {}); }
  const view = $('camView'), g = view.getContext('2d'), work = document.createElement('canvas'), wg = work.getContext('2d', { willReadFrequently: true });
  let found = null, best = 0, lcMax = 1e-3, until = Infinity, eyeFirst = 0;
  // once he has read her, keep looking a moment longer so his own eye has time to see her too
  while (alive(r) && (performance.now() < until || (found && !eyeFirst && performance.now() < until + 5000) || (eyeFirst && performance.now() < eyeFirst + 1500))) {
    await sleep(90);
    let rgba, w, h;
    if (fake) { const fr = fake.camFeed(); if (!fr) continue; ({ rgba, w, h } = fr); view.width = w; view.height = h; g.putImageData(new ImageData(new Uint8ClampedArray(rgba), w, h), 0, 0); }
    else {
      const vw = v.videoWidth, vh = v.videoHeight; if (!vw) continue;
      w = 640; h = Math.round(640 * vh / vw); work.width = w; work.height = h; view.width = w; view.height = h;
      wg.drawImage(v, 0, 0, w, h); rgba = wg.getImageData(0, 0, w, h).data; g.drawImage(work, 0, 0);
    } g.fillStyle = 'rgba(18,11,23,.35)'; g.fillRect(0, 0, w, h);
    // his optic lobe looks too (FlyHarp's model), at a fly's resolution
    if (!eye) { eye = new FlyEye(); eye.ready.catch((e) => console.warn('fly eye', e)); }
    if (eye.meta && !eye._wait) { eye.sample(rgba, w, h); eye.step(2).then((Lz) => { if (!Lz) return; eye.draw($('flyEye'), Lz); if (found && !eyeFirst) eyeFirst = performance.now(); lcMax = Math.max(lcMax * 0.995, Lz.lc10, 1e-3); scene.sees = Math.min(1, Lz.lc10 / lcMax); }); }
    const res = F.read(F.toGrey(rgba, w, h), w, h);
    if (res && res.finders) {
      // show what he sees: each facet he reads lights up
      const Lc = F.layout().cells;
      for (let i = 0; i < Lc.length; i++) { const z = res.Hm[6] * Lc[i].x + res.Hm[7] * Lc[i].y + res.Hm[8], x = (res.Hm[0] * Lc[i].x + res.Hm[1] * Lc[i].y + res.Hm[2]) / z, y = (res.Hm[3] * Lc[i].x + res.Hm[4] * Lc[i].y + res.Hm[5]) / z;
        g.fillStyle = res.bits[i] ? 'rgba(255,104,186,.95)' : 'rgba(255,210,63,.55)'; g.fillRect(x - 1.5, y - 1.5, 3, 3); }
      g.strokeStyle = '#ffb547'; g.lineWidth = 2; for (const b of res.finders) { g.beginPath(); g.arc(b.x, b.y, b.r + 4, 0, 7); g.stroke(); }
      const look = Pair.parseFace(res.payload);
      if (look && !found) { found = look; until = performance.now() + 2200; $('lookCap').textContent = 'He sees her. Her eyes gave him her key and her room; his own eye (below) sees her as a fly would.'; }
      else if (!look && !found) { best++; $('lookCap').textContent = 'He glimpses her… hold steady, fill the frame with her face.'; }
    }
  }
  if (stream) stream.getTracks().forEach(t => t.stop());
  if (found) { $('look').hidden = true; }
  return found;
}

// ---------------------------------------------------------------- the female
async function femaleFlow(r) {
  $('brainMale').classList.add('dim'); $('fTitle').textContent = 'Her ears and song pathway';
  while (alive(r)) {
    stage('orient'); resetNotes(); air('');
    const wait = memory.refractory();
    if (wait > 0) { $('look').hidden = true; caption(`After that wrong song she is wary: she won't show herself for another ${Math.ceil(wait / 1000)} s.`); todo(`Wait ${Math.ceil(wait / 1000)} s.`); await sleep(1000); continue; }
    // a fresh face each time: her room and her key, in her eyes
    const me = Pair.female(Pair.F.RELAY | (DIRECT_OK ? Pair.F.WEBRTC : 0)), bits = F.facetBits(me.face);
    $('look').hidden = false; $('cam').hidden = true; $('face').hidden = false; F.drawCanvas($('face').getContext('2d'), bits, 1000);
    $('lookCap').textContent = 'Show him your face: hold your screen up to his camera, bright and still.';
    caption('She waits to be seen.'); air('waiting…'); todo('Turn your brightness up and hold this screen toward his camera. Then keep the phones close and quiet while he sings.');
    const relay = new RelayPipe(me.room, 'f');
    try { await relay.ready; } catch (e) { caption('She can\'t be found.'); todo('No internet connection to the relay. Check your connection and Start over.', true); return; }
    let hello = null, gone = false;
    relay.onframe = (f) => { const h = Pair.parseHello(f); if (h && !hello) hello = h; };
    relay.ongone = () => { gone = true; };
    while (!hello && alive(r)) await sleep(100);
    if (!alive(r)) { relay.close(); return; }
    let keys; try { keys = Pair.derive(me, hello); } catch (e) { relay.close(); caption('That was not a fly.'); continue; }
    $('look').hidden = true; scene.sees = 1;
    stage('tap'); caption('He saw her, approached and tapped her.'); todo('He found you. Stay still and quiet while he sings.'); scene.tastes = 1;
    const session = new Pair.Session('f', keys);
    const ch = live = new Channel(session, relay, { ongone: () => { gone = true; } });
    // her brain, built from both keys; the song she expects: the one made from the keys she actually received
    const expected = Song.symbolsOf(keys.song);
    let result = 'nothing';
    for (let tries = 0; tries < 6 && result === 'nothing' && !gone && alive(r); tries++) {
      const brain = new FemaleBrain(meta, bin, M, personality(S, keys.seed, meta.n));
      const L = new Song.Listener(brain, expected, M), queue = []; L.onFrame = (st, b) => queue.push({ st, r: snapR(b) });
      stage('sing'); caption('She listens for his song.'); air('listening for song…'); resetNotes();
      result = await hearSong(L, queue, expected, r);
    }
    if (!alive(r)) return;
    if (gone) { hangUp(); caption('He left.'); todo('His phone left. Start over on both.', true); return; }
    const accepted = result === 'accept';
    stage('decide', !accepted); caption(accepted ? 'His song matches the keys they swapped: he is who her eyes met. She slows down and opens.' : 'Wrong notes. She kicks and runs.');
    if (!accepted) {
      scene.kick = performance.now(); if (result !== 'nothing') memory.rejected(); ch.control(Pair.M.KICK); await sleep(300); hangUp();
      todo(result === 'nothing' ? 'No song reached her: volume up, phones closer, and try again.' : 'Wrong song: noise, distance, or someone in the middle. She waits a little longer after each rejection.', true);
      air('she kicks…'); await sleep(2500); continue;
    }
    ch.control(Pair.M.ACCEPT);
    stage('mate'); caption('They mate.'); air('connecting…'); todo('You accepted him. One moment while the private chat opens.'); scene.mating = 0.5;
    const how = await ch.goDirect('f');
    if (!alive(r)) return;
    memory.mated(); scene.mating = 1;
    openNest(ch, '', how); caption('Mated. The nest is open.'); air('mated'); todo('You\'re in. Chat and drop photos or files below. Leaving the page ends it.', true);
    return;
  }
}

/** his key song, with her brain as his phone predicts it */
async function singKey(sch, snaps) {
  air('singing (3.7 s)…'); resetNotes(); oscSet(Song.renderTrue(sch, M, 4000), 4000);
  let shown = -1;
  await play(Song.renderAir(sch, M, FS), (t) => { scene.songT = t; driveMale(sch, t); const k = Math.min(snaps.length - 1, Math.floor(t / 0.005));
    while (shown < k) { shown++; showFemale(snaps[shown].st, snaps[shown].r, true, shown < k); } });
  scene.songT = -1;
}

// ---------------------------------------------------------------- the nest: a temporary chat, with photo and file drops
// Nothing is stored: the thread lives only in this page. When either phone leaves, the session is over.
let nest = null; const rows = new Map();
const hhmm = () => new Date().toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
function nestStatus(t, ok = true) { $('nestStatus').textContent = t; $('nestDot').classList.toggle('off', !ok); }
function resetNest() { $('nest').hidden = true; $('nestSend').hidden = true; $('nestSend').classList.remove('off'); $('items').innerHTML = ''; rows.clear(); nestStatus(''); $('nestTitle').textContent = 'Just the two of you'; }
function closeNest() { nest = null; resetNest(); }
function sys(t) { const li = document.createElement('li'); li.className = 'sys'; li.textContent = t; $('items').append(li); scrollThread(); }
function scrollThread() { const th = $('items'); th.scrollTop = th.scrollHeight; }
function openNest(ch, firstNote, how) {
  resetNest(); $('nest').hidden = false; $('nestSend').hidden = false;
  nestStatus(how === 'direct' ? 'session open · direct · end-to-end encrypted · kept nowhere' : 'session open · via relay · end-to-end encrypted · kept nowhere');
  sys('She accepted. This lasts as long as you both do.');
  nest = new Nest(ch, { onItem: (it) => addItem(it), onProgress: (p) => progress(p) });
  const finished = () => { if (!nest) return; scene.finished = performance.now(); nest = null; live = null; ch.close(); $('nestSend').classList.add('off'); $('nestTitle').textContent = 'All finished'; nestStatus('spent · nothing kept', false);
    sys('…and that\'s that. You\'re both finished; nothing was kept. Save anything you want before you slip away.'); };
  ch.ongone = finished; ch.oncontrol = (m) => { if (m.type === Pair.M.BYE) finished(); };
  if (firstNote) sendItem(firstNote, 'note');
  $('nest').scrollIntoView({ behavior: 'smooth', block: 'start' });
}
async function sendItem(x, kind) { if (!nest) return; const it = await nest.send(x, kind); addItem(it); }
$('pickPhoto').onchange = (e) => { for (const f of e.target.files) sendItem(f, 'photo'); e.target.value = ''; };
$('pickFile').onchange = (e) => { for (const f of e.target.files) sendItem(f, 'file'); e.target.value = ''; };
$('noteSend').onclick = () => { const t = $('noteIn').value.trim(); if (t) { sendItem(t, 'note'); $('noteIn').value = ''; $('noteIn').focus(); } };
$('noteIn').onkeydown = (e) => { if (e.key === 'Enter') $('noteSend').click(); };
const human = (n) => n < 1024 ? n + ' B' : n < 1 << 20 ? (n / 1024).toFixed(0) + ' kB' : (n / (1 << 20)).toFixed(1) + ' MB';
const esc = (t) => String(t).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const ext = (n) => ((n || '').split('.').pop() || 'file').slice(0, 4);
function row(dir, id) { const key = dir + id; let li = rows.get(key); if (!li) { li = document.createElement('li'); li.className = dir; $('items').append(li); rows.set(key, li); scrollThread(); } return li; }
function progress(p) {
  if (p.kind === 'note') return;                         // notes are small; they just appear
  const li = row(p.dir, p.id);
  if (!li.querySelector('progress')) li.innerHTML = `<div class="drop"><div class="file"><span class="ico">${esc(ext(p.name))}</span><div><div class="fn">${esc(p.name)}</div><div class="fs">${human(p.size || 0)} · ${p.dir === 'in' ? 'arriving' : 'sending'}</div></div></div><progress max="1"></progress></div>`;
  li.querySelector('progress').value = p.frac;
}
async function addItem(it) {
  const li = it.id != null ? row(it.dir, it.id) : row(it.dir, 'x' + Math.random()), when = `<div class="when">${hhmm()}</div>`;
  if (it.kind === 'note') { const text = it.text ?? await it.blob.text(); li.innerHTML = `<div class="bub">${esc(text)}</div>${when}`; scrollThread(); return; }
  const url = URL.createObjectURL(it.blob), isImg = (it.type || '').startsWith('image/');
  li.innerHTML = `<div class="drop">` + (isImg ? `<img src="${url}" alt="${esc(it.name)}">` :
    `<div class="file"><span class="ico">${esc(ext(it.name))}</span><div><div class="fn">${esc(it.name)}</div><div class="fs">${human(it.size)}</div></div></div>`) +
    `<a href="${url}" download="${esc(it.name)}">${it.dir === 'in' ? 'save' : 'sent'} ${isImg ? 'photo' : 'file'}</a></div>${when}`;
  scrollThread();
}

/** listen to the song as it arrives; her brain runs train by train and replays in real time just behind it */

function hearSong(L, queue, expected, r) {
  return new Promise((res) => {
    const heard = []; let finished = false, start = 0, k = 0;
    const finish = () => { if (finished) return; finished = true; L.advance(heard.slice(), true); };
    const det = new Song.SongDetector(M, ctx.sampleRate, () => {}, () => { scene.pulseFlash = performance.now(); ring(); if (!start) start = performance.now() + 800; });
    det.onTrain = (syms, n) => { if (n === 1) heard.length = 0; heard.push(...syms); if (n >= Song.TRAINS) finish(); else L.advance(heard.slice(), false); };   // a new bout starts afresh
    const l = (x) => det.push(x); listeners.add(l);
    const giveUp = setTimeout(() => { det.flush(); finish(); }, 16000);
    const tick = () => {
      if (!alive(r)) { listeners.delete(l); clearTimeout(giveUp); return; }
      if (finished && !start) start = performance.now();
      if (start) { const want = Math.min(queue.length - 1, Math.floor((performance.now() - start) / 5)); while (k <= want) { const q = queue[k]; showFemale(q.st, q.r, false, k < want); k++; } }   // draw only the latest; tick the notes for the rest
      if (finished && k >= queue.length) { listeners.delete(l); clearTimeout(giveUp); return res(heard.length ? (L.verdict || 'reject') : 'nothing'); }
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  });
}


// ---------------------------------------------------------------- her brain on screen
let pos = null, areaIdx = null, readSet = null, vpo = [];
// FlyHarp's area palette: ears teal, AMMC/saddle violet, wedge yellow, AVLP red, GNG orange; the song readout hot pink
const NPCOL = { JO: '79,179,164', AMMC: '143,127,214', SAD: '143,127,214', WED: '224,195,90', AVLP: '226,87,107', PVLP: '226,87,107', GNG: '232,138,79', IPS: '232,138,79', SPS: '232,138,79' };
const AREAS = [['JO', ['JO']], ['AMMC', ['AMMC']], ['SAD', ['SAD']], ['WED', ['WED']], ['AVLP', ['AVLP', 'PVLP']], ['GNG', ['GNG']], ['IPS', ['IPS', 'SPS']]];
function prepNet() {
  const c = $('fNet'), W = c.width, H = c.height; let x0 = 1e18, x1 = -1e18, y0 = 1e18, y1 = -1e18;
  for (let i = 0; i < meta.n; i++) { x0 = Math.min(x0, meta.x[i]); x1 = Math.max(x1, meta.x[i]); y0 = Math.min(y0, meta.y[i]); y1 = Math.max(y1, meta.y[i]); }
  const s = Math.min((W - 40) / (x1 - x0), (H - 40) / (y1 - y0)), ox = (W - s * (x1 - x0)) / 2, oy = (H - s * (y1 - y0)) / 2;
  pos = new Float32Array(2 * meta.n); for (let i = 0; i < meta.n; i++) { pos[2 * i] = ox + s * (meta.x[i] - x0); pos[2 * i + 1] = oy + s * (meta.y[i] - y0); }
  areaIdx = AREAS.map(([, nps]) => meta.np.map((n, i) => nps.includes(n) ? i : -1).filter(i => i >= 0));
  readSet = new Set(M.readout); vpo = M.named.vpoEN || [];
  $('fAreas').innerHTML = AREAS.map(([n]) => `<div class="area"><i><b style="height:0"></b></i>${n}</div>`).join('');
  const bar = $('notes'); bar.innerHTML = '<span></span>'.repeat(64);
  $('rTheta').style.left = '40%';
  drawNet(new Uint8Array(meta.n)); drawMale();
}
function snapR(b) { const a = new Uint8Array(b.N); for (let i = 0; i < b.N; i++) a[i] = Math.min(255, b.r[i] >> 8); return a; }
function resetNotes() { for (const s of $('notes').children) s.className = ''; $('rBar').style.width = '0'; $('rVal').textContent = ''; }
function showAreas(r) {
  const bars = $('fAreas').querySelectorAll('b');
  areaIdx.forEach((ids, k) => { let s = 0; for (const i of ids) s += r[i]; const m = ids.length ? s / ids.length / 255 : 0; bars[k].style.height = Math.min(100, 100 * Math.sqrt(m * 4)) + '%'; });
}
function showFemale(st, r, predicted, skipDraw = false) {
  for (const p of st.pulses) if (p.k >= 0) $('notes').children[p.k].className = st.cur === 'match' ? 'm' : 'w';
  if (skipDraw) return;
  drawNet(r); showAreas(r);
  const full = Song.LISTEN.THETA * 2.5;   // the threshold mark sits at 40%
  $('rBar').style.width = Math.min(100, 100 * st.R / full) + '%';
  $('rVal').textContent = st.verdict ? (st.verdict === 'accept' ? 'accepts' : 'rejects') : `${st.matched} right · ${st.wrong} wrong${predicted ? ' (predicted)' : ''}`;
}
function drawNet(r) {
  const c = $('fNet'), g = c.getContext('2d'); g.globalCompositeOperation = 'source-over'; g.fillStyle = '#12040c'; g.fillRect(0, 0, c.width, c.height);
  g.globalCompositeOperation = 'lighter';
  for (let i = 0; i < meta.n; i++) {
    const a = r[i] / 255, x = pos[2 * i], y = pos[2 * i + 1];
    if (a < 0.01) { g.fillStyle = 'rgba(200,120,160,0.10)'; g.fillRect(x, y, 1.6, 1.6); continue; }
    const col = readSet.has(i) ? '255,104,186' : NPCOL[meta.np[i]] || '231,165,143';
    g.fillStyle = `rgba(${col},${Math.min(1, 0.25 + a * 1.5)})`; const s = 1.6 + a * 4; g.fillRect(x - s / 2, y - s / 2, s, s);
  }
  g.globalCompositeOperation = 'source-over';
  for (const i of vpo) { g.strokeStyle = 'rgba(255,210,63,0.85)'; g.beginPath(); g.arc(pos[2 * i], pos[2 * i + 1], 6 + r[i] / 40, 0, 7); g.stroke(); }
  if (vpo.length) { g.fillStyle = '#FFD23F'; g.font = 'italic 22px "Playfair Display", serif'; g.fillText('vpoEN', pos[2 * vpo[0]] + 9, pos[2 * vpo[0]] - 6); }
  g.font = '18px "Courier Prime", monospace'; g.fillStyle = 'rgba(79,179,164,.95)'; g.fillText('■ ears (Johnston\'s organ)', 12, c.height - 12); g.fillStyle = 'rgba(255,104,186,.95)'; g.textAlign = 'right'; g.fillText('■ song pathway → vpoEN', c.width - 12, c.height - 12); g.textAlign = 'left';
}

// ---------------------------------------------------------------- his circuit on screen
const circuit = new MaleCircuit(); circuit.ready.then(() => drawMale()).catch((e) => console.warn('male circuit', e)); let lastT = 0, pulseIdx = 0;
const NPOS = { LC10a: [0.13, 0.2], vAB3: [0.13, 0.66], P1: [0.33, 0.43], pIP10: [0.53, 0.43], dPR1: [0.73, 0.12], vPR6: [0.73, 0.43], TN1A: [0.73, 0.74], wing: [0.9, 0.43] };
function driveMale(sch, t) {
  if (t < lastT) { lastT = 0; pulseIdx = 0; }
  const dt = Math.max(0.001, t - lastT); lastT = t;
  const tick = t / M.song.tick; let pulse = false;
  while (pulseIdx < sch.pulses.length && sch.pulses[pulseIdx].t <= tick) { pulse = true; pulseIdx++; }
  if (pulse) ring();
  const hum = sch.hums.some(h => tick >= h.t0 && tick < h.t1);
  circuit.step(dt, { sees: scene.sees, tastes: scene.tastes, singing: true, pulse, hum }); scene.wing = circuit.a.wing; drawMale();
}
function idleMale() { if (scene.songT >= 0) return; circuit.step(1 / 60, { sees: scene.sees, tastes: scene.tastes }); scene.wing = 0.4 * circuit.a.wing; drawMale(); }   // between songs: aroused, wing half out
function drawMale() { circuit.draw($('mNet')); }
let osc = null, oscFs = 4000;
function oscSet(x, fs) { osc = x; oscFs = fs; }
function drawOsc() {
  const c = $('osc'), g = c.getContext('2d'), W = c.width, H = c.height; g.fillStyle = '#12040c'; g.fillRect(0, 0, W, H);
  g.strokeStyle = 'rgba(255,104,186,.2)'; g.beginPath(); g.moveTo(0, H / 2); g.lineTo(W, H / 2); g.stroke();
  if (!osc || scene.songT < 0) { g.fillStyle = 'rgba(185,150,166,.85)'; g.font = 'italic 20px "Playfair Display", serif'; g.fillText('his song, at true pitch, appears here as he sings', 12, H - 14); return; }
  const span = 0.5, n0 = Math.floor((scene.songT - span) * oscFs), n1 = Math.floor(scene.songT * oscFs);
  g.strokeStyle = '#FF68BA'; g.shadowColor = 'rgba(255,104,186,.8)'; g.shadowBlur = 8; g.lineWidth = 1.4; g.beginPath();
  for (let x = 0; x < W; x++) { const n = n0 + Math.floor((n1 - n0) * x / W), v = n >= 0 && n < osc.length ? osc[n] : 0; const y = H / 2 - v * H * 1.3; x ? g.lineTo(x, y) : g.moveTo(x, y); }
  g.stroke(); g.shadowBlur = 0;
}

// ---------------------------------------------------------------- the mast slips like a copier sheet (as FlyHarp's), and the logo's wing rings with each pulse
const logoEl = document.querySelector('.logo'), strings = document.querySelector('#logo .strings'), reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
let lastJit = 0;
function jitter() { if (reduced || !logoEl) return; logoEl.classList.remove('jit'); void logoEl.offsetWidth; logoEl.classList.add('jit'); lastJit = performance.now(); }
function ring() { if (!strings) return; strings.classList.remove('ring'); void strings.getBBox(); strings.classList.add('ring'); if (performance.now() - lastJit > 420 && Math.random() < 0.3) jitter(); }
(function idle() { setTimeout(() => { if (!document.hidden && performance.now() - lastJit > 3000) jitter(); idle(); }, 3500 + Math.random() * 5500); })();

// ---------------------------------------------------------------- the two flies
const scene = { stage: 'orient', bad: false, t0: 0, sees: 0, tastes: 0, wing: 0, songT: -1, kick: 0, mating: 0, pulseFlash: 0, finished: 0 };
function resetScene() { Object.assign(scene, { pose: null, stage: 'orient', bad: false, sees: 0, tastes: 0, wing: 0, songT: -1, kick: 0, mating: 0, finished: 0 }); resetNotes(); }
function drawFlies() {
  const c = $('flies'), now = performance.now(), st = scene.stage;
  const st2 = st === 'mate' && scene.mating >= 1 && scene.finished ? 'mate' : st;
  maleStage(c.getContext('2d'), c.width, c.height, { stage: st2, bad: scene.bad, t: (now - scene.t0) / 1000, now, wing: scene.wing,
    singing: scene.songT >= 0 && role === 'male', kickT: scene.kick ? (now - scene.kick) / 1000 : -1, mating: scene.mating,
    finished: !!scene.finished, finishedT: scene.finished ? (now - scene.finished) / 1000 : 0, pose: scene.pose });
}
function loop() { if (!$('ritual').hidden && role === 'male') { drawFlies(); drawOsc(); idleMale(); } requestAnimationFrame(loop); }
requestAnimationFrame(loop);

if (new URLSearchParams(location.search).has('test')) {
  // headless checks: tools/pair-test.py joins two pages: her face feeds his camera, his song her ears; the relay is real (local)
  const cam = document.createElement('canvas'); cam.width = 640; cam.height = 480; let seen = null;
  const b64f = (x) => { const u = new Uint8Array(x.buffer, x.byteOffset, x.byteLength); let s = ''; for (let i = 0; i < u.length; i += 8192) s += String.fromCharCode(...u.subarray(i, i + 8192)); return btoa(s); };
  window.__opul = { sendItem, played: [],
    card: () => { if ($('look').hidden || $('face').hidden) return null; const c = document.createElement('canvas'), S = 420; c.width = c.height = S; const g = c.getContext('2d');
      g.translate(S / 2, S / 2); g.rotate(0.05); g.drawImage($('face'), -S / 2, -S / 2, S, S); return c.toDataURL('image/png'); },
    see: (url) => { const im = new Image(); im.onload = () => { seen = im; }; im.src = url; },
    camFeed: () => { if (!seen) return null; const g = cam.getContext('2d', { willReadFrequently: true }); g.fillStyle = '#3a3036'; g.fillRect(0, 0, 640, 480);
      g.filter = 'blur(1px)'; g.drawImage(seen, 100, 30, 440, 440); g.filter = 'none'; return { rgba: g.getImageData(0, 0, 640, 480).data, w: 640, h: 480 }; },
    takePlayed: () => { const out = window.__opul.played.map(b64f); window.__opul.played = []; return out; },
    hear: (b64) => { const u = Uint8Array.from(atob(b64), c => c.charCodeAt(0)), x48 = new Float32Array(u.buffer), r = ctx.sampleRate / FS;
      const x = r === 1 ? x48 : Float32Array.from({ length: Math.floor(x48.length * r) }, (_, i) => { const t = i / r, k = Math.floor(t), f = t - k; return (x48[k] || 0) * (1 - f) + (x48[k + 1] || 0) * f; });
      for (let i = 0; i < x.length; i += 2048) { const b = x.subarray(i, i + 2048); for (const l of listeners) l(b); } },
    state: () => ({ stage: scene.stage, todo: $('todoT').textContent, caption: $('caption').textContent, air: $('air').textContent, nest: !$('nest').hidden && $('nestStatus').textContent }) };
}
