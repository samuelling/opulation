// OPUlation/2: the courtship as a passkey-style pairing, with no shared passphrase.
//
// Bluetooth's "numeric comparison" pairing has two people check that two screens show the same six digits. Here
// the comparison is done by the flies, over channels a remote attacker can't touch:
//
//   1. HER FACE (her screen -> his camera): version|flags, a room code (8 bytes) and her X25519 public key.
//      What his camera reads came from her screen, so he has her real key. (41 bytes, js/flycode.js)
//   2. RENDEZVOUS: both phones meet in the room on any pipe: the relay (js/pipe.js, worker/), Multipeer (iPhone),
//      or anything else. He sends HELLO: his flags and public key. The pipe is NOT trusted: whoever runs it could
//      swap his key for theirs.
//   3. HIS SONG (his speaker -> her ears): 64 inter-pulse intervals, the first 16 bytes of
//      SHA-512("OPUlation/2 song" | room | her key | his key). She computes the song she expects from the key she
//      received; if anyone swapped his key, the song he really sings doesn't match and she kicks. Her FlyWire
//      brain hears it and must reach threshold too (js/song.js Listener). 128 bits, 4 wrong notes tolerated.
//   4. VERDICT, and everything after, sealed with ChaCha20-Poly1305 (IETF) under keys from the X25519 secret.
//      Only she can make keys from his HELLO and her face's key, so a valid sealed message proves it's her.
//
// Every primitive (X25519, SHA-512, ChaCha20-Poly1305 IETF) exists in both libsodium and Apple's CryptoKit, and
// data/vectors2.json pins them, so the web and iPhone versions pair with each other.
export const VERSION = 0x20, F = { RELAY: 1, MULTIPEER: 2, WEBRTC: 4 };
export const W = { HELLO: 0x01, SEALED: 0x02 };                    // wire frame types
export const M = { ACCEPT: 0x41, KICK: 0x4b, SIGNAL: 0x53, READY: 0x59, DIRECT: 0x44, RELAY: 0x52, NEST: 0x4e, BYE: 0x58 };   // sealed message types
const te = new TextEncoder(), td = new TextDecoder();
const S = () => globalThis.sodium;
export const cat = (...a) => { const o = new Uint8Array(a.reduce((n, x) => n + x.length, 0)); let k = 0; for (const x of a) { o.set(x, k); k += x.length; } return o; };
export const hex = (b) => Array.from(b, x => x.toString(16).padStart(2, '0')).join('');
const eq = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);

/** her side: a fresh room and key pair; `face` is what her screen shows */
export function female(flags = F.RELAY | F.WEBRTC, sk = S().randombytes_buf(32), room = S().randombytes_buf(8)) {
  const pk = S().crypto_scalarmult_base(sk);
  return { role: 'f', flags, sk, pk, room, face: cat(Uint8Array.of(VERSION | flags), room, pk) };
}
export function parseFace(b) {
  if (!b || b.length !== 41 || (b[0] & 0xf0) !== VERSION) return null;
  return { flags: b[0] & 15, room: b.slice(1, 9), pk: b.slice(9, 41) };
}
/** his side, from her face */
export function male(face, flags = F.RELAY | F.WEBRTC, sk = S().randombytes_buf(32)) {
  const pk = S().crypto_scalarmult_base(sk);
  return { role: 'm', flags, sk, pk, room: face.room, herPk: face.pk, herFlags: face.flags, hello: cat(Uint8Array.of(W.HELLO, flags), pk) };
}
export function parseHello(b) { return b && b.length === 34 && b[0] === W.HELLO ? { flags: b[1], pk: b.slice(2, 34) } : null; }

/** both sides: keys, the song and the brain's seed. For her, `peer` is his HELLO; for him, nothing more is needed. */
export function derive(me, hisHello) {
  const s = S(), herPk = me.role === 'f' ? me.pk : me.herPk, hisPk = me.role === 'f' ? hisHello.pk : me.pk;
  const other = me.role === 'f' ? hisPk : herPk;
  const shared = s.crypto_scalarmult(me.sk, other);
  if (shared.every(x => x === 0)) throw new Error('bad public key');
  const T = s.crypto_hash_sha512(cat(te.encode('OPUlation/2'), me.room, herPk, hisPk));
  const K = s.crypto_hash_sha512(cat(te.encode('OPUlation/2 keys'), shared, T));
  return {
    transcript: T,
    song: s.crypto_hash_sha512(cat(te.encode('OPUlation/2 song'), T)).slice(0, 16),        // public: its strength is the air it travels through
    seed: s.crypto_hash_sha512(cat(te.encode('OPUlation/2 seed'), shared, T)).slice(0, 32), // her brain's personality
    kHim: K.slice(0, 32), kHer: K.slice(32, 64),
    peerFlags: me.role === 'f' ? hisHello.flags : me.herFlags,
  };
}

/** sealed messages, one counter per direction; the receiver needs counters to rise strictly (no replays) */
export class Session {
  constructor(role, keys) {
    this.role = role; this.tx = role === 'm' ? keys.kHim : keys.kHer; this.rx = role === 'm' ? keys.kHer : keys.kHim;
    this.dtx = role === 'm' ? 0x4d : 0x46; this.drx = role === 'm' ? 0x46 : 0x4d; this.ntx = 0; this.nrx = -1;
  }
  static nonce(dir, ctr) { const n = new Uint8Array(12); n[0] = dir; let c = ctr; for (let i = 4; i < 12; i++) { n[i] = c % 256; c = Math.floor(c / 256); } return n; }
  /** type (M.*) + body bytes -> one wire frame */
  seal(type, body = new Uint8Array(0)) {
    const ctr = this.ntx++, head = cat(Uint8Array.of(W.SEALED), Session.nonce(0, ctr).subarray(4));
    const ct = S().crypto_aead_chacha20poly1305_ietf_encrypt(cat(Uint8Array.of(type), body), head, null, Session.nonce(this.dtx, ctr), this.tx);
    return cat(head, ct);
  }
  /** wire frame -> {type, body} or null (forged, replayed, or not sealed) */
  open(f) {
    if (!f || f.length < 9 + 17 || f[0] !== W.SEALED) return null;
    let ctr = 0; for (let i = 8; i >= 1; i--) ctr = ctr * 256 + f[i];
    if (ctr <= this.nrx) return null;
    let p; try { p = S().crypto_aead_chacha20poly1305_ietf_decrypt(null, f.subarray(9), f.subarray(0, 9), Session.nonce(this.drx, ctr), this.rx); } catch (e) { return null; }
    this.nrx = ctr; return { type: p[0], body: p.subarray(1) };
  }
}
export const text = (s) => te.encode(s), untext = (b) => td.decode(b);
