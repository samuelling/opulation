// The nest: files, photos and notes over the sealed channel (js/pipe.js Channel, which looks like a data channel).
// ------------------------------------------------------------------ the nest: files, photos and notes over the channel
// Each item: a JSON header {id, kind: 'file' | 'photo' | 'note', name, type, size}, then the bytes in 16 kB chunks,
// then {id, end: true}. Flow control on bufferedAmount keeps big files from swamping the channel.
const CHUNK = 16384;
export class Nest {
  constructor(dc, { onItem = () => {}, onProgress = () => {} } = {}) {
    this.dc = dc; dc.binaryType = 'arraybuffer'; this.onItem = onItem; this.onProgress = onProgress; this.rx = null; this.q = Promise.resolve(); this.n = 0;
    dc.onmessage = (e) => this._msg(e.data);
  }
  _msg(d) {
    if (typeof d === 'string') {
      const h = JSON.parse(d);
      if (h.end && this.rx && this.rx.id === h.id) { const r = this.rx; this.rx = null; const blob = new Blob(r.parts, { type: r.type || 'application/octet-stream' });
        this.onItem({ dir: 'in', id: r.id, kind: r.kind, name: r.name, type: r.type, size: r.size, blob }); }
      else if (!h.end) { this.rx = { ...h, parts: [], got: 0 }; this.onProgress({ dir: 'in', id: h.id, kind: h.kind, name: h.name, size: h.size, frac: 0 }); }
      return;
    }
    if (!this.rx) return; this.rx.parts.push(d); this.rx.got += d.byteLength; this.onProgress({ dir: 'in', id: this.rx.id, kind: this.rx.kind, name: this.rx.name, size: this.rx.size, frac: this.rx.got / Math.max(1, this.rx.size) });
  }
  /** send a File/Blob (kind 'file' or 'photo') or a note (string) */
  send(item, kind = 'file') { this.q = this.q.then(() => this._send(item, kind)); return this.q; }
  async _send(item, kind) {
    const id = ++this.n, isNote = typeof item === 'string', blob = isNote ? new Blob([item], { type: 'text/plain' }) : item;
    const name = isNote ? 'note' : (item.name || (kind === 'photo' ? 'photo.jpg' : 'file')), type = blob.type || 'application/octet-stream';
    this.dc.send(JSON.stringify({ id, kind: isNote ? 'note' : kind, name, type, size: blob.size }));
    const buf = new Uint8Array(await blob.arrayBuffer());
    this.dc.bufferedAmountLowThreshold = 1 << 20;
    for (let o = 0; o < buf.length; o += CHUNK) {
      if (this.dc.bufferedAmount > 4 << 20) await new Promise(r => this.dc.addEventListener('bufferedamountlow', r, { once: true }));
      this.dc.send(buf.subarray(o, Math.min(buf.length, o + CHUNK))); this.onProgress({ dir: 'out', id, kind: isNote ? 'note' : kind, name, size: blob.size, frac: Math.min(1, (o + CHUNK) / buf.length) });
    }
    this.dc.send(JSON.stringify({ id, end: true }));
    return { dir: 'out', id, kind: isNote ? 'note' : kind, name, type, size: blob.size, blob };
  }
}
