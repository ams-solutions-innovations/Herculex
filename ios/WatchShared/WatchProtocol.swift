import Foundation
import CryptoKit

typealias WatchJSON = [String: Any]

enum WatchProtocol {
    static let group = "group.com.ams.herculex.watch"
    static func json(_ value: Any?) -> WatchJSON { value as? WatchJSON ?? [:] }
    static func decode(_ value: Any?) -> WatchJSON {
        if let object = value as? WatchJSON { return object }
        guard let string = value as? String, let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        return json(object)
    }
    static func encode(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
    static func array(_ value: Any?) -> [WatchJSON] {
        if let array = value as? [WatchJSON] { return array }
        guard let string = value as? String, let data = string.data(using: .utf8) else { return [] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [WatchJSON] ?? []
    }
    static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    static func digest(_ value: Any) -> String {
        SHA256.hash(data: Data(encode(value).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }
    static func int(_ value: Any?) -> Int { Int(number(value)) }
    static func payload(_ value: WatchJSON) -> WatchJSON { value["payload"] as? WatchJSON ?? value }
    static func day(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    static func envelope(entity: String, id: String, revision: Int64, payload: WatchJSON) -> WatchJSON {
        ["schemaVersion": 2, "entity": entity, "entityId": id, "revision": revision,
         "origin": "watch", "updatedAtEpochMs": now, "payload": payload]
    }
    static func newer(_ lhs: WatchJSON, than rhs: WatchJSON) -> Bool {
        let a = number(lhs["revision"]), b = number(rhs["revision"])
        return a == b ? (lhs["origin"] as? String ?? "") > (rhs["origin"] as? String ?? "") : a > b
    }
    // Keep opaque set metadata intact. Merge the three independently editable
    // fields using the same ordering as WearSyncStamp in Dart/Kotlin.
    static func mergeSet(_ incoming: WatchJSON, local: WatchJSON, fallback: WatchJSON) -> WatchJSON {
        var result = incoming
        let remoteVersions = json(incoming["syncVersions"])
        let localVersions = json(local["syncVersions"])
        var versions = remoteVersions
        for (field, keys) in [("weight", ["weight"]), ("reps", ["reps"]),
                              ("completion", ["completed", "completedAtEpochMs"])] {
            let remoteStamp = remoteVersions[field] as? WatchJSON ?? fallback
            let localStamp = localVersions[field] as? WatchJSON ?? [:]
            if newer(localStamp, than: remoteStamp) {
                for key in keys { result[key] = local[key] }
                versions[field] = localStamp
            } else { versions[field] = remoteStamp }
        }
        result["syncVersions"] = versions
        return result
    }
}

// One atomically replaced file per store. NSRecursiveLock also protects callback
// delivery from WCSession's background delegate queue.
final class WatchDiskStore {
    private let url: URL
    private let lock = NSRecursiveLock()
    private var state: WatchJSON
    init(name: String, shared: Bool = false) {
        let manager = FileManager.default
        let base = (shared ? manager.containerURL(forSecurityApplicationGroupIdentifier: WatchProtocol.group) : nil)
            ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? manager.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent(name + ".json")
        state = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? WatchJSON } ?? [:]
    }
    func read(_ key: String) -> Any? { lock.lock(); defer { lock.unlock() }; return state[key] }
    @discardableResult func update(_ edit: (inout WatchJSON) -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var next = state
        edit(&next)
        do {
            let data = try JSONSerialization.data(withJSONObject: next, options: [.sortedKeys])
            try data.write(to: url, options: .atomic)
            state = next
            return true
        } catch { return false }
    }
}
