import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var ritual = Ritual()
    @State var showHow = false
    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if ritual.phase == .setup { SetupView(ritual: ritual) } else { RitualView(ritual: ritual) }
                    Button("How to mate") { showHow = true }.foregroundStyle(Theme.muted).font(.footnote)
                }.padding(18)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showHow) { HowView() }
    }
    var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("OPU").font(Theme.serif(40)).foregroundStyle(Theme.cream)
            Text("lation").font(Theme.serif(22)).italic().foregroundStyle(Theme.pink).baselineOffset(14)
            Spacer()
        }.overlay(alignment: .bottomLeading) { Text("a secret passes only after a proper Drosophila courtship").font(.caption).italic().foregroundStyle(Theme.muted).offset(y: 16) }
        .padding(.bottom, 14)
    }
}

struct SetupView: View {
    @ObservedObject var ritual: Ritual
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                role(.male, "♂", "Court", "I'm sending"); role(.female, "♀", "Be courted", "I'm receiving")
            }
            if ritual.role == .male {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A first note").foregroundStyle(Theme.cream); Text("Optional. Sent the moment she accepts.").font(.caption).foregroundStyle(Theme.muted)
                    TextField("A secret note", text: $ritual.gift, axis: .vertical).lineLimit(2...3).padding(10).background(Theme.velvet).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Button { ritual.begin() } label: { Text(ritual.role == .male ? "Begin courtship" : "Wait to be courted").font(.headline).frame(maxWidth: .infinity).padding(14) }
                .background(Theme.pink).foregroundStyle(Theme.ground).clipShape(RoundedRectangle(cornerRadius: 16))
            if let e = ritual.error { Text(e).font(.footnote).foregroundStyle(Theme.amber) }
            Text("No passphrase: the courtship itself is the pairing. Two iPhones link directly (Bluetooth and Wi-Fi, no network needed); with the web page at linglab.org/opulation, through the relay.").font(.caption).foregroundStyle(Theme.muted)
        }.padding(16).background(Theme.velvet.opacity(0.6)).clipShape(RoundedRectangle(cornerRadius: 20))
    }
    func role(_ r: Ritual.Role, _ sym: String, _ t: String, _ s: String) -> some View {
        Button { ritual.role = r } label: {
            VStack(spacing: 4) { Text(sym).font(.system(size: 30)); Text(t).font(.headline); Text(s).font(.caption) }.frame(maxWidth: .infinity).padding(12)
        }.foregroundStyle(ritual.role == r ? Theme.cream : Theme.muted)
         .background(RoundedRectangle(cornerRadius: 16).fill(ritual.role == r ? Theme.velvet : .clear))
         .overlay(RoundedRectangle(cornerRadius: 16).stroke(ritual.role == r ? Theme.pink : Theme.muted.opacity(0.4)))
    }
}

struct RitualView: View {
    @ObservedObject var ritual: Ritual
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) { Text("NOW").font(.caption.bold()).foregroundStyle(Theme.ground).padding(.horizontal, 6).padding(.vertical, 2).background(ritual.done ? Theme.teal : Theme.amber).clipShape(Capsule())
                Text(ritual.todo).font(.callout).foregroundStyle(Theme.cream) }
            HStack(spacing: 6) { ForEach(Ritual.stages, id: \.self) { s in
                let i = Ritual.stages.firstIndex(of: s)!, j = Ritual.stages.firstIndex(of: ritual.stage) ?? 0
                Text(["Orient", "Tap", "Sing", "She decides", "Mate"][i]).font(.caption2).padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Capsule().fill(i == j ? (ritual.bad ? Color.red.opacity(0.5) : Theme.pink.opacity(0.5)) : i < j ? Theme.velvet : .clear))
                    .overlay(Capsule().stroke(Theme.muted.opacity(0.4))).foregroundStyle(Theme.cream) } }
            Text(ritual.caption).font(Theme.serif(17)).italic().foregroundStyle(Theme.cream)
            if !ritual.air.isEmpty { Text(ritual.air).font(.caption.monospaced()).foregroundStyle(Theme.amber) }
            if ritual.role == .female, let bits = ritual.faceBits { FaceView(bits: bits).aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14)) }
            if ritual.role == .male && ritual.camera.running && ritual.stage == "orient" {
                CameraPreview(session: ritual.camera.session).aspectRatio(3 / 4, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .bottom) { Text(ritual.glimpse ? "He glimpses her… hold steady" : "Fill the frame with her face").font(.caption).padding(6).background(.black.opacity(0.5)).clipShape(Capsule()).padding(8) }
            }
            if ritual.role == .female || ritual.stage != "orient" { BrainView(ritual: ritual) }
            if ritual.role == .male { CircuitView(ritual: ritual) }
            if ritual.nestOpen { NestView(ritual: ritual) }
            Button("Start over") { ritual.startOver() }.foregroundStyle(Theme.muted)
        }
    }
}

