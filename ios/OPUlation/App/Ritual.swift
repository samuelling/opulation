// The ritual, as on the web page (js/app.js): her face -> his camera; the phones meet on Multipeer (two iPhones) or
// the relay; his key song -> her ears and FlyWire brain; her sealed verdict; then the nest, end-to-end encrypted.
import SwiftUI
import AVFoundation

@MainActor final class Ritual: ObservableObject {
    enum Role: String { case male, female }
    enum Phase { case setup, ritual }
    static let stages = ["orient", "tap", "sing", "decide", "mate"]
    @Published var role: Role = .male
    @Published var phase: Phase = .setup
    @Published var gift = ""
    @Published var stage = "orient", bad = false, caption = "", todo = "", air = "", done = false
    @Published var faceBits: [UInt8]? = nil
    @Published var glimpse = false
    @Published var R: Double = 0, notes: [Int] = Array(repeating: 0, count: 64)
    @Published var brainSnap: [UInt8] = []
    @Published var maleTick = 0
    @Published var nestOpen = false, nestStatus = "", finished = false
    @Published var items: [NestItem] = [], sys: [String] = [], progress: [Int: Double] = [:]
    @Published var error: String? = nil

    let audio = AudioIO(), camera = FaceCamera()
    private(set) var brainData: BrainData?, male: MaleCircuit?
    private var channel: Channel?, run = UUID(), detector: KeySong.Detector?
    private var listening = false

    init() {
        Task.detached(priority: .userInitiated) {
            let d = try? BrainData.bundled(), m = try? MaleCircuit.bundled()
            await MainActor.run { self.brainData = d; self.male = m; self.brainSnap = [UInt8](repeating: 0, count: d?.meta.n ?? 0) }
        }
    }

    // ------------------------------------------------------------ helpers
    private func alive(_ r: UUID) -> Bool { run == r }
    private func set(_ s: String, bad: Bool = false) { stage = s; self.bad = bad }
    private func sleep(_ s: Double) async { try? await Task.sleep(nanoseconds: UInt64(s * 1e9)) }
    private var refractoryUntil: Double { get { UserDefaults.standard.double(forKey: "opul.until") } set { UserDefaults.standard.set(newValue, forKey: "opul.until") } }
    private var rejects: Int { get { UserDefaults.standard.integer(forKey: "opul.rejects") } set { UserDefaults.standard.set(newValue, forKey: "opul.rejects") } }
    private func rejected() { rejects += 1; refractoryUntil = Date().timeIntervalSince1970 + Double(min(600, 10 << (rejects - 1))) }
    private func mated() { rejects = 0; refractoryUntil = 0 }

    func begin() {
        error = nil
        Task {
            guard await AudioIO.requestMic() else { error = "OPUlation needs the microphone (his song is the proof). Allow it in Settings."; return }
            if role == .male { guard await FaceCamera.requestAccess() else { error = "He needs the camera to see her face. Allow it in Settings."; return } }
            while brainData == nil { await sleep(0.1) }
            run = UUID(); let r = run; phase = .ritual; resetNest(); notes = Array(repeating: 0, count: 64); R = 0
            if role == .male { await runMale(r) } else { await runFemale(r) }
        }
    }
    func startOver() {
        run = UUID(); hangUp(); camera.stop(); stopListening(); audio.stopPlaying(); phase = .setup; faceBits = nil; resetNest(); set("orient")
    }
    private func hangUp() { if let c = channel { c.control(Pair.Msg.bye); let ch = c; Task { await self.sleep(0.3); ch.close() } }; channel = nil }

