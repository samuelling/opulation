// How sealed frames get between the phones (none is trusted; the courtship authenticates):
//   RelayPipe      the relay (worker/), a WebSocket per phone in her room; works with the web page too
//   MultipeerPipe  Bluetooth + peer-to-peer Wi-Fi between two iPhones (the AirDrop machinery), no network needed
import Foundation
import MultipeerConnectivity

protocol FramePipe: AnyObject {
    var onFrame: (([UInt8]) -> Void)? { get set }
    var onGone: (() -> Void)? { get set }
    var kind: String { get }
    func send(_ b: [UInt8]) async
    func close()
}

final class RelayPipe: FramePipe {
    static var base = URL(string: "wss://opulation-relay.samuelling.workers.dev")!
    var onFrame: (([UInt8]) -> Void)?, onGone: (() -> Void)?, onPeer: (() -> Void)?
    let kind = "relay"
    private(set) var peer = false
    private let task: URLSessionWebSocketTask
    private var pinger: Timer?
    init(room: [UInt8], role: String) {
        var c = URLComponents(url: RelayPipe.base.appendingPathComponent("r/" + room.hex), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "role", value: role)]
        task = URLSession.shared.webSocketTask(with: c.url!); task.maximumMessageSize = 2 << 20
        task.resume(); receive()
        pinger = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in self?.task.send(.string("ping")) { _ in } }
    }
    private func receive() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure: DispatchQueue.main.async { if self.peer { self.peer = false }; self.onGone?() }; return
            case .success(.string(let s)):
                DispatchQueue.main.async {
                    if s == "peer" { self.peer = true; self.onPeer?() } else if s == "gone" { self.peer = false; self.onGone?() }
                }
            case .success(.data(let d)): let b = [UInt8](d); DispatchQueue.main.async { self.onFrame?(b) }
            @unknown default: break
            }
            self.receive()
        }
    }
    func send(_ b: [UInt8]) async { try? await task.send(.data(Data(b))) }
    func close() { pinger?.invalidate(); task.cancel(with: .goingAway, reason: nil) }
}

/** her side advertises her room; his side looks for that room and invites her. Encryption required (and our own on top). */
final class MultipeerPipe: NSObject, FramePipe, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    static let service = "opulation"
    var onFrame: (([UInt8]) -> Void)?, onGone: (() -> Void)?, onConnected: (() -> Void)?
    let kind = "multipeer"
    private let me = MCPeerID(displayName: UIDeviceName.short)
    private lazy var session: MCSession = { let s = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required); s.delegate = self; return s }()
    private var advertiser: MCNearbyServiceAdvertiser?, browser: MCNearbyServiceBrowser?
    private let room: [UInt8]
    private(set) var connected = false
    init(room: [UInt8], role: String) {
        self.room = room; super.init()
        if role == "f" { let a = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: ["r": room.hex], serviceType: Self.service); a.delegate = self; a.startAdvertisingPeer(); advertiser = a }
        else { let b = MCNearbyServiceBrowser(peer: me, serviceType: Self.service); b.delegate = self; b.startBrowsingForPeers(); browser = b }
    }
    func advertiser(_ a: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer p: MCPeerID, withContext c: Data?, invitationHandler h: @escaping (Bool, MCSession?) -> Void) {
        h(c.map { [UInt8]($0) } == room && !connected, session)
    }
    func browser(_ b: MCNearbyServiceBrowser, foundPeer p: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        if info?["r"] == room.hex && !connected { b.invitePeer(p, to: session, withContext: Data(room), timeout: 15) }
    }
    func browser(_ b: MCNearbyServiceBrowser, lostPeer p: MCPeerID) {}
    func session(_ s: MCSession, peer p: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected: if !self.connected { self.connected = true; self.advertiser?.stopAdvertisingPeer(); self.browser?.stopBrowsingForPeers(); self.onConnected?() }
            case .notConnected: if self.connected { self.connected = false; self.onGone?() }
            default: break
            }
        }
    }
    func session(_ s: MCSession, didReceive data: Data, fromPeer p: MCPeerID) { let b = [UInt8](data); DispatchQueue.main.async { self.onFrame?(b) } }
    func session(_ s: MCSession, didReceive stream: InputStream, withName n: String, fromPeer p: MCPeerID) {}
    func session(_ s: MCSession, didStartReceivingResourceWithName n: String, fromPeer p: MCPeerID, with progress: Progress) {}
    func session(_ s: MCSession, didFinishReceivingResourceWithName n: String, fromPeer p: MCPeerID, at url: URL?, withError e: Error?) {}
    func send(_ b: [UInt8]) async { guard !session.connectedPeers.isEmpty else { return }; try? session.send(Data(b), toPeers: session.connectedPeers, with: .reliable) }
    func close() { advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers(); session.disconnect() }
}
import UIKit
enum UIDeviceName { static var short: String { "OPUlation-" + String(UUID().uuidString.prefix(4)) } }

