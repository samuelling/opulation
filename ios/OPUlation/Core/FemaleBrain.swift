// Her ears and song pathway: FlyHarp's FlyWire auditory network (4,222 neurons), in Q16 integers, exactly as
// js/female.js computes it (data/vectors.json checks the two agree bit for bit). Only +, -, * of integers, floor
// shifts (>> on Int64 is a floor) and floor division.
import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

@inline(__always) func floorDiv(_ a: Int64, _ b: Int64) -> Int64 { let q = a / b; return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q }

/** data/ear.json + ear.bin + female-model.json */
public final class BrainData: @unchecked Sendable {
    public struct Meta: Decodable { public let n: Int; public let tiers: [Int]; public let sign: [Double]; public let intot: [Int]; public let x: [Double]; public let y: [Double]; public let np: [String] }
    public struct Song: Decodable { public let tick: Double; public let pulseHz: Double; public let sineHz: Double; public let pulseAmp: Double; public let sineAmp: Double; public let pulseSigma: Double; public let ipiTicks: [Int] }
    public struct Jon: Decodable { public let ear: [Int]; public let slow: [Int]; public let pol: [Int]; public let band: [Int]; public let gain: [Int64]; public let dtTauA: [Int64]; public let kA: [Int64] }
    public struct Prof: Decodable { public let push: [Int64]; public let pull: [Int64] }
    public struct Model: Decodable {
        public let NB: Int; public let dtTicks: Int; public let song: Song; public let G: Int64; public let alpha: [Int64]; public let c50: Int64; public let cSlow: Int64
        public let kNorm: Int64; public let aSlow: Int64; public let signQ8: [String: Int64]; public let personality: Int64; public let jon: Jon; public let tanhLUT: [Int64]
        public let envOff: Int; public let envTable: [Int64]; public let pulseProf: Prof; public let sineProf: Prof; public let pulseAbs: Int64; public let sineAbs: Int64
        public let pulseAmp: Int64; public let sineAmp: Int64; public let readout: [Int]; public let named: [String: [Int]]
    }
    public let meta: Meta, M: Model, rowptr: [Int32], pre: [UInt16], syn: [UInt16]
    public init(earJSON: Data, earBin: Data, model: Data) throws {
        meta = try JSONDecoder().decode(Meta.self, from: earJSON); M = try JSONDecoder().decode(Model.self, from: model)
        let N = meta.n, b = [UInt8](earBin)
        func i32(_ o: Int) -> Int32 { Int32(bitPattern: UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24) }
        func u16(_ o: Int) -> UInt16 { UInt16(b[o]) | UInt16(b[o + 1]) << 8 }
        rowptr = (0...N).map { i32(4 * $0) }; let E = Int(rowptr[N]), o1 = 4 * (N + 1), o2 = o1 + 2 * E
        pre = (0..<E).map { u16(o1 + 2 * $0) }; syn = (0..<E).map { u16(o2 + 2 * $0) }
    }
    public static func bundled(_ bundle: Bundle = .main) throws -> BrainData {
        func d(_ n: String, _ e: String) throws -> Data { try Data(contentsOf: bundle.url(forResource: n, withExtension: e)!) }
        return try BrainData(earJSON: d("ear", "json"), earBin: d("ear", "bin"), model: d("female-model", "json"))
    }
}

/** 2 bytes per neuron from the 32-byte seed: SHA-512(seed | 'OP' | c LE16), as js/female.js */
public func personality(seed: [UInt8], n: Int) -> [UInt8] {
    var out: [UInt8] = []; out.reserveCapacity(2 * n); var c = 0
    while out.count < 2 * n { var h = SHA512(); h.update(data: seed + [0x4f, 0x50, UInt8(c & 255), UInt8((c >> 8) & 255)]); out += [UInt8](h.finalize()); c += 1 }
    return Array(out.prefix(2 * n))
}

