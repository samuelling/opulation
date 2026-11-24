// OPUlation/2: the courtship as a passkey-style pairing. The same protocol as js/pair.js, byte for byte
// (data/vectors2.json): her face carries a room code and her X25519 key; he says HELLO on an untrusted pipe; his key
// song is SHA-512(room | her key | his key) as 64 intervals; she compares it with the song made from the keys she
// received. Everything after is sealed with ChaCha20-Poly1305 (IETF), one key and counter per direction.
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public enum Pair {
    public static let version: UInt8 = 0x20
    public struct Flags: OptionSet, Sendable { public let rawValue: UInt8; public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let relay = Flags(rawValue: 1), multipeer = Flags(rawValue: 2), webrtc = Flags(rawValue: 4) }
    public enum Wire { public static let hello: UInt8 = 0x01, sealed: UInt8 = 0x02 }
    public enum Msg { public static let accept: UInt8 = 0x41, kick: UInt8 = 0x4b, signal: UInt8 = 0x53, ready: UInt8 = 0x59,
                      direct: UInt8 = 0x44, relay: UInt8 = 0x52, nest: UInt8 = 0x4e, bye: UInt8 = 0x58 }

    public struct Face: Sendable { public let flags: Flags; public let room: [UInt8]; public let pk: [UInt8] }
    public struct Hello: Sendable { public let flags: Flags; public let pk: [UInt8] }
    public struct Keys: Sendable { public let transcript, song, seed, kHim, kHer: [UInt8]; public let peerFlags: Flags }

    public enum Role: Sendable { case female, male }
    public struct Party: Sendable {
        public let role: Role; public let flags: Flags; public let sk: [UInt8]; public let pk: [UInt8]; public let room: [UInt8]
        public var herPk: [UInt8] = []; public var herFlags: Flags = []
        /** her screen's 41 bytes */
        public var face: [UInt8] { [Pair.version | flags.rawValue] + room + pk }
        /** his HELLO frame */
        public var hello: [UInt8] { [Wire.hello, flags.rawValue] + pk }
    }

    public static func random(_ n: Int) -> [UInt8] { var g = SystemRandomNumberGenerator(); return (0..<n).map { _ in UInt8.random(in: 0...255, using: &g) } }
    static func publicKey(_ sk: [UInt8]) -> [UInt8] { [UInt8](try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: sk).publicKey.rawRepresentation) }

    public static func female(flags: Flags = [.relay, .multipeer], sk: [UInt8] = random(32), room: [UInt8] = random(8)) -> Party {
        Party(role: .female, flags: flags, sk: sk, pk: publicKey(sk), room: room)
    }
    public static func parseFace(_ b: [UInt8]?) -> Face? {
        guard let b, b.count == 41, b[0] & 0xf0 == version else { return nil }
        return Face(flags: Flags(rawValue: b[0] & 15), room: Array(b[1..<9]), pk: Array(b[9..<41]))
    }
    public static func male(face: Face, flags: Flags = [.relay, .multipeer], sk: [UInt8] = random(32)) -> Party {
        var p = Party(role: .male, flags: flags, sk: sk, pk: publicKey(sk), room: face.room); p.herPk = face.pk; p.herFlags = face.flags; return p
    }
    public static func parseHello(_ b: [UInt8]) -> Hello? { b.count == 34 && b[0] == Wire.hello ? Hello(flags: Flags(rawValue: b[1]), pk: Array(b[2..<34])) : nil }

    static func sha512(_ parts: [UInt8]...) -> [UInt8] { var h = SHA512(); for p in parts { h.update(data: p) }; return [UInt8](h.finalize()) }
    static let utf = { (s: String) in [UInt8](s.utf8) }

    public enum PairError: Error { case badKey }
    /** both sides. For her, `hello` is his HELLO; for him it is not needed. */
    public static func derive(_ me: Party, hello: Hello? = nil) throws -> Keys {
        let herPk = me.role == .female ? me.pk : me.herPk, hisPk = me.role == .female ? hello!.pk : me.pk
        let other = me.role == .female ? hisPk : herPk
        let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: me.sk)
        let shared = try priv.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: other))
        let s = shared.withUnsafeBytes { [UInt8]($0) }
        if s.allSatisfy({ $0 == 0 }) { throw PairError.badKey }
        let T = sha512(utf("OPUlation/2"), me.room, herPk, hisPk)
        let K = sha512(utf("OPUlation/2 keys"), s, T)
        return Keys(transcript: T, song: Array(sha512(utf("OPUlation/2 song"), T).prefix(16)), seed: Array(sha512(utf("OPUlation/2 seed"), s, T).prefix(32)),
                    kHim: Array(K[0..<32]), kHer: Array(K[32..<64]), peerFlags: me.role == .female ? hello!.flags : me.herFlags)
    }

    /** sealed messages; counters must rise strictly (no replays) */
    public final class Session: @unchecked Sendable {
        let tx: SymmetricKey, rx: SymmetricKey, dtx: UInt8, drx: UInt8
        var ntx: UInt64 = 0, nrx: Int64 = -1
        let lock = NSLock()
        public init(role: Role, keys: Keys) {
            tx = SymmetricKey(data: role == .male ? keys.kHim : keys.kHer); rx = SymmetricKey(data: role == .male ? keys.kHer : keys.kHim)
            dtx = role == .male ? 0x4d : 0x46; drx = role == .male ? 0x46 : 0x4d
        }
        static func nonce(_ dir: UInt8, _ ctr: UInt64) -> [UInt8] { var n = [UInt8](repeating: 0, count: 12); n[0] = dir; for i in 0..<8 { n[4 + i] = UInt8((ctr >> (8 * UInt64(i))) & 255) }; return n }
        public func seal(_ type: UInt8, _ body: [UInt8] = []) -> [UInt8] {
            lock.lock(); let ctr = ntx; ntx += 1; lock.unlock()
            let head = [Wire.sealed] + Array(Session.nonce(0, ctr)[4..<12])
            let box = try! ChaChaPoly.seal([type] + body, using: tx, nonce: try! ChaChaPoly.Nonce(data: Session.nonce(dtx, ctr)), authenticating: head)
            return head + [UInt8](box.ciphertext) + [UInt8](box.tag)
        }
        public func open(_ f: [UInt8]) -> (type: UInt8, body: [UInt8])? {
            guard f.count >= 9 + 17, f[0] == Wire.sealed else { return nil }
            var ctr: UInt64 = 0; for i in stride(from: 8, through: 1, by: -1) { ctr = ctr << 8 | UInt64(f[i]) }
            lock.lock(); defer { lock.unlock() }
            guard Int64(bitPattern: ctr) > nrx else { return nil }
            let ct = Array(f[9..<(f.count - 16)]), tag = Array(f[(f.count - 16)...])
            guard let box = try? ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: Session.nonce(drx, ctr)), ciphertext: ct, tag: tag),
                  let p = try? ChaChaPoly.open(box, using: rx, authenticating: Array(f[0..<9])), !p.isEmpty else { return nil }
            nrx = Int64(bitPattern: ctr); let b = [UInt8](p); return (b[0], Array(b.dropFirst()))
        }
    }
}
public extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
    init?(hex: String) { var o: [UInt8] = []; var i = hex.startIndex
        while i < hex.endIndex { let j = hex.index(i, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex; guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }; o.append(b); i = j }
        self = o }
}
