// The key song, as js/song.js: 16 bytes -> 64 symbols -> four trains of 16 inter-pulse intervals (30/36/42/48 ms)
// with sine-song hums, in 0.25 ms ticks. His phone sings it three octaves up; hers detects the intervals and replays
// the ideal song, frame by frame, into her brain (Listener), which must agree note by note and reach threshold.
import Foundation

public enum KeySong {
    public static let trains = 4, perTrain = 16, boutGap = 1.0
    public static func symbols(_ tag: [UInt8]) -> [Int] { tag.flatMap { b in stride(from: 6, through: 0, by: -2).map { Int((b >> UInt8($0)) & 3) } } }

    public struct Pulse: Sendable { public let t: Int; public let k: Int; public let train: Int }
    public struct Hum: Sendable { public let t0: Int; public var t1: Int }
    public struct Schedule: Sendable { public let pulses: [Pulse]; public let hums: [Hum]; public let end: Int }
    public static func schedule(_ symbols: [Int], _ M: BrainData.Model) -> Schedule {
        let ipi = M.song.ipiTicks; var pulses: [Pulse] = [], hums: [Hum] = [], t = 40
        hums.append(Hum(t0: t, t1: t + 1200)); t += 1200 + 160
        for tr in 0..<trains {
            pulses.append(Pulse(t: t, k: -1, train: tr))
            for i in 0..<perTrain { let k = tr * perTrain + i; t += ipi[k < symbols.count ? symbols[k] : 0]; pulses.append(Pulse(t: t, k: k, train: tr)) }
            if tr < trains - 1 { t += 240; hums.append(Hum(t0: t, t1: t + 800)); t += 800 + 240 }
        }
        return Schedule(pulses: pulses, hums: hums, end: t + 400)
    }

    /** ideal antenna frames (Q16), one per 5 ms */
    public final class Framer {
        let M: BrainData.Model; public private(set) var n = 0; var slow: Int64 = 0; var pi = 0
        public init(_ M: BrainData.Model) { self.M = M }
        public func next(_ sch: Schedule) -> (n: Int, f: [Int64], pulses: [Pulse], hum: Bool) {
            let NB = M.NB, F = M.dtTicks, OFF = M.envOff, pp = M.pulseProf, sp = M.sineProf, n = self.n; self.n += 1
            let a = n * F, b = a + F; var envP: Int64 = 0; var here: [Pulse] = []
            while pi < sch.pulses.count && sch.pulses[pi].t < a - OFF { pi += 1 }
            var j = pi
            while j < sch.pulses.count && sch.pulses[j].t <= a + OFF { envP += M.envTable[sch.pulses[j].t - a + OFF]; if sch.pulses[j].t >= a && sch.pulses[j].t < b { here.append(sch.pulses[j]) }; j += 1 }
            if envP > 65536 { envP = 65536 }
            var cov = 0; for h in sch.hums { let o = min(b, h.t1) - max(a, h.t0); if o > 0 { cov += o } }
            let envS = floorDiv(Int64(cov) * 65536, Int64(F)); var f = [Int64](repeating: 0, count: 4 * NB + 2)
            let ap = (envP * M.pulseAmp) >> 16, aS = (envS * M.sineAmp) >> 16
            for k in 0..<NB {
                let push = ((ap * pp.push[k]) >> 16) + ((aS * sp.push[k]) >> 16), pull = ((ap * pp.pull[k]) >> 16) + ((aS * sp.pull[k]) >> 16)
                f[k] = push; f[NB + k] = pull; f[2 * NB + k] = push; f[3 * NB + k] = pull
            }
            slow += ((((envP * M.pulseAbs) >> 16) + ((envS * M.sineAbs) >> 16) - slow) * M.aSlow) >> 16
            f[4 * NB] = slow; f[4 * NB + 1] = slow
            return (n, f, here, cov > 0)
        }
    }