/** her face: hexagonal facets in two compound eyes, ink lines, four landmark dots (FlyCode's geometry) */
struct FaceView: View {
    let bits: [UInt8]
    var body: some View {
        Canvas { g, size in
            let s = size.width / FlyCode.size
            g.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.925, green: 0.894, blue: 0.839)))
            for E in FlyCode.eyes { g.fill(Path(ellipseIn: CGRect(x: (E.cx - E.rx) * s, y: (E.cy - E.ry) * s, width: 2 * E.rx * s, height: 2 * E.ry * s)), with: .color(Color(red: 0.784, green: 0.725, blue: 0.659))) }
            for (i, c) in FlyCode.cells.enumerated() {
                var p = Path(); for k in 0..<6 { let a = Double(k) * .pi / 3, pt = CGPoint(x: (c.x + FlyCode.FR * cos(a)) * s, y: (c.y + FlyCode.FR * sin(a)) * s); k == 0 ? p.move(to: pt) : p.addLine(to: pt) }; p.closeSubpath()
                g.fill(p, with: .color(bits[i] == 1 ? Color(red: 0.353, green: 0.102, blue: 0.11) : Color(red: 0.984, green: 0.953, blue: 0.91)))
            }
            for pl in FlyCode.inkLines() { var p = Path(); for (k, q) in pl.enumerated() { let pt = CGPoint(x: q.0 * s, y: q.1 * s); k == 0 ? p.move(to: pt) : p.addLine(to: pt) }
                g.stroke(p, with: .color(Color(red: 0.165, green: 0.102, blue: 0.118)), style: StrokeStyle(lineWidth: 5 * s, lineCap: .round, lineJoin: .round)) }
            for (x, y) in FlyCode.finders { g.fill(Path(ellipseIn: CGRect(x: (x - FlyCode.finderR) * s, y: (y - FlyCode.finderR) * s, width: 2 * FlyCode.finderR * s, height: 2 * FlyCode.finderR * s)), with: .color(Color(red: 0.078, green: 0.047, blue: 0.063))) }
        }
    }
}

/** her FlyWire auditory network, neurons where they sit, lit by activity; the 64 notes; her receptivity */
struct BrainView: View {
    @ObservedObject var ritual: Ritual
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ritual.role == .male ? "Her, as his phone predicts her" : "Her ears and song pathway").font(.subheadline.bold()).foregroundStyle(Theme.cream)
            Text("FlyWire auditory network · 4,222 neurons").font(.caption2).foregroundStyle(Theme.muted)
            Canvas { g, size in
                guard let D = ritual.brainData, ritual.brainSnap.count == D.meta.n else { return }
                let xs = D.meta.x, ys = D.meta.y, x0 = xs.min()!, x1 = xs.max()!, y0 = ys.min()!, y1 = ys.max()!
                let sc = min((size.width - 16) / (x1 - x0), (size.height - 16) / (y1 - y0)), ox = (size.width - sc * (x1 - x0)) / 2, oy = (size.height - sc * (y1 - y0)) / 2
                for i in 0..<D.meta.n { let v = Double(ritual.brainSnap[i]) / 255, x = ox + sc * (xs[i] - x0), y = oy + sc * (ys[i] - y0), r = 1.1 + 2.2 * v
                    g.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(Theme.pink.opacity(0.12 + 0.88 * v))) }
            }.frame(height: 190).background(Color.black.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 2) { ForEach(0..<64, id: \.self) { i in Rectangle().fill(ritual.notes[i] == 1 ? Theme.teal : ritual.notes[i] == 2 ? Color.red : Theme.muted.opacity(0.25)).frame(height: 8) } }
            GeometryReader { g in ZStack(alignment: .leading) { Capsule().fill(Theme.velvet); Capsule().fill(Theme.pink).frame(width: g.size.width * ritual.R)
                Rectangle().fill(Theme.amber).frame(width: 2).offset(x: g.size.width / 2.2) } }.frame(height: 8)
            Text("receptivity (amber: her threshold)").font(.caption2).foregroundStyle(Theme.muted)
        }
    }
}