/** a Session over a pipe: sealed control messages, and the nest's items (same framing as js/link.js) */
@MainActor final class Channel {
    let session: Pair.Session; var pipe: FramePipe
    var onControl: ((UInt8, [UInt8]) -> Void)?, onGone: (() -> Void)?
    var onItem: ((NestItem) -> Void)?, onProgress: ((Int, Bool, Double) -> Void)?
    private var rx: (id: Int, kind: String, name: String, type: String, size: Int, data: Data)?
    private var nextId = 0
    private var sendQueue: Task<Void, Never>? = nil
    init(session: Pair.Session, pipe: FramePipe) { self.session = session; self.pipe = pipe; attach() }
    func attach() {
        pipe.onFrame = { [weak self] f in self?.frame(f) }
        pipe.onGone = { [weak self] in self?.onGone?() }
    }
    private func frame(_ f: [UInt8]) {
        guard let m = session.open(f) else { return }
        if m.type == Pair.Msg.nest { nest(m.body) } else { onControl?(m.type, m.body) }
    }
    func control(_ t: UInt8, _ body: [UInt8] = []) { let f = session.seal(t, body); let p = pipe; Task { await p.send(f) } }
    private func sendRaw(_ body: [UInt8]) async { await pipe.send(session.seal(Pair.Msg.nest, body)) }
    private func sendJSON(_ o: [String: Any]) async { let d = try! JSONSerialization.data(withJSONObject: o); await sendRaw([0x4a] + [UInt8](d)) }
    /** send a note, photo or file; items go one at a time, in order */
    func send(_ item: NestItem) -> NestItem {
        nextId += 1; let id = nextId; var out = item; out.id = id; out.incoming = false
        let prev = sendQueue
        sendQueue = Task { [weak self] in
            await prev?.value
            guard let self else { return }
            await self.sendJSON(["id": id, "kind": item.kind, "name": item.name, "type": item.type, "size": item.data.count])
            let chunk = 16384; var o = 0, bytes = [UInt8](item.data)
            while o < bytes.count { let e = min(bytes.count, o + chunk); await self.sendRaw([0x42] + Array(bytes[o..<e])); o = e
                if item.kind != "note" { self.onProgress?(id, false, Double(o) / Double(max(1, bytes.count))) } }
            await self.sendJSON(["id": id, "end": true]); bytes = []
        }
        return out
    }
    private func nest(_ b: [UInt8]) {
        guard let k = b.first else { return }; let d = Array(b.dropFirst())
        if k == 0x4a, let o = try? JSONSerialization.jsonObject(with: Data(d)) as? [String: Any] {
            let id = (o["id"] as? NSNumber)?.intValue ?? 0
            if o["end"] as? Bool == true { if let r = rx, r.id == id { rx = nil; onItem?(NestItem(id: id, incoming: true, kind: r.kind, name: r.name, type: r.type, data: r.data)) } }
            else { rx = (id, o["kind"] as? String ?? "file", o["name"] as? String ?? "file", o["type"] as? String ?? "application/octet-stream", (o["size"] as? NSNumber)?.intValue ?? 0, Data()); if rx!.kind != "note" { onProgress?(id, true, 0) } }
        } else if k == 0x42, rx != nil { rx!.data.append(contentsOf: d); if rx!.kind != "note" { onProgress?(rx!.id, true, Double(rx!.data.count) / Double(max(1, rx!.size))) } }
    }
    func close() { pipe.close() }
}
struct NestItem: Identifiable, Equatable {
    var id: Int = 0; var incoming = false; var kind: String; var name: String; var type: String; var data: Data
    var text: String? { kind == "note" ? String(data: data, encoding: .utf8) : nil }
    static func note(_ t: String) -> NestItem { NestItem(kind: "note", name: "note", type: "text/plain", data: Data(t.utf8)) }
}