    public struct Params: Sendable { public var KD: Int64 = 2, KH: Int64 = 1, KICK: Int64 = 6000, maxWrong = 4, theta: Int64 = 600000; public init() {} }
    public enum Cur: Sendable { case none, anchor, match, wrong }
    public struct State: Sendable { public let n: Int; public let drive: Int64; public let R: Int64; public let matched: Int; public let wrong: Int; public let cur: Cur; public let hum: Bool; public var verdict: String? }

    /** she listens; `advance(heardSoFar, final)` runs her brain as far as the heard song allows */
    public final class Listener {
        public let brain: FemaleBrain; let expected: [Int]?; let M: BrainData.Model; let P: Params
        let framer: Framer; public private(set) var R: Int64 = 0, wrong = 0, matched = 0; var cur: Cur = .none
        public private(set) var verdict: String? = nil; public private(set) var done = false; public private(set) var last: State? = nil
        public var onFrame: ((State, FemaleBrain) -> Void)?
        public init(brain: FemaleBrain, expected: [Int]?, P: Params = Params()) { self.brain = brain; self.expected = expected; M = brain.D.M; self.P = P; framer = Framer(M); brain.reset() }
        @discardableResult public func advance(_ heard: [Int], final: Bool = false) -> [State] {
            var out: [State] = []; if done { return out }
            var full = heard; while full.count < trains * perTrain { full.append(0) }
            let sch = schedule(full, M)
            var safe = sch.end
            if !final { var lastKnown = 0; for p in sch.pulses { if p.k < heard.count { lastKnown = p.t } else { break } }
                safe = heard.count >= trains * perTrain ? sch.end : lastKnown - M.envOff }
            while !done && (framer.n + 1) * M.dtTicks <= safe {
                let fr = framer.next(sch); brain.input(fr.f); brain.step(); let d = brain.drive()
                for p in fr.pulses {
                    if p.k < 0 { cur = .anchor; continue }
                    let ok = expected == nil || heard[p.k] == expected![p.k]; cur = ok ? .match : .wrong
                    if ok { matched += 1 } else { wrong += 1; R = max(0, R - P.KICK) }
                    if wrong > P.maxWrong && verdict == nil { verdict = "reject" }
                }
                if verdict == nil { if cur == .match { R += P.KD * d } else if fr.hum || cur == .anchor { R += P.KH * d } }
                let st = State(n: fr.n, drive: d, R: R, matched: matched, wrong: wrong, cur: cur, hum: fr.hum, verdict: verdict)
                out.append(st); last = st; onFrame?(st, brain)
                if verdict != nil { done = true }
            }
            if final || framer.n * M.dtTicks >= sch.end { done = true; if verdict == nil, let l = last { verdict = KeySong.decide(l, P) }; last?.verdict = verdict }
            return out
        }
    }
    public static func decide(_ last: State, _ P: Params = Params()) -> String { last.verdict == "reject" ? "reject" : (last.wrong <= P.maxWrong && last.R >= P.theta ? "accept" : "reject") }

    // ------------------------------------------------------------------ on the air
    public static let up = 8.0, pulseSigma = 0.0012, pulseAmp: Float = 0.6, humAmp: Float = 0.18
    public static func renderAir(_ sch: Schedule, _ M: BrainData.Model, fs: Double = 48000) -> [Float] {
        let tick = M.song.tick, N = Int(ceil((Double(sch.end) * tick + 0.05) * fs)); var x = [Float](repeating: 0, count: N)
        let fp = M.song.pulseHz * up, fh = M.song.sineHz * up, sg = pulseSigma
        for p in sch.pulses { let tc = Double(p.t) * tick, a = max(0, Int(floor((tc - 4 * sg) * fs))), b = min(N, Int(ceil((tc + 4 * sg) * fs)))
            for n in a..<b { let t = Double(n) / fs - tc; x[n] += pulseAmp * Float(exp(-0.5 * (t / sg) * (t / sg)) * cos(2 * .pi * fp * t)) } }
        for h in sch.hums { let a = Int(floor(Double(h.t0) * tick * fs)), b = Int(floor(Double(h.t1) * tick * fs)), r = Int((0.01 * fs).rounded())
            for n in a..<min(b, N) { let e = min(1, Double(n - a) / Double(r), Double(b - n) / Double(r)); x[n] += humAmp * Float(e * sin(2 * .pi * fh * Double(n) / fs)) } }
        return x
    }

