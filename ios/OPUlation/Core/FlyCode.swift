// Her face as a visual code, as js/flycode.js ('face' card): 41 bytes, Reed-Solomon (24 parity bytes) over GF(256),
// whitened into 520 of her 522 facets, located by four ink dots. Drawing (CoreGraphics, in the app) and reading
// (here, from a greyscale camera frame) share this geometry exactly.
import Foundation

public enum FlyCode {
    // ------------------------------------------------------------------ Reed-Solomon over GF(256), poly 0x11d
    static let tables: (exp: [UInt8], log: [UInt8]) = {
        var e = [UInt8](repeating: 0, count: 512), l = [UInt8](repeating: 0, count: 256); var x = 1
        for i in 0..<255 { e[i] = UInt8(x); l[x] = UInt8(i); x <<= 1; if x & 256 != 0 { x ^= 0x11d } }
        for i in 255..<512 { e[i] = e[i - 255] }; return (e, l)
    }()
    static func gmul(_ a: UInt8, _ b: UInt8) -> UInt8 { a == 0 || b == 0 ? 0 : tables.exp[Int(tables.log[Int(a)]) + Int(tables.log[Int(b)])] }
    static func gdiv(_ a: UInt8, _ b: UInt8) -> UInt8 { a == 0 ? 0 : tables.exp[(Int(tables.log[Int(a)]) + 255 - Int(tables.log[Int(b)])) % 255] }
    static func polyMul(_ p: [UInt8], _ q: [UInt8]) -> [UInt8] { var r = [UInt8](repeating: 0, count: p.count + q.count - 1); for i in 0..<p.count { for j in 0..<q.count { r[i + j] ^= gmul(p[i], q[j]) } }; return r }
    static func genPoly(_ n: Int) -> [UInt8] { var g: [UInt8] = [1]; for i in 0..<n { g = polyMul(g, [1, tables.exp[i]]) }; return g }
    public static func rsEncode(_ msg: [UInt8], _ nsym: Int) -> [UInt8] {
        let g = genPoly(nsym); var out = msg + [UInt8](repeating: 0, count: nsym)
        for i in 0..<msg.count { let c = out[i]; if c != 0 { for j in 1..<g.count { out[i + j] ^= gmul(g[j], c) } } }
        for i in 0..<msg.count { out[i] = msg[i] }; return out
    }
    static func polyEval(_ p: [UInt8], _ x: UInt8) -> UInt8 { var y = p[0]; for i in 1..<p.count { y = gmul(y, x) ^ p[i] }; return y }
    public static func rsDecode(_ cw: [UInt8], _ nsym: Int) -> [UInt8]? {
        let n = cw.count, E = tables.exp, LOG = tables.log; var synd = [UInt8](repeating: 0, count: nsym), any = false
        for i in 0..<nsym { synd[i] = polyEval(cw, E[i]); if synd[i] != 0 { any = true } }
        if !any { return Array(cw.prefix(n - nsym)) }
        var C: [UInt8] = [1], B: [UInt8] = [1], L = 0, m = 1, b: UInt8 = 1
        for k in 0..<nsym {
            var d = synd[k]; if L >= 1 { for i in 1...L { d ^= gmul(i < C.count ? C[i] : 0, synd[k - i]) } }
            if d == 0 { m += 1; continue }
            let T = C, coef = gdiv(d, b)
            while C.count < B.count + m { C.append(0) }
            for i in 0..<B.count { C[i + m] ^= gmul(coef, B[i]) }
            if 2 * L <= k { L = k + 1 - L; B = T; b = d; m = 1 } else { m += 1 }
        }
        if L * 2 > nsym { return nil }
        var pos: [Int] = []
        for p in 0..<n { let xinv = E[(255 - p) % 255]; var s: UInt8 = 0; for i in stride(from: C.count - 1, through: 0, by: -1) { s = gmul(s, xinv) ^ C[i] }; if s == 0 { pos.append(p) } }
        if pos.count != L { return nil }
        var Om = [UInt8](repeating: 0, count: nsym); for i in 0..<nsym { for j in 0...i where j < C.count { Om[i] ^= gmul(C[j], synd[i - j]) } }
        var out = cw
        for p in pos {
            let X = E[p], xinv = E[(255 - p) % 255]
            var om: UInt8 = 0; for i in stride(from: nsym - 1, through: 0, by: -1) { om = gmul(om, xinv) ^ Om[i] }
            var dC: UInt8 = 0; var i = 1; while i < C.count { dC ^= gmul(C[i], E[(Int(LOG[Int(xinv)]) * (i - 1)) % 255]); i += 2 }
            if dC == 0 { return nil }
            out[n - 1 - p] ^= gmul(X, gdiv(om, dC))
        }
        for i in 0..<nsym where polyEval(out, E[i]) != 0 { return nil }
        return Array(out.prefix(n - nsym))
    }

