// The iPhone core must compute exactly what the web version does: data/vectors2.json (pairing) and
// data/vectors.json (her brain), both written by tools/test.mjs.
import XCTest
import Foundation
@testable import OPUlationCore

final class CoreTests: XCTestCase {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    func json(_ name: String) throws -> [String: Any] { try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("data/" + name))) as! [String: Any] }
    func bytes(_ v: Any?) -> [UInt8] { [UInt8](hex: v as! String)! }

    func testPairingMatchesWeb() throws {
        let v = try json("vectors2.json")
        let her = Pair.female(flags: [.relay, .multipeer], sk: bytes(v["herSk"]), room: bytes(v["room"]))
        XCTAssertEqual(her.face.hex, v["face"] as? String)
        let face = try XCTUnwrap(Pair.parseFace(her.face))
        let him = Pair.male(face: face, flags: [.relay], sk: bytes(v["hisSk"]))
        XCTAssertEqual(him.hello.hex, v["hello"] as? String)
        let k = try Pair.derive(him), kf = try Pair.derive(her, hello: Pair.parseHello(him.hello))
        XCTAssertEqual(k.transcript.hex, v["transcript"] as? String)
        XCTAssertEqual(k.song.hex, v["song"] as? String); XCTAssertEqual(k.seed.hex, v["seed"] as? String)
        XCTAssertEqual(k.kHim.hex, v["kHim"] as? String); XCTAssertEqual(k.kHer.hex, v["kHer"] as? String)
        XCTAssertEqual(kf.song.hex, k.song.hex)
        let sm = Pair.Session(role: .male, keys: k), sf = Pair.Session(role: .female, keys: kf)
        XCTAssertEqual(sm.seal(Pair.Msg.nest, [0x4a] + Array("hello".utf8)).hex, v["hisFirstSealed"] as? String)
        XCTAssertEqual(sf.seal(Pair.Msg.accept).hex, v["herFirstSealed"] as? String)
        // and they open each other's, once
        let w = sm.seal(Pair.Msg.nest, [1, 2, 3]); XCTAssertEqual(sf.open(w)?.body, [1, 2, 3]); XCTAssertNil(sf.open(w))
    }
    func testBrainMatchesWeb() throws {
        let v = try json("vectors.json")
        let D = try BrainData(earJSON: Data(contentsOf: root.appendingPathComponent("data/ear.json")), earBin: Data(contentsOf: root.appendingPathComponent("data/ear.bin")),
                              model: Data(contentsOf: root.appendingPathComponent("data/female-model.json")))
        let seed = bytes(v["seed"]), tag = bytes(v["tag"]), pers = personality(seed: seed, n: D.meta.n)
        XCTAssertEqual(Array(pers.prefix(16)).hex, v["personality16"] as? String)
        let brain = FemaleBrain(D, pers: pers), sy = KeySong.symbols(tag), L = KeySong.Listener(brain: brain, expected: sy)
        var trace: [Int64] = []; L.onFrame = { st, _ in trace.append(st.R) }
        L.advance(sy, final: true)
        XCTAssertEqual(trace.count, v["frames"] as? Int)
        XCTAssertEqual(L.last?.R, (v["R"] as? NSNumber)?.int64Value)
        XCTAssertEqual(Int64(brain.digest()), (v["digest"] as? NSNumber)?.int64Value)
        XCTAssertEqual(L.verdict, v["verdict"] as? String)
        XCTAssertEqual([50, 200, 400, 600].map { trace[$0] }, (v["Rat"] as? [NSNumber])?.map { $0.int64Value })
    }
    func testFaceRoundTrip() throws {
        // draw her face into a greyscale image at an angle, read it back
        let p = Pair.random(41), bits = FlyCode.facetBits(p), w = 640, h = 480
        let Hm = FlyCode.homography([(0, 0), (1000, 0), (1000, 1000), (0, 1000)], [(140, 70), (520, 95), (510, 455), (125, 430)])
        let img = raster(bits, w, h, Hm)
        let r = FlyCode.read(img, w, h); XCTAssertEqual(r?.payload, p)
    }
    func testSongThroughDetector() throws {
        let D = try BrainData(earJSON: Data(contentsOf: root.appendingPathComponent("data/ear.json")), earBin: Data(contentsOf: root.appendingPathComponent("data/ear.bin")),
                              model: Data(contentsOf: root.appendingPathComponent("data/female-model.json")))
        let sy = KeySong.symbols(Pair.random(16)), x = KeySong.renderAir(KeySong.schedule(sy, D.M), D.M)
        var got: [Int]? = nil; let det = KeySong.Detector(D.M, sampleRate: 48000); det.onSong = { got = $0 }
        var i = 0; while i < x.count { det.push(Array(x[i..<min(x.count, i + 1024)])); i += 1024 }; det.push([Float](repeating: 0, count: 9600)); det.flush()
        XCTAssertEqual(got, sy)
    }
    /** a plain renderer of her face (the test's camera) */
    func raster(_ bits: [UInt8], _ w: Int, _ h: Int, _ Hm: FlyCode.H) -> [UInt8] {
        let m = Hm, A = m[4] * m[8] - m[5] * m[7], B = -(m[3] * m[8] - m[5] * m[6]), C = m[3] * m[7] - m[4] * m[6], det = m[0] * A + m[1] * B + m[2] * C
        let inv = [A / det, -(m[1] * m[8] - m[2] * m[7]) / det, (m[1] * m[5] - m[2] * m[4]) / det, B / det, (m[0] * m[8] - m[2] * m[6]) / det, -(m[0] * m[5] - m[2] * m[3]) / det, C / det, -(m[0] * m[7] - m[1] * m[6]) / det, (m[0] * m[4] - m[1] * m[3]) / det]
        var img = [UInt8](repeating: 236, count: w * h)
        for py in 0..<h { for px in 0..<w {
            let (x, y) = FlyCode.apply(inv, Double(px) + 0.5, Double(py) + 0.5)
            if x < 0 || y < 0 || x > 1000 || y > 1000 { img[py * w + px] = 40; continue }
            var v: UInt8 = 236
            for E in FlyCode.eyes { let u = (x - E.cx) / E.rx, q = (y - E.cy) / E.ry; if u * u + q * q <= 1 { v = 200 } }
            for (i, c) in FlyCode.cells.enumerated() where abs(x - c.x) < 12 && abs(y - c.y) < 12 { let dx = abs(x - c.x), dy = abs(y - c.y), r = FlyCode.FR
                if dy <= r * 0.866 && dx * 0.866 + dy * 0.5 <= r * 0.866 { v = bits[i] == 1 ? 38 : 250 } }
            for (fx, fy) in FlyCode.finders where (x - fx) * (x - fx) + (y - fy) * (y - fy) <= FlyCode.finderR * FlyCode.finderR { v = 20 }
            img[py * w + px] = v
        } }
        return img
    }
}