    /** streaming detector for the microphone: pulse peaks -> trains -> symbols. A long silence starts a new bout. */
    public final class Detector {
        let fs: Double, w: Double, wh: Double, L: Int, ipiMs: [Double]
        var ph = 0.0, phh = 0.0, bi: [Double], bq: [Double], hi: [Double], hq: [Double], si = 0.0, sq = 0.0, shi = 0.0, shq = 0.0, k = 0
        var n = 0, floorE = 1e-6, prev2 = 0.0, prev1 = 0.0, lastPeak = -1_000_000_000, lastT: Double? = nil
        var cur: [Double] = [], trainsSoFar: [[Int]] = []
        public var onSong: (([Int]) -> Void)?, onTrain: (([Int], Int) -> Void)?, onPulse: (() -> Void)?
        public init(_ M: BrainData.Model, sampleRate: Double) {
            fs = sampleRate; w = 2 * .pi * M.song.pulseHz * KeySong.up / sampleRate; wh = 2 * .pi * M.song.sineHz * KeySong.up / sampleRate
            L = max(4, Int((0.002 * sampleRate).rounded())); bi = .init(repeating: 0, count: L); bq = bi; hi = bi; hq = bi
            ipiMs = M.song.ipiTicks.map { Double($0) * M.song.tick }
        }
        public func push(_ x: [Float]) {
            for v32 in x {
                let v = Double(v32), ci = v * cos(ph), cq = -v * sin(ph); ph += w; if ph > 2 * .pi { ph -= 2 * .pi }
                let h1 = v * cos(phh), h2 = -v * sin(phh); phh += wh; if phh > 2 * .pi { phh -= 2 * .pi }
                si += ci - bi[k]; sq += cq - bq[k]; bi[k] = ci; bq[k] = cq
                shi += h1 - hi[k]; shq += h2 - hq[k]; hi[k] = h1; hq[k] = h2; k = (k + 1) % L
                let LL = Double(L * L), e = (si * si + sq * sq) / LL, eh = (shi * shi + shq * shq) / LL
                floorE = e < floorE ? floorE * 0.999 + e * 0.001 : floorE * 0.99999 + e * 0.00001
                let i = n; n += 1
                if prev1 > prev2 && prev1 >= e && prev1 > 40 * floorE && prev1 > 1e-7 && prev1 > 4 * eh && Double(i - 1 - lastPeak) > 0.022 * fs {
                    let den = prev2 - 2 * prev1 + e, off = den != 0 ? 0.5 * (prev2 - e) / den : 0
                    peak((Double(i - 1) + off) / fs); lastPeak = i - 1
                }
                prev2 = prev1; prev1 = e
                if let l = cur.last, Double(i) / fs - l > 0.08 { endTrain() }
            }
        }
        func peak(_ t: Double) {
            if let lt = lastT, t - lt > KeySong.boutGap, !trainsSoFar.isEmpty { trainsSoFar = [] }
            lastT = t; cur.append(t); onPulse?()
        }
        func endTrain() {
            let c = cur; cur = []; guard c.count >= 6 else { return }
            var syms: [Int] = []
            for i in 1..<c.count { let d = c[i] - c[i - 1]; var best = 0; for s in 1..<4 where abs(d - ipiMs[s]) < abs(d - ipiMs[best]) { best = s }; syms.append(best) }
            while syms.count < perTrain { syms.append(0) }; syms = Array(syms.prefix(perTrain))
            trainsSoFar.append(syms); onTrain?(syms, trainsSoFar.count)
            if trainsSoFar.count == trains { let s = trainsSoFar.flatMap { $0 }; trainsSoFar = []; onSong?(s) }
        }
        public func flush() { if !cur.isEmpty { endTrain() } }
    }
}
