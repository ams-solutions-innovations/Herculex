import Foundation
import WatchConnectivity

final class WatchTransport: NSObject, WCSessionDelegate {
    static let shared = WatchTransport()
    let disk = WatchDiskStore(name: "watch-transport")
    var onPacket: ((WatchJSON, @escaping (Bool) -> Void) -> Void)?
    var onStatus: (() -> Void)?
    private var applying = false
    private var context: WatchJSON = [:]
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    var reachable: Bool { session?.isReachable == true }
    var pending: Int { (disk.read("outbox") as? [WatchJSON] ?? []).count }

    func activate() {
        guard let session = session else { return }
        context = disk.read("context") as? WatchJSON ?? [:]
        session.delegate = self
        session.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.drain() }
    }
    // Enqueue on disk before attempting delivery. The receiver acknowledges
    // only after its business transaction (not WC delivery) has committed.
    @discardableResult func enqueue(kind: String, payload: WatchJSON, id: String = UUID().uuidString,
                                   asFile: Bool = false, persist: ((inout WatchJSON) -> Void)? = nil) -> Bool {
        let packet: WatchJSON = ["id": id, "kind": kind, "payload": payload, "file": asFile]
        let saved = disk.update { state in
            persist?(&state)
            var outbox = state["outbox"] as? [WatchJSON] ?? []
            if !outbox.contains(where: { $0["id"] as? String == id }) { outbox.append(packet) }
            state["outbox"] = outbox
        }
        if saved { transmit(packet) }
        onStatus?()
        return saved
    }
    func publish(kind: String, payload: WatchJSON, file: Bool = false) {
        guard let session = session else { return }
        var payload = payload
        payload["snapshotAtEpochMs"] = WatchProtocol.now
        guard disk.update({ state in
            var latest = state["latestSnapshots"] as? WatchJSON ?? [:]
            latest[kind] = payload; state["latestSnapshots"] = latest
        }) else { return }
        if file || WatchProtocol.encode(payload).utf8.count > 48_000 {
            // Retain file payloads in our outbox too: a failed WC file transfer
            // is retried after activation/reconnection rather than forgotten.
            _ = enqueue(kind: kind, payload: payload, asFile: true)
            return
        }
        var candidate = context
        candidate[kind] = payload
        if WatchProtocol.encode(["snapshots_json": WatchProtocol.encode(candidate)]).utf8.count > 48_000 {
            _ = enqueue(kind: kind, payload: payload, asFile: true)
            return
        }
        context[kind] = payload
        _ = disk.update { $0["context"] = context }
        if session.activationState == .activated {
            try? session.updateApplicationContext(["snapshots_json": WatchProtocol.encode(context)])
            if session.isReachable {
                session.sendMessage(["snapshots_json": WatchProtocol.encode([kind: payload])], replyHandler: nil, errorHandler: { _ in })
            }
        }
    }
    private func transmit(_ packet: WatchJSON) {
        guard let session = session, session.activationState == .activated else { return }
        let id = packet["id"] as? String
        // WC dictionaries accept property-list values, which exclude JSON null.
        // Keep opaque business payloads in JSON across every transport path.
        let wire: WatchJSON = ["id": id ?? "", "kind": packet["kind"] as? String ?? "",
                               "payload_json": WatchProtocol.encode(WatchProtocol.json(packet["payload"]))]
        if !session.outstandingUserInfoTransfers.contains(where: { $0.userInfo["id"] as? String == id }) {
            if packet["file"] as? Bool == true || WatchProtocol.encode(wire).utf8.count > 48_000 {
                if session.outstandingFileTransfers.contains(where: { $0.file.metadata?["packetId"] as? String == id }) { return }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("hx-" + (id ?? UUID().uuidString) + ".json")
                if (try? Data(WatchProtocol.encode(packet).utf8).write(to: url, options: .atomic)) != nil {
                    session.transferFile(url, metadata: ["packetId": id ?? ""])
                }
            } else { session.transferUserInfo(wire) }
        }
        // Ordered commands (especially fasting start/stop) use the single
        // ordered user-info queue. Only self-contained snapshots/terminal
        // messages have a parallel fast path.
        let kind = packet["kind"] as? String ?? ""
        if ["workout", "end", "achievement", "requestSync"].contains(kind),
           session.isReachable && WatchProtocol.encode(wire).utf8.count <= 48_000 {
            session.sendMessage(wire, replyHandler: nil, errorHandler: { _ in })
        }
    }
    func flush() {
        guard session?.activationState == .activated else { return }
        for packet in disk.read("outbox") as? [WatchJSON] ?? [] { transmit(packet) }
        if !context.isEmpty { try? session?.updateApplicationContext(["snapshots_json": WatchProtocol.encode(context)]) }
        drain()
        onStatus?()
    }
    func republishSnapshots() {
        let latest = disk.read("latestSnapshots") as? WatchJSON ?? [:]
        for kind in latest.keys.sorted() {
            publish(kind: kind, payload: WatchProtocol.json(latest[kind]), file: kind == "catalog" || kind == "workouts")
        }
    }
    func forgetSession(_ entityId: String) {
        let current = WatchProtocol.decode(WatchProtocol.json(context["session"])["session_json"])
        if current["entityId"] as? String == entityId { context.removeValue(forKey: "session") }
        _ = disk.update { state in
            var latest = state["latestSnapshots"] as? WatchJSON ?? [:]
            let cached = WatchProtocol.decode(WatchProtocol.json(latest["session"])["session_json"])
            if cached["entityId"] as? String == entityId { latest.removeValue(forKey: "session") }
            state["latestSnapshots"] = latest; state["context"] = context
        }
    }
    func request(kind: String, payload: WatchJSON, completion: @escaping (Bool) -> Void) {
        guard let session = session, session.isReachable else { completion(false); return }
        session.sendMessage(["id": UUID().uuidString, "kind": kind, "payload_json": WatchProtocol.encode(payload), "request": true],
                            replyHandler: { reply in DispatchQueue.main.async { completion(reply["applied"] as? Bool == true) } },
                            errorHandler: { _ in DispatchQueue.main.async { completion(false) } })
    }
    private func unpack(_ packet: WatchJSON) -> WatchJSON {
        var decoded = packet
        if let json = packet["payload_json"] as? String { decoded["payload"] = WatchProtocol.decode(json); decoded.removeValue(forKey: "payload_json") }
        return decoded
    }
    private func receive(_ raw: WatchJSON) {
        let packet = unpack(raw)
        if let ack = packet["ack"] as? String {
            _ = disk.update { state in
                state["outbox"] = (state["outbox"] as? [WatchJSON] ?? []).filter { $0["id"] as? String != ack }
                state["lastConfirmedAt"] = WatchProtocol.now
            }
            onStatus?()
            return
        }
        if let json = packet["snapshots_json"] as? String {
            let snapshots = WatchProtocol.decode(json)
            for key in snapshots.keys.sorted() {
                receive(["id": "snapshot-" + key + "-" + WatchProtocol.digest(snapshots[key]!),
                         "kind": key, "payload": snapshots[key]!])
            }
            return
        }
        guard let id = packet["id"] as? String, packet["kind"] is String else { return }
        if (disk.read("seen") as? [String] ?? []).contains(id) { acknowledge(id); return }
        if disk.update({ state in
            var inbox = state["inbox"] as? [WatchJSON] ?? []
            if !inbox.contains(where: { $0["id"] as? String == id }) { inbox.append(packet) }
            state["inbox"] = inbox
        }) { drain() }
    }
    func drain() {
        DispatchQueue.main.async {
            guard !self.applying, let handler = self.onPacket,
                  let packet = (self.disk.read("inbox") as? [WatchJSON])?.first,
                  let id = packet["id"] as? String else { return }
            self.applying = true
            handler(packet) { success in
                DispatchQueue.main.async {
                    self.applying = false
                    guard success else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { self.drain() }
                        return
                    }
                    let saved = self.disk.update { state in
                        state["inbox"] = (state["inbox"] as? [WatchJSON] ?? []).filter { $0["id"] as? String != id }
                        var seen = state["seen"] as? [String] ?? []
                        seen.append(id)
                        state["seen"] = Array(seen.suffix(2048))
                    }
                    if saved { self.acknowledge(id); self.drain() }
                }
            }
        }
    }
    private func acknowledge(_ id: String) {
        guard let session = session, session.activationState == .activated else { return }
        if session.isReachable { session.sendMessage(["ack": id], replyHandler: nil, errorHandler: { _ in }) }
        session.transferUserInfo(["ack": id])
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.flush() }
    }
    func sessionReachabilityDidChange(_ session: WCSession) { DispatchQueue.main.async { self.flush() } }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { DispatchQueue.main.async { self.receive(message) } }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["request"] as? Bool == true {
            DispatchQueue.main.async {
                guard let handler = self.onPacket else { replyHandler(["applied": false]); return }
                handler(self.unpack(message)) { replyHandler(["applied": $0]) }
            }
            return
        }
        // A transport receipt is deliberately not a business acknowledgement.
        replyHandler(["received": true])
        DispatchQueue.main.async { self.receive(message) }
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { DispatchQueue.main.async { self.receive(userInfo) } }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { DispatchQueue.main.async { self.receive(applicationContext) } }
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL),
              let packet = try? JSONSerialization.jsonObject(with: data) as? WatchJSON else { return }
        // Read inside the delegate: WCSession removes its received file on return.
        DispatchQueue.main.async { self.receive(packet) }
    }
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if error == nil { try? FileManager.default.removeItem(at: fileTransfer.file.fileURL) }
    }
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
