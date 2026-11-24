// The whole ritual between two simulated phones: her face through a (simulated) camera, every sound turn through
// a (simulated) room with echo and noise, her brain listening train by train. Same code paths as the app.
import * as P from '../js/pair.js';
import * as Song from '../js/song.js';
import * as F from '../js/flycode.js';
import { FemaleBrain, personality } from '../js/female.js';
import { loadBrainParts } from './test-female.mjs';
const FS = 48000;
function room(x) { const y = new Float32Array(x.length + FS / 2), d = Math.round(0.006 * FS); for (let i = 0; i < x.length; i++) { y[i + 1000] += 0.7 * x[i]; y[i + 1000 + d] += 0.3 * x[i]; } for (let i = 0; i < y.length; i++) y[i] += 0.01 * (Math.random() * 2 - 1); return y; }
/** the whole ritual. `mitm`: someone on the network swaps his HELLO for their own. */
export async function ritual(S, parts, { mitm = false } = {}) {
  const M = parts.M;
  // she shows her face; his camera reads it
  const her = P.female(), img = F.drawRaster(F.facetBits(her.face), 640, 480, F.homography([[0, 0], [1000, 0], [1000, 1000], [0, 1000]], [[140, 70], [520, 95], [510, 455], [125, 430]]));
  const face = P.parseFace(F.read(img, 640, 480)?.payload); if (!face) return 'blind';
  // he says hello on the (untrusted) pipe
  const him = P.male(face), hk = P.derive(him);
  const hello = mitm ? P.male(face).hello : him.hello;
  const fk = P.derive(her, P.parseHello(hello));
  // he sings; she hears it through the room, train by train, and judges it against the keys she received
  const air = room(Song.renderAir(Song.schedule(Song.symbolsOf(hk.song), M), M, FS));
  const L = new Song.Listener(new FemaleBrain(parts.meta, parts.bin, M, personality(S, fk.seed, parts.meta.n)), Song.symbolsOf(fk.song), M);
  const heard = []; let done = false;
  const det = new Song.SongDetector(M, FS, () => {}); det.onTrain = (s, n) => { if (n === 1) heard.length = 0; heard.push(...s); if (n >= Song.TRAINS) { L.advance(heard.slice(), true); done = true; } else L.advance(heard.slice(), false); };
  for (let i = 0; i < air.length; i += 2048) det.push(air.subarray(i, i + 2048)); det.flush(); if (!done) L.advance(heard.slice(), true);
  if (L.verdict !== 'accept') return 'kicked';
  // her accept, sealed; he must be able to open it
  const she = new P.Session('f', fk), he = new P.Session('m', hk), v = he.open(she.seal(P.M.ACCEPT));
  if (!v || v.type !== P.M.ACCEPT) return 'accept unreadable';
  const n = she.open(he.seal(P.M.NEST, P.cat(Uint8Array.of(0x4a), P.text('a fig, ripe')))); return n ? 'mated: ' + P.untext(n.body.subarray(1)) : 'note lost';
}
export async function run(ok, S) {
  const parts = loadBrainParts();
  const a = await ritual(S, parts); ok(a === 'mated: a fig, ripe', `face through the camera, song through the room: ${a}`);
  const b = await ritual(S, parts, { mitm: true }); ok(b === 'kicked', `a man in the middle swaps his key: ${b}`);
  { // she starts listening mid-song: that half bout is dropped, and his next bout is heard whole
    const sy = Song.symbolsOf(S.randombytes_buf(16)), x = Song.renderAir(Song.schedule(sy, parts.M), parts.M, FS), cut = Math.floor(1.4 * FS);
    const a = new Float32Array((x.length - cut) + 2 * FS + x.length); a.set(x.subarray(cut), 0); a.set(x, x.length - cut + 2 * FS);
    const bouts = [], det = new Song.SongDetector(parts.M, FS, ({ symbols }) => bouts.push(symbols));
    for (let i = 0; i < a.length; i += 2048) det.push(a.subarray(i, i + 2048)); det.flush();
    ok(bouts.length === 1 && bouts[0].every((v, i) => v === sy[i]), `a half-heard bout is dropped, the next is heard whole (${bouts.length} bout)`); }
}
