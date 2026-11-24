// His courtship-song circuit: 978 neurons from Janelia's male CNS connectome (data/male.json + male.bin), the same
// plain rate model as js/male.js. Seeing (LC10a) or tasting (vAB3) her wakes P1, P1 drives pIP10, pIP10 the song
// premotor and wing motor neurons; the song's rhythm itself is fed in from the key.
import Foundation

public final class MaleCircuit {
    public struct Neuron: Decodable { public let type: String; public let g: String; public let sign: Double; public let p: [Double] }
    struct Meta: Decodable { let n: Int; let G: Double; let tau: Double; let neurons: [Neuron]; let back: [Int] }
    public let neurons: [Neuron], back: [Int]; let G: Float, tau: Float, n: Int
    let pre: [Int], post: [Int], w: [Float]
    public private(set) var r: [Float]; var u: [Float], ext: [Float]
    public private(set) var groups: [String: [Int]] = [:]
    public private(set) var a: [String: Float] = ["LC10a": 0, "vAB3": 0, "P1": 0, "pIP10": 0, "pulse": 0, "sine": 0, "wingMN": 0]
    public init(json: Data, bin: Data) throws {
        let m = try JSONDecoder().decode(Meta.self, from: json); neurons = m.neurons; back = m.back; n = m.n; G = Float(m.G); tau = Float(m.tau)
        let b = [UInt8](bin), E = b.count / 6; var tot = [Float](repeating: 0, count: n)
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        var pre = [Int](), post = [Int](), wr = [Float](); pre.reserveCapacity(E); post.reserveCapacity(E)
        for k in 0..<E { tot[u16(6 * k + 2)] += Float(u16(6 * k + 4)) }
        for k in 0..<E { let p = u16(6 * k), q = u16(6 * k + 2); pre.append(p); post.append(q); wr.append(Float(m.neurons[p].sign) * Float(u16(6 * k + 4)) / max(1, tot[q])) }
        self.pre = pre; self.post = post; w = wr; r = .init(repeating: 0, count: n); u = r; ext = r
        for (i, x) in m.neurons.enumerated() { groups[x.g, default: []].append(i) }
    }
    public static func bundled(_ bundle: Bundle = .main) throws -> MaleCircuit {
        try MaleCircuit(json: Data(contentsOf: bundle.url(forResource: "male", withExtension: "json")!), bin: Data(contentsOf: bundle.url(forResource: "male", withExtension: "bin")!))
    }
    public func step(_ dt: Double, sees: Float = 0, tastes: Float = 0, singing: Bool = false, pulse: Bool = false, hum: Bool = false) {
        let steps = min(40, max(1, Int((dt / 0.005).rounded()))), h = Float(dt) / Float(steps)
        for s in 0..<steps {
            for i in 0..<n { ext[i] = 0 }
            for i in groups["LC10a"] ?? [] { ext[i] = sees * 0.9 }
            for i in groups["vAB3"] ?? [] { ext[i] = tastes }
            let drive = max(0.3, a["pIP10"] ?? 0)
            if singing && pulse && s == 0 { for i in groups["pulse"] ?? [] { ext[i] = 3 * drive } }
            if singing && hum { for i in groups["sine"] ?? [] { ext[i] = 0.9 * drive } }
            for i in 0..<n { u[i] = 0 }
            for k in 0..<w.count { u[post[k]] += w[k] * r[pre[k]] }
            for i in 0..<n { let x = G * u[i] + ext[i]; r[i] += (h / tau) * (-r[i] + (x > 0 ? tanh(x) : 0)) }
        }
        for g in a.keys { let ix = groups[g] ?? []; a[g] = ix.isEmpty ? 0 : ix.reduce(Float(0)) { $0 + r[$1] } / Float(ix.count) }
        a["wingMN"] = min(1, 1.6 * (a["wingMN"] ?? 0))
    }
}