/** his courtship-song circuit from the male CNS connectome, lying on its side: brain left, nerve cord right */
struct CircuitView: View {
    @ObservedObject var ritual: Ritual
    static let cols: [String: Color] = ["LC10a": Theme.teal, "vAB3": .purple, "P1": Theme.pink, "pIP10": Theme.amber, "pulse": .yellow, "sine": .orange, "wingMN": Theme.cream]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("His courtship circuit").font(.subheadline.bold()).foregroundStyle(Theme.cream)
            Text("978 neurons from the male CNS connectome, seeing her to singing").font(.caption2).foregroundStyle(Theme.muted)
            Canvas { g, size in
                guard let m = ritual.male else { return }; _ = ritual.maleTick
                let X = { (p: Double) in 8 + p * (size.width - 16) }, Y = { (p: Double) in 6 + p * (size.height - 12) }
                var i = 0; while i + 1 < m.back.count { g.fill(Path(CGRect(x: X(Double(m.back[i]) / 255), y: Y(Double(m.back[i + 1]) / 255), width: 1, height: 1)), with: .color(Theme.cream.opacity(0.08))); i += 2 }
                for (k, n) in m.neurons.enumerated() { let v = Double(min(1, m.r[k])), c = Self.cols[n.g] ?? Theme.muted, r = 1.2 + 2.6 * v
                    g.fill(Path(ellipseIn: CGRect(x: X(n.p[0]) - r, y: Y(n.p[1]) - r, width: 2 * r, height: 2 * r)), with: .color(c.opacity(0.2 + 0.8 * v))) }
            }.frame(height: 170).background(Color.black.opacity(0.35)).clipShape(RoundedRectangle(cornerRadius: 12))
            HStack { ForEach(["LC10a", "P1", "pIP10", "pulse", "sine", "wingMN"], id: \.self) { g in Text(g).font(.caption2).foregroundStyle(Self.cols[g]!) } }
        }
    }
}

