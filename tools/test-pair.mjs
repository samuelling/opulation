// The pairing protocol, and data/vectors2.json: fixed keys -> every derived value, so the Swift app (CryptoKit)
// can prove it computes the same bytes as libsodium here.
import fs from 'fs';
import * as P from '../js/pair.js';
const ROOT = new URL('..', import.meta.url).pathname;
export async function run(ok, S) {
  const f = P.female(), face = P.parseFace(f.face);
  ok(f.face.length === 41 && face && P.hex(face.pk) === P.hex(f.pk), 'her face: version and flags, room, key in 41 bytes');
  const m = P.male(face), km = P.derive(m), kf = P.derive(f, P.parseHello(m.hello));
  ok(P.hex(km.song) === P.hex(kf.song) && P.hex(km.kHim) === P.hex(kf.kHim) && P.hex(km.seed) === P.hex(kf.seed), 'both phones derive the same song, keys and brain seed');
  const a = new P.Session('m', km), b = new P.Session('f', kf);
  const w1 = a.seal(P.M.NEST, P.text('meet me by the bromeliad')), r1 = b.open(w1);
  ok(r1 && r1.type === P.M.NEST && P.untext(r1.body) === 'meet me by the bromeliad', 'a sealed message opens for her');
  ok(b.open(w1) === null, '…but not twice (replay refused)');
  const w2 = a.seal(P.M.NEST, P.text('x')); w2[12] ^= 1; ok(b.open(w2) === null, '…nor tampered with');
  ok(a.open(b.seal(P.M.ACCEPT)).type === P.M.ACCEPT, 'her accept opens for him');
  ok(b.open(b.seal(P.M.ACCEPT)) === null, 'a phone can\'t open its own messages (direction keys differ)');
  { // a man in the middle swaps his key for his own: he can talk to her, but the song she then expects is not the one sung
    const eve = P.male(face), ke = P.derive(f, P.parseHello(eve.hello));
    ok(P.hex(ke.song) !== P.hex(km.song), 'with a swapped key, the song she expects differs from the song he sings');
    const he = new P.Session('m', km), she = new P.Session('f', ke);
    ok(he.open(she.seal(P.M.ACCEPT)) === null, '…and her accept, if fooled, would not open for him');
  }
  ok(P.parseFace(Uint8Array.of(1, ...new Uint8Array(40))) === null, 'an old (v1) face is not read as v2');
  // cross-platform vectors
  const sk = (b) => new Uint8Array(32).map((_, i) => (i * 7 + b) & 255);
  const fv = P.female(P.F.RELAY | P.F.MULTIPEER, sk(1), new Uint8Array(8).map((_, i) => 0xf0 + i)), mv = P.male(P.parseFace(fv.face), P.F.RELAY, sk(2));
  const kv = P.derive(mv), sv = new P.Session('m', kv), fs2 = new P.Session('f', P.derive(fv, P.parseHello(mv.hello)));
  const vec = { herSk: P.hex(fv.sk), hisSk: P.hex(mv.sk), room: P.hex(fv.room), face: P.hex(fv.face), hello: P.hex(mv.hello),
    transcript: P.hex(kv.transcript), song: P.hex(kv.song), seed: P.hex(kv.seed), kHim: P.hex(kv.kHim), kHer: P.hex(kv.kHer),
    hisFirstSealed: P.hex(sv.seal(P.M.NEST, P.cat(Uint8Array.of(0x4a), P.text('hello')))), herFirstSealed: P.hex(fs2.seal(P.M.ACCEPT)) };
  const path = ROOT + 'data/vectors2.json';
  if (process.env.WRITE_VECTORS || !fs.existsSync(path)) fs.writeFileSync(path, JSON.stringify(vec, null, 1));
  ok(JSON.stringify(JSON.parse(fs.readFileSync(path))) === JSON.stringify(vec), 'matches data/vectors2.json (the iPhone app checks the same bytes)');
}