    // ------------------------------------------------------------ him
    private func runMale(_ r: UUID) async {
        guard let D = brainData else { return }
        set("orient"); caption = "He looks for her."; todo = "Point your camera at her screen and fill the frame with her face. Hold still until it locks."; air = ""
        var face: Pair.Face? = nil
        camera.onRead = { [weak self] res in guard let self else { return }; self.glimpse = res?.finders.isEmpty == false; if let p = res?.payload, face == nil { face = Pair.parseFace(p) } }
        do { try camera.start() } catch { todo = error.localizedDescription; return }
        while face == nil && alive(r) { await sleep(0.1) }
        camera.stop(); guard alive(r), let face else { return }
        caption = "He sees her, and turns toward her."
        let me = Pair.male(face: face, flags: [.relay, .multipeer])
        guard let keys = try? Pair.derive(me) else { caption = "That was not a fly."; return }
        let session = Pair.Session(role: .male, keys: keys)
        // meet her: Multipeer if she is an iPhone nearby, else the relay
        set("tap"); caption = "He approaches and taps her."; air = "finding her…"; todo = "Got her. Keep your phone near hers and stay quiet."
        var pipe: FramePipe? = nil
        if face.flags.contains(.multipeer) {
            let mp = MultipeerPipe(room: me.room, role: "m"); var ok = false; mp.onConnected = { ok = true }
            for _ in 0..<60 where !ok && alive(r) { await sleep(0.1) }
            if ok { pipe = mp } else { mp.close() }
        }
        if pipe == nil {
            let relay = RelayPipe(room: me.room, role: "m"); relay.onPeer = { [weak relay] in Task { await relay?.send(me.hello) } }
            for _ in 0..<100 where !relay.peer && alive(r) { await sleep(0.1) }
            guard relay.peer else { relay.close(); if alive(r) { caption = "She isn't there."; todo = "Her phone isn't in the room. Ask her to Start over, and read her new face."; done = true }; return }
            pipe = relay
        }
        guard let pipe, alive(r) else { return }
        await pipe.send(me.hello)
        var verdict: String? = nil, gone = false
        let ch = Channel(session: session, pipe: pipe); channel = ch
        ch.onControl = { t, _ in if t == Pair.Msg.accept { verdict = "accept" } else if t == Pair.Msg.kick { verdict = "kick" } }
        ch.onGone = { gone = true }
        // the song she was made to want, and her brain as he predicts it
        let sy = KeySong.symbols(keys.song), sch = KeySong.schedule(sy, D.M), air48 = KeySong.renderAir(sch, D.M)
        set("sing"); caption = "He extends one wing and sings: sine song, then pulse song. The song is the check that the keys they swapped are really theirs."
        Task.detached { [weak self] in await self?.judge(symbols: sy, expected: sy, seed: keys.seed, fast: true) }
        for bout in 0..<10 where verdict == nil && !gone && alive(r) {
            todo = "Keep your phone near hers and stay quiet." + (bout > 0 ? " He sings again." : "")
            air = "singing (3.7 s)…"; await sing(air48, sch, D)
            set("decide"); air = "waiting for her…"
            for _ in 0..<20 where verdict == nil && !gone { await sleep(0.1) }
            if verdict == nil { set("sing") }
        }
        guard alive(r) else { return }
        if verdict != "accept" {
            hangUp(); set("decide", bad: true); air = ""; done = true
            caption = verdict == "kick" ? "She kicks him away." : gone ? "She left." : "No answer from her."
            todo = verdict == "kick" ? "She rejected the song: usually noise or distance. Move closer, quieter room, Start over on both." : "Nothing from her. Volume up, phones closer, then Start over on both."
            return
        }
        if pipe.kind == "relay" { ch.control(Pair.Msg.relay) }   // a web page waits for him to say how they'll talk
        set("mate"); caption = "She slows and opens. They mate."; mated()
        openNest(ch, how: pipe.kind)
        if !gift.isEmpty { items.append(ch.send(.note(gift))) }
    }
    /** play his song and step his circuit with it */
    private func sing(_ x: [Float], _ sch: KeySong.Schedule, _ D: BrainData) async {
        final class Clock: @unchecked Sendable { var pi = 0, last = 0.0; let start = Date() }
        let clock = Clock(), tick = D.M.song.tick
        let timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let m = self.male else { return }
                let t = Date().timeIntervalSince(clock.start); var pulse = false
                while clock.pi < sch.pulses.count && Double(sch.pulses[clock.pi].t) * tick <= t { clock.pi += 1; pulse = true }
                let hum = sch.hums.contains { t >= Double($0.t0) * tick && t < Double($0.t1) * tick }
                m.step(max(0.001, t - clock.last), sees: 1, tastes: 0.4, singing: true, pulse: pulse, hum: hum); clock.last = t; self.maleTick &+= 1
            }
        }
        stopListening(); let audio = self.audio
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            do { try audio.play(x) { c.resume() } } catch { c.resume() }
        }
        timer.invalidate()
    }

    // ------------------------------------------------------------ her
    private func runFemale(_ r: UUID) async {
        guard let D = brainData else { return }
        while alive(r) {
            set("orient"); notes = Array(repeating: 0, count: 64); R = 0; air = ""; done = false
            let wait = refractoryUntil - Date().timeIntervalSince1970
            if wait > 0 { faceBits = nil; caption = "After that wrong song she is wary for \(Int(wait.rounded(.up))) s."; todo = "Wait a moment."; await sleep(1); continue }
            let me = Pair.female(flags: [.relay, .multipeer]); faceBits = FlyCode.facetBits(me.face)
            caption = "She waits to be seen."; air = "waiting…"; todo = "Brightness up; hold this screen toward his camera. Then keep the phones close and quiet while he sings."
            // listen from now: a song he sings as soon as he's seen her is kept, whole bouts only
            var bouts: [[Int]] = []; startListening { bouts.append($0) }
            // he may come by Multipeer or by the relay: the first hello wins
            let relay = RelayPipe(room: me.room, role: "f"), mp = MultipeerPipe(room: me.room, role: "f")
            var hello: Pair.Hello? = nil, chosen: FramePipe? = nil
            relay.onFrame = { f in if hello == nil, let h = Pair.parseHello(f) { hello = h; chosen = relay } }
            mp.onFrame = { f in if hello == nil, let h = Pair.parseHello(f) { hello = h; chosen = mp } }
            while hello == nil && alive(r) { await sleep(0.1) }
            guard alive(r), let hello, let pipe = chosen else { relay.close(); mp.close(); stopListening(); return }
            if pipe === relay { mp.close() } else { relay.close() }
            guard let keys = try? Pair.derive(me, hello: hello) else { pipe.close(); continue }
            faceBits = nil; set("tap"); caption = "He saw her, approached and tapped her."; todo = "He found you. Stay still and quiet while he sings."
            var gone = false
            let ch = Channel(session: Pair.Session(role: .female, keys: keys), pipe: pipe); channel = ch
            ch.onGone = { gone = true }; ch.onControl = { _, _ in }
            set("sing"); caption = "She listens for his song."
            let t0 = Date()
            while bouts.isEmpty && !gone && alive(r) && Date().timeIntervalSince(t0) < 40 { await sleep(0.1) }
            guard alive(r) else { return }
            if gone { hangUp(); caption = "He left."; todo = "Start over on both."; done = true; return }
            guard let heard = bouts.last else { ch.control(Pair.Msg.kick); hangUp(); caption = "She heard no song."; todo = "Volume up on his phone, phones closer, and try again."; await sleep(2.5); continue }
            stopListening(); air = "she hears it…"
            let verdict = await judge(symbols: heard, expected: KeySong.symbols(keys.song), seed: keys.seed, fast: false)
            guard alive(r) else { return }
            if verdict != "accept" {
                set("decide", bad: true); caption = "Wrong notes. She kicks and runs."; rejected(); ch.control(Pair.Msg.kick); await sleep(0.3); hangUp()
                todo = "Wrong song: noise, distance, or someone in the middle. She waits a little longer after each rejection."; air = "she kicks…"; await sleep(2.5); continue
            }
            set("decide"); caption = "His song matches the keys they swapped: he is who her eyes met. She slows down and opens."
            ch.control(Pair.Msg.accept)
            set("mate"); mated(); openNest(ch, how: pipe.kind); return
        }
    }
    /** run her brain on a heard song; show it; returns her verdict */
    @discardableResult nonisolated private func judge(symbols: [Int], expected: [Int], seed: [UInt8], fast: Bool) async -> String {
        guard let D = await brainData else { return "reject" }
        let brain = FemaleBrain(D, pers: personality(seed: seed, n: D.meta.n)), L = KeySong.Listener(brain: brain, expected: expected)
        let theta = Double(KeySong.Params().theta) * 2.2
        L.onFrame = { st, b in
            guard st.n % 6 == 0 || st.verdict != nil else { return }
            let snap = b.r.map { UInt8(min(255, $0 >> 8)) }, R = st.R, matched = st.matched, wrong = st.wrong
            Task { @MainActor in self.brainSnap = snap; self.R = min(1, Double(R) / theta)
                var k = 0; for i in 0..<64 where k < matched + wrong { self.notes[i] = i < symbols.count && symbols[i] == expected[i] ? 1 : 2; k += 1 } }
            if !fast { Thread.sleep(forTimeInterval: 0.012) }   // as it happens: about the song's own pace
        }
        L.advance(symbols, final: true)
        return L.verdict ?? "reject"
    }
    private func startListening(_ onSong: @escaping ([Int]) -> Void) {
        guard let D = brainData else { return }
        try? audio.startListening()
        let det = KeySong.Detector(D.M, sampleRate: audio.inputRate); detector = det
        det.onSong = { s in Task { @MainActor in onSong(s) } }
        det.onTrain = { [weak self] _, n in Task { @MainActor in self?.air = "hearing his song… \(n)/\(KeySong.trains)" } }
        audio.onInput = { [weak det] x in det?.push(x) }
        listening = true
    }
    private func stopListening() { if listening { audio.onInput = nil; audio.stopListening(); listening = false } }

    // ------------------------------------------------------------ the nest
    private func resetNest() { nestOpen = false; finished = false; items = []; sys = []; progress = [:]; nestStatus = "" }
    private func openNest(_ ch: Channel, how: String) {
        nestOpen = true; finished = false; air = "mated"; done = true
        nestStatus = (how == "multipeer" ? "direct, phone to phone" : "via relay") + " · end-to-end encrypted · kept nowhere"
        caption = "Mated. The nest is open."; todo = "You're in. Chat and drop photos or files below. Leaving ends it."
        sys = ["She accepted. This lasts as long as you both do."]
        ch.onItem = { [weak self] it in self?.progress[it.id] = nil; self?.items.append(it) }
        ch.onProgress = { [weak self] id, inc, f in self?.progress[(inc ? 1_000_000 : 0) + id] = f }
        let end = { [weak self] in guard let self, !self.finished else { return }; self.finished = true; self.channel = nil; ch.close()
            self.nestStatus = "spent · nothing kept"; self.sys.append("…and that's that. You're both finished; nothing was kept. Save anything you want before you slip away.") }
        ch.onGone = end; ch.onControl = { t, _ in if t == Pair.Msg.bye { end() } }
    }
    func send(_ item: NestItem) { guard let ch = channel, !finished else { return }; items.append(ch.send(item)) }
}