struct NestView: View {
    @ObservedObject var ritual: Ritual
    @State var note = ""
    @State var photos: [PhotosPickerItem] = []
    @State var picking = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ritual.finished ? "All finished" : "Just the two of you").font(Theme.serif(22)).foregroundStyle(Theme.cream)
            HStack { Circle().fill(ritual.finished ? Theme.muted : Theme.teal).frame(width: 7, height: 7); Text(ritual.nestStatus).font(.caption).foregroundStyle(Theme.muted) }
            ForEach(Array(ritual.sys.enumerated()), id: \.offset) { Text($0.element).font(.caption).italic().foregroundStyle(Theme.muted).frame(maxWidth: .infinity) }
            ForEach(ritual.items) { it in Bubble(item: it) }
            ForEach(ritual.progress.sorted(by: { $0.key < $1.key }), id: \.key) { k, f in ProgressView(value: f).tint(Theme.pink) }
            if !ritual.finished {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $photos, maxSelectionCount: 10, matching: .images) { Image(systemName: "camera") }
                    Button { picking = true } label: { Image(systemName: "paperclip") }
                    TextField("A note", text: $note).padding(8).background(Theme.velvet).clipShape(Capsule()).onSubmit(sendNote)
                    Button(action: sendNote) { Image(systemName: "arrow.up.circle.fill").font(.title2) }.foregroundStyle(Theme.pink)
                }.foregroundStyle(Theme.cream)
            }
        }
        .padding(14).background(Theme.velvet.opacity(0.5)).clipShape(RoundedRectangle(cornerRadius: 18))
        .onChange(of: photos) { _, sel in for p in sel { Task { if let d = try? await p.loadTransferable(type: Data.self) { ritual.send(NestItem(kind: "photo", name: "photo.jpg", type: "image/jpeg", data: d)) } } }; photos = [] }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { res in
            for url in (try? res.get()) ?? [] { let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let d = try? Data(contentsOf: url) { ritual.send(NestItem(kind: "file", name: url.lastPathComponent, type: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream", data: d)) } }
        }
    }
    func sendNote() { let t = note.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return }; ritual.send(.note(t)); note = "" }
}

struct Bubble: View {
    let item: NestItem
    var body: some View {
        HStack { if !item.incoming { Spacer(minLength: 40) }
            Group {
                if let t = item.text { Text(t).padding(10).background(item.incoming ? Theme.velvet : Theme.pink.opacity(0.75)).clipShape(RoundedRectangle(cornerRadius: 14)) }
                else if item.type.hasPrefix("image/"), let ui = UIImage(data: item.data) {
                    VStack(alignment: .trailing) { Image(uiImage: ui).resizable().scaledToFit().frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 12))
                        if item.incoming { ShareLink(item: Image(uiImage: ui), preview: SharePreview("photo", image: Image(uiImage: ui))) { Label("save", systemImage: "square.and.arrow.down").font(.caption) } } }
                } else {
                    VStack(alignment: .leading, spacing: 4) { Label(item.name, systemImage: "doc").font(.callout); Text(ByteCountFormatter.string(fromByteCount: Int64(item.data.count), countStyle: .file)).font(.caption2)
                        if item.incoming, let url = tempFile(item) { ShareLink(item: url) { Label("save", systemImage: "square.and.arrow.down").font(.caption) } } }
                        .padding(10).background(Theme.velvet).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }.foregroundStyle(Theme.cream)
            if item.incoming { Spacer(minLength: 40) } }
    }
    func tempFile(_ it: NestItem) -> URL? { let u = FileManager.default.temporaryDirectory.appendingPathComponent(it.name); return (try? it.data.write(to: u)) != nil ? u : nil }
}

struct HowView: View {
    @Environment(\.dismiss) var dismiss
    let steps = [
        ("Two phones, one room.", "Volume up, room quiet: his song is sung out loud. Two iPhones need no network at all; with a phone on the web page (linglab.org/opulation), both need to be online."),
        ("Pick parts.", "The one sending is ♂ Court; the one receiving is ♀ Be courted. No passphrase: the courtship itself is the pairing."),
        ("♀ goes first.", "Tap Wait to be courted and allow the microphone. Her face appears: it holds her key and a room code."),
        ("♂ next.", "Tap Begin courtship, allow the camera and microphone, and fill the camera with her face until it locks."),
        ("Keep the phones close and quiet.", "His phone sings a few seconds of courtship song made from both phones' keys. Hers hears it: if it matches the keys she actually received, nobody is in the middle, and she accepts."),
        ("If she accepts,", "a private chat opens on both: notes, photos, files, end-to-end encrypted. When either of you leaves, you're finished and nothing is kept."),
        ("Kicked?", "Usually noise or distance. Move closer, quieter room, and Start over on both."),
    ]
    var body: some View {
        NavigationStack {
            List { ForEach(Array(steps.enumerated()), id: \.offset) { i, s in VStack(alignment: .leading, spacing: 4) { Text("\(i + 1). \(s.0)").bold(); Text(s.1).font(.callout) } } }
                .navigationTitle("How to mate").toolbar { Button("Got it") { dismiss() } }
        }.preferredColorScheme(.dark)
    }
}

@main struct OPUlationApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