    // ------------------------------------------------------------------ layout
    public static let payload = 41, nsym = 24, bits = (payload + nsym) * 8, size = 1000.0, D = 27.0, FR = 0.40 * 27.0
    public static let finders: [(Double, Double)] = [(70, 860), (930, 860), (500, 112), (500, 942)], finderR = 27.0
    public struct Ellipse { public let cx, cy, rx, ry: Double }
    public static let eyes = [Ellipse(cx: 268, cy: 498, rx: 214, ry: 268), Ellipse(cx: 732, cy: 498, rx: 214, ry: 268)]
    public struct Cell { public let x, y: Double; let eye: Int }
    public static let cells: [Cell] = {
        var cs: [Cell] = []
        for (e, E) in eyes.enumerated() {
            let rows = Int(ceil(E.ry / (D * 0.866))), cols = Int(ceil(E.rx / D)) + 1
            for r in -rows...rows { for c in -cols...cols {
                let x = E.cx + (Double(c) + (r & 1 != 0 ? 0.5 : 0)) * D, y = E.cy + Double(r) * D * 0.866
                let u = (x - E.cx) / (E.rx - FR), v = (y - E.cy) / (E.ry - FR); if u * u + v * v <= 1 { cs.append(Cell(x: x, y: y, eye: e)) }
            } }
        }
        return cs.sorted { a, b in a.y != b.y ? a.y < b.y : a.eye != b.eye ? a.eye < b.eye : a.x < b.x }
    }()
    static func whiten(_ n: Int) -> [UInt8] { var r = 0x1d5; return (0..<n).map { _ in let b = ((r >> 8) ^ (r >> 4)) & 1; r = ((r << 1) | b) & 511; return UInt8(b) } }
    /** 41 bytes -> one bit per facet (1 = dark) */
    public static func facetBits(_ p: [UInt8]) -> [UInt8] {
        let cw = rsEncode(p, nsym), wh = whiten(cells.count); var out = [UInt8](repeating: 0, count: cells.count)
        for i in 0..<bits { out[i] = ((cw[i >> 3] >> UInt8(7 - (i & 7))) & 1) ^ wh[i] }
        for i in bits..<cells.count { out[i] = wh[i] }; return out
    }
    /** ink polylines (head capsule, antennae, bristles, mouthparts), layout units */
    public static func inkLines() -> [[(Double, Double)]] {
        func arc(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ a0: Double, _ a1: Double, _ n: Int = 40) -> [(Double, Double)] { (0...n).map { i in let a = a0 + (a1 - a0) * Double(i) / Double(n); return (cx + rx * cos(a), cy + ry * sin(a)) } }
        var L: [[(Double, Double)]] = eyes.map { arc($0.cx, $0.cy, $0.rx + 6, $0.ry + 6, 0, 2 * .pi, 90) }
        L.append(arc(500, 520, 470, 480, .pi * 1.1, .pi * 1.9, 60))
        L += [[(455, 300), (430, 240), (395, 175)], [(545, 300), (570, 240), (605, 175)], [(395, 175), (350, 150)], [(605, 175), (650, 150)]]
        for s in [(420.0, 135.0, 400.0, 100.0), (580, 135, 600, 100), (300, 205, 270, 175), (700, 205, 730, 175)] { L.append([(s.0, s.1), (s.2, s.3)]) }
        L.append(arc(500, 760, 70, 60, 0.15 * .pi, 0.85 * .pi, 24))
        L += [[(470, 800), (480, 860), (500, 885)], [(530, 800), (520, 860), (500, 885)]]
        return L
    }