public final class FemaleBrain {
    public let N: Int, nJ: Int, D: BrainData
    let w: [Int64], tierAlpha: [Int64], p: [Int64]
    public var V: [Int64], r: [Int64]; var acc: [Int64], jA: [Int64]
    public init(_ D: BrainData, pers: [UInt8]) {
        self.D = D; let meta = D.meta, M = D.M; N = meta.n; nJ = meta.tiers[0]; let Q: Int64 = 1 << 16
        let sq: [Int64] = meta.sign.map { s in
            let key = s == 1 ? "1" : s == -1 ? "-1" : s == 0.3 ? "0.3" : String(s)
            return M.signQ8[key] ?? (s > 0 ? 256 : s < 0 ? -256 : 0) }
        var w = [Int64](repeating: 0, count: D.pre.count)
        for i in 0..<N { let tot = Int64(max(meta.intot[i], 1)); for q in Int(D.rowptr[i])..<Int(D.rowptr[i + 1]) { w[q] = floorDiv(sq[Int(D.pre[q])] * Int64(D.syn[q]) * 256, tot) } }
        self.w = w
        var ta: [Int64] = []; for (t, n) in meta.tiers.enumerated() { ta += [Int64](repeating: M.alpha[t], count: n) }; tierAlpha = ta
        var p = [Int64](repeating: Q, count: N)
        for i in nJ..<N { p[i] = Q - M.personality + (Int64(Int(pers[2 * i]) | Int(pers[2 * i + 1]) << 8) % (2 * M.personality + 1)) }
        self.p = p; V = [Int64](repeating: 0, count: N); r = V; acc = V; jA = [Int64](repeating: 0, count: nJ)
    }
    public func reset() { for i in 0..<N { V[i] = 0; r[i] = 0 }; for j in 0..<nJ { jA[j] = 0 } }
    /** one 5 ms antenna frame (Q16 ints) */
    public func input(_ f: [Int64]) {
        let M = D.M, NB = M.NB, J = M.jon
        var pool: [Int64] = [0, 0]
        for e in 0..<2 { var s: Int64 = 0; for b in 0..<(2 * NB) { s += f[e * 2 * NB + b] }; pool[e] = floorDiv(s, Int64(2 * NB)) }
        for j in 0..<nJ {
            let e = J.ear[j], slow = J.slow[j] != 0
            let env = slow ? f[4 * NB + e] : f[e * 2 * NB + J.pol[j] * NB + J.band[j]]
            let c = slow ? M.cSlow : M.c50 + M.kNorm * pool[e]
            let d = floorDiv(J.gain[j] * env, env + c)
            jA[j] += ((d - jA[j]) * J.dtTauA[j]) >> 16
            r[j] = min(max(d - ((J.kA[j] * jA[j]) >> 16), 0), 1 << 16)
        }
    }
    public func step() {
        let G = D.M.G, L = D.M.tanhLUT
        D.rowptr.withUnsafeBufferPointer { rp in D.pre.withUnsafeBufferPointer { pre in w.withUnsafeBufferPointer { w in
            for i in nJ..<N { var s: Int64 = 0; for q in Int(rp[i])..<Int(rp[i + 1]) { s += w[q] * r[Int(pre[q])] }; acc[i] = ((s >> 16) * G * p[i]) >> 16 }
        } } }
        for i in nJ..<N { V[i] += (tierAlpha[i] * (acc[i] - V[i])) >> 16; let v = V[i]; r[i] = v > 0 ? L[Int(min(v >> 6, 4096))] : 0 }
    }
    public func drive() -> Int64 { var s: Int64 = 0; for i in D.M.readout { s += r[i] }; return floorDiv(s, Int64(D.M.readout.count)) }
    public func digest() -> UInt32 {
        var h: UInt32 = 2166136261
        for i in 0..<N { let u = UInt32(truncatingIfNeeded: V[i]); h = (h ^ (u & 0xffff)) &* 16777619; h = (h ^ ((u >> 16) & 0xffff)) &* 16777619 }
        return h
    }
}