    // ------------------------------------------------------------------ reading
    public typealias H = [Double]
    public static func homography(_ src: [(Double, Double)], _ dst: [(Double, Double)]) -> H {
        var A: [[Double]] = []
        for i in 0..<4 { let (x, y) = src[i], (u, v) = dst[i]
            A.append([x, y, 1, 0, 0, 0, -u * x, -u * y, u]); A.append([0, 0, 0, x, y, 1, -v * x, -v * y, v]) }
        let n = 8
        for c in 0..<n { var p = c; for r in (c + 1)..<n where abs(A[r][c]) > abs(A[p][c]) { p = r }; A.swapAt(c, p)
            for r in 0..<n where r != c { let f = A[r][c] / A[c][c]; for k in c...n { A[r][k] -= f * A[c][k] } } }
        return (0..<n).map { A[$0][n] / A[$0][$0] } + [1]
    }
    public static func apply(_ m: H, _ x: Double, _ y: Double) -> (Double, Double) { let z = m[6] * x + m[7] * y + m[8]; return ((m[0] * x + m[1] * y + m[2]) / z, (m[3] * x + m[4] * y + m[5]) / z) }
    public struct Blob { public let x, y: Double; public let n: Int; public let r: Double }
    public static func findBlobs(_ img: [UInt8], _ w: Int, _ h: Int) -> [Blob] {
        var I = [Double](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h { var s = 0.0; for x in 0..<w { s += Double(img[y * w + x]); I[(y + 1) * (w + 1) + x + 1] = I[y * (w + 1) + x + 1] + s } }
        let R = max(8, Int((Double(w) / 12).rounded())); var dark = [Bool](repeating: false, count: w * h)
        for y in 0..<h { for x in 0..<w {
            let x0 = max(0, x - R), x1 = min(w, x + R + 1), y0 = max(0, y - R), y1 = min(h, y + R + 1)
            let m = (I[y1 * (w + 1) + x1] - I[y0 * (w + 1) + x1] - I[y1 * (w + 1) + x0] + I[y0 * (w + 1) + x0]) / Double((x1 - x0) * (y1 - y0))
            dark[y * w + x] = Double(img[y * w + x]) < m * 0.6
        } }
        var lab = [Int32](repeating: 0, count: w * h), blobs: [Blob] = [], stack: [Int] = [], id: Int32 = 0
        for p in 0..<(w * h) where dark[p] && lab[p] == 0 {
            id += 1; var n = 0, sx = 0.0, sy = 0.0, x0 = w, x1 = 0, y0 = h, y1 = 0; stack.append(p); lab[p] = id
            while let q = stack.popLast() {
                let x = q % w, y = q / w; n += 1; sx += Double(x); sy += Double(y); x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
                for r in [q - 1, q + 1, q - w, q + w] where r >= 0 && r < w * h && dark[r] && lab[r] == 0 && abs((r % w) - x) <= 1 { lab[r] = id; stack.append(r) }
            }
            let bw = Double(x1 - x0 + 1), bh = Double(y1 - y0 + 1), fill = Double(n) / (bw * bh)
            if n >= 12 && fill > 0.62 && fill < 0.9 && bw / bh > 0.6 && bw / bh < 1.66 { blobs.append(Blob(x: sx / Double(n) + 0.5, y: sy / Double(n) + 0.5, n: n, r: sqrt(Double(n) / .pi))) }
        }
        return blobs
    }
    /** four finders [L, R, top, bottom] at any rotation; also the mirrored assignment */
    static func pickFinders(_ blobs: [Blob]) -> [[Blob]] {
        guard blobs.count >= 4 else { return [] }
        let big = Array(blobs.sorted { $0.n > $1.n }.prefix(8)); var s = 0
        func d(_ a: Blob, _ b: Blob) -> Double { hypot(a.x - b.x, a.y - b.y) }
        while s + 4 <= big.count {
            let f = Array(big[s..<(s + 4)]); s += 1; if Double(f[3].n) < Double(f[0].n) * 0.45 { continue }
            let score = f.indices.map { i -> Double in let ds = f.indices.filter { $0 != i }.map { d(f[i], f[$0]) }.sorted(); return ds[0] + ds[1] }
            let bi = score.firstIndex(of: score.min()!)!, B = f[bi]
            let rest = f.indices.filter { $0 != bi }.map { f[$0] }
            var T = rest[0]; for a in rest where d(a, B) > d(T, B) { T = a }
            let pq = rest.filter { !($0.x == T.x && $0.y == T.y) }; guard pq.count == 2 else { return [] }
            let cross = (T.x - B.x) * (pq[0].y - B.y) - (T.y - B.y) * (pq[0].x - B.x)
            let (Lf, Rf) = cross < 0 ? (pq[0], pq[1]) : (pq[1], pq[0])
            return [[Lf, Rf, T, B], [Rf, Lf, T, B]]
        }
        return []
    }
    public struct Read { public let payload: [UInt8]?; public let finders: [Blob]; public let Hm: H; public let bits: [UInt8] }
    public static func read(_ img: [UInt8], _ w: Int, _ h: Int) -> Read? {
        var first: Read? = nil
        for f in pickFinders(findBlobs(img, w, h)) { guard let r = readWith(img, w, h, f) else { continue }; if r.payload != nil { return r }; if first == nil { first = r } }
        return first
    }
    static func readWith(_ img: [UInt8], _ w: Int, _ h: Int, _ f: [Blob]) -> Read? {
        let Hm = homography(finders, f.map { ($0.x, $0.y) }), span = hypot(f[1].x - f[0].x, f[1].y - f[0].y) / 860 * FR
        let samp: [Double] = cells.map { c in let (px, py) = apply(Hm, c.x, c.y); var s = 0.0, n = 0.0
            for dy in -1...1 { for dx in -1...1 { let x = Int((px + Double(dx) * 0.35 * span).rounded()), y = Int((py + Double(dy) * 0.35 * span).rounded()); if x >= 0 && y >= 0 && x < w && y < h { s += Double(img[y * w + x]); n += 1 } } }
            return n > 0 ? s / n : 128 }
        var t = samp.reduce(0, +) / Double(samp.count)
        for _ in 0..<8 { var a = 0.0, na = 0.0, b = 0.0, nb = 0.0; for v in samp { if v < t { a += v; na += 1 } else { b += v; nb += 1 } }; if na == 0 || nb == 0 { return nil }; t = (a / na + b / nb) / 2 }
        let wh = whiten(cells.count); var cw = [UInt8](repeating: 0, count: payload + nsym); let bitsOut = samp.map { $0 < t ? UInt8(1) : 0 }
        for i in 0..<bits { cw[i >> 3] |= (bitsOut[i] ^ wh[i]) << UInt8(7 - (i & 7)) }
        return Read(payload: rsDecode(cw, nsym), finders: f, Hm: Hm, bits: bitsOut)
    }
}
