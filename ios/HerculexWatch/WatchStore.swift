import Combine
import Foundation
import WatchKit
import WidgetKit
import UserNotifications

final class WatchStore: ObservableObject {
    static let shared = WatchStore()
    @Published var active: WatchJSON?
    @Published var notice: String?
    @Published var status = "Waiting for iPhone"
    @Published var cache: WatchJSON = [:]
    @Published var summary: WatchJSON?
    let transport = WatchTransport.shared
    private let widgets = WatchDiskStore(name: "watch-widgets", shared: true)
    private var retryTimer: Timer?
    var revision: Int64 {
        let previous = Int64(WatchProtocol.number(transport.disk.read("revision")))
        return max(previous + 1, WatchProtocol.now)
    }
    var payload: WatchJSON { active.map(WatchProtocol.payload) ?? [:] }
    var exercises: [WatchJSON] { payload["exercises"] as? [WatchJSON] ?? [] }
    var macros: WatchJSON { WatchProtocol.json(cache["macros"]) }
    func macroValue(_ key: String) -> Double {
        var total = macros["day"] as? String == WatchProtocol.day() ? WatchProtocol.number(macros[key]) : 0
        for packet in transport.disk.read("outbox") as? [WatchJSON] ?? [] {
            let command = WatchProtocol.json(packet["payload"])
            guard command["localDate"] as? String == WatchProtocol.day() else { continue }
            if packet["kind"] as? String == "macroCommand" {
                total += WatchProtocol.number(command[key == "water_ml" ? "waterMl" : key])
            }
            if packet["kind"] as? String == "quickaddCommand" {
                let items = (quickadd["suggested"] as? [WatchJSON] ?? []) + (quickadd["recent"] as? [WatchJSON] ?? []) + (quickadd["recipes"] as? [WatchJSON] ?? [])
                if let food = items.first(where: { item in
                    if let recipeId = command["recipeId"] as? NSNumber { return item["recipeId"] as? NSNumber == recipeId }
                    return item["foodId"] as? NSNumber == command["foodId"] as? NSNumber
                }) {
                    let factor = command["recipeId"] != nil ? WatchProtocol.number(command["portionAmount"]) :
                        WatchProtocol.number(command["portionAmount"]) / max(0.01, WatchProtocol.number(food["portionAmount"]))
                    let foodKey = key == "calories" ? "kcal" : key == "fats" ? "fat" : key
                    total += WatchProtocol.number(food[foodKey]) * factor
                }
            }
        }
        return total
    }
    var fasting: WatchJSON {
        var result = WatchProtocol.payload(WatchProtocol.json(cache["fasting"]))
        for packet in transport.disk.read("outbox") as? [WatchJSON] ?? [] where packet["kind"] as? String == "fastingCommand" {
            let command = WatchProtocol.json(packet["payload"])
            if command["action"] as? String == "start" {
                result["hasActiveFast"] = true
                result["startedAtEpochMs"] = command["startedAtEpochMs"]
                result["targetSeconds"] = command["targetSeconds"]
            } else {
                result["hasActiveFast"] = false
                result["lastFastDurationSeconds"] = max(0, (WatchProtocol.number(command["endedAtEpochMs"]) - WatchProtocol.number(command["startedAtEpochMs"])) / 1000)
                result.removeValue(forKey: "startedAtEpochMs")
            }
        }
        return result
    }
    var workouts: [WatchJSON] {
        WatchProtocol.array(WatchProtocol.json(cache["workouts"])["workouts_json"])
            .sorted { isToday($0) && !isToday($1) }
    }
    var catalog: [WatchJSON] { WatchProtocol.array(WatchProtocol.json(cache["catalog"])["catalog_json"]) }
    var quickadd: WatchJSON { WatchProtocol.decode(WatchProtocol.json(cache["quickadd"])["quickadd_json"]) }
    func isToday(_ item: WatchJSON) -> Bool {
        item["scheduledToday"] as? Bool == true && item["scheduledDate"] as? String == WatchProtocol.day()
    }
    init() {
        active = transport.disk.read("active") as? WatchJSON
        summary = transport.disk.read("summary") as? WatchJSON
        cache = transport.disk.read("cache") as? WatchJSON ?? [:]
        transport.onPacket = { [weak self] packet, done in
            guard let self = self else { done(false); return }
            if packet["kind"] as? String == "rest" {
                let args = WatchProtocol.json(packet["payload"])
                _ = self.scheduleRest(WatchProtocol.decode(args["rest_json"]), completion: done)
                return
            }
            done(self.receive(packet))
        }
        transport.onStatus = { [weak self] in self?.refreshStatus() }
        transport.activate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.transport.flush() }
        WorkoutHealth.shared.onMetrics = { [weak self] _, _ in self?.objectWillChange.send() }
        WorkoutHealth.shared.recover()
        refreshStatus()
    }
    func refreshStatus() {
        let pending = transport.pending
        if pending > 0 { status = "\(pending) pending · " + (transport.reachable ? "syncing" : "offline") }
        else if let confirmed = transport.disk.read("lastConfirmedAt") as? NSNumber {
            let date = Date(timeIntervalSince1970: confirmed.doubleValue / 1000)
            status = "Synced " + date.formatted(date: .omitted, time: .shortened)
        } else { status = transport.reachable ? "iPhone connected" : "Offline · saved on watch" }
    }
    func requestSync() {
        _ = transport.enqueue(kind: "requestSync", payload: [:])
        transport.flush()
    }
    private func receive(_ packet: WatchJSON) -> Bool {
        let kind = packet["kind"] as? String ?? ""
        let args = WatchProtocol.json(packet["payload"])
        if kind == "session" { return receiveSession(WatchProtocol.decode(args["session_json"])) }
        if kind == "end" {
            let id = args["entity_id"] as? String ?? ""
            guard !id.isEmpty else { return false }
            if active?["entityId"] as? String == id { finish(discard: false, notifyPhone: true) }
            return rememberTerminal(id)
        }
        if kind == "healthOwnership" {
            let id = args["entityId"] as? String ?? ""
            let ownership = WatchProtocol.json(args["ownership"])
            guard transport.disk.update({ state in
                var owners = state["healthOwners"] as? WatchJSON ?? [:]
                owners[id] = ownership; state["healthOwners"] = owners
            }) else { return false }
            WorkoutHealth.shared.resolveOwnership(id: id, ownership: ownership)
            return true
        }
        if kind == "rest" { return scheduleRest(WatchProtocol.decode(args["rest_json"])) }
        if kind == "achievement" {
            let item = WatchProtocol.decode(args["achievement_json"])
            notice = [item["label"] as? String, item["value"] as? String].compactMap { $0 }.joined(separator: " · ")
            WKInterfaceDevice.current().play(.success)
            return true
        }
        guard ["macros", "cns", "fasting", "quickadd", "catalog", "workouts"].contains(kind) else { return false }
        if kind != "fasting",
           WatchProtocol.number(WatchProtocol.json(cache[kind])["snapshotAtEpochMs"]) > WatchProtocol.number(args["snapshotAtEpochMs"]) { return true }
        var next = cache
        if kind == "fasting" {
            let remote = WatchProtocol.decode(args["fasting_json"])
            let local = WatchProtocol.json(cache["fasting"])
            if !local.isEmpty && !WatchProtocol.newer(remote, than: local) { return true }
            next[kind] = remote
        } else { next[kind] = args }
        guard transport.disk.update({ $0["cache"] = next }) else { return false }
        cache = next
        projectWidgets()
        return true
    }
    private func receiveSession(_ incoming: WatchJSON) -> Bool {
        guard let id = incoming["entityId"] as? String,
              WatchProtocol.int(incoming["schemaVersion"]) == 2 else { return false }
        if (transport.disk.read("terminal") as? [String] ?? []).contains(id) { return true }
        if let currentId = active?["entityId"] as? String, currentId != id {
            notice = "Another workout is active on iPhone. This workout stays on your watch."
            return true
        }
        var merged = incoming
        var body = WatchProtocol.payload(incoming)
        if let local = active {
            // Structural changes follow the envelope revision; live values
            // follow their independent stamps even when envelopes cross.
            let localBody = WatchProtocol.payload(local)
            let incomingWins = WatchProtocol.newer(incoming, than: local)
            let remoteExercises = body["exercises"] as? [WatchJSON] ?? []
            let localExercises = localBody["exercises"] as? [WatchJSON] ?? []
            var chosen = incomingWins ? remoteExercises : localExercises
            let other = incomingWins ? localExercises : remoteExercises
            for i in chosen.indices {
                guard let id = chosen[i]["wireId"] as? String,
                      let peer = other.first(where: { $0["wireId"] as? String == id }) else { continue }
                var sets = chosen[i]["sets"] as? [WatchJSON] ?? []
                let peerSets = peer["sets"] as? [WatchJSON] ?? []
                for j in sets.indices {
                    if let id = sets[j]["wireId"] as? String,
                       let peerSet = peerSets.first(where: { $0["wireId"] as? String == id }) {
                        sets[j] = WatchProtocol.mergeSet(sets[j], local: peerSet, fallback: incomingWins ? incoming : local)
                    }
                }
                chosen[i]["sets"] = sets
            }
            if !incomingWins { merged = local; body = localBody }
            body["exercises"] = chosen
        }
        merged["payload"] = body
        guard transport.disk.update({ state in
            state["active"] = merged
            state["revision"] = max(WatchProtocol.number(state["revision"]), WatchProtocol.number(incoming["revision"]))
        }) else { return false }
        let isNew = active == nil
        active = merged
        if isNew {
            WorkoutHealth.shared.start(id: id, start: Date(timeIntervalSince1970: WatchProtocol.number(body["startedAtEpochMs"]) / 1000))
            claimHealth()
        }
        projectWidgets()
        return true
    }
    private func claimHealth() {
        guard active != nil else { return }
        var body = payload
        body["healthExport"] = ["owner": "watch", "status": "pending"]
        commit(body, action: "healthClaim")
    }
    func start(_ template: WatchJSON?) {
        guard active == nil else { notice = "Finish the active workout first."; return }
        let template = template ?? ["id": "empty", "name": "Free workout", "exercises": []]
        let id = UUID().uuidString
        let body: WatchJSON = ["template": template, "startedAtEpochMs": WatchProtocol.now,
                              "currentExerciseIndex": 0, "currentSetIndex": 0,
                              "healthExport": ["owner": "watch", "status": "pending"],
                              "exercises": (template["exercises"] as? [WatchJSON] ?? []).map(makeExercise)]
        let envelope = WatchProtocol.envelope(entity: "active_workout", id: id, revision: revision, payload: body)
        guard send(envelope, action: "updated") else { return }
        active = envelope
        WorkoutHealth.shared.start(id: id, start: Date())
        projectWidgets()
    }
    func makeExercise(_ template: WatchJSON) -> WatchJSON {
        let planned = template["plannedSets"] as? [WatchJSON] ?? []
        let count = max(1, WatchProtocol.int(template["targetSets"]))
        let sets = planned.isEmpty ? (0..<count).map { i in
            ["wireId": "watch_set_" + UUID().uuidString, "setIndex": i + 1,
             "weight": 0, "reps": 0, "completed": false, "setType": "standard"] as WatchJSON
        } : planned.enumerated().map { i, row -> WatchJSON in
            var set = row
            set["wireId"] = "watch_set_" + UUID().uuidString
            set["setIndex"] = i + 1
            set["weight"] = 0; set["reps"] = 0; set["completed"] = false
            return set
        }
        return ["wireId": "watch_exercise_" + UUID().uuidString, "template": template, "sets": sets,
                "supersetGroup": template["supersetGroup"] ?? NSNull()]
    }
    @discardableResult private func send(_ envelope: WatchJSON, action: String, saveTemplate: Bool = false, terminal: Bool = false) -> Bool {
        let id = UUID().uuidString
        let event: WatchJSON = ["eventId": id, "action": action, "session_json": WatchProtocol.encode(envelope), "saveAsTemplate": saveTemplate]
        let saved = transport.enqueue(kind: "workout", payload: event, id: id) { state in
            state["revision"] = envelope["revision"]
            if terminal {
                state.removeValue(forKey: "active")
                state["summary"] = envelope
                var snapshots = state["healthWorkoutSnapshots"] as? WatchJSON ?? [:]
                snapshots[envelope["entityId"] as! String] = envelope
                state["healthWorkoutSnapshots"] = snapshots
                var ended = state["terminal"] as? [String] ?? []
                ended.append(envelope["entityId"] as! String)
                state["terminal"] = ended
            } else { state["active"] = envelope }
        }
        if !saved { notice = "Could not save. Please try again." }
        return saved
    }
    func commit(_ body: WatchJSON, action: String = "updated") {
        guard let id = active?["entityId"] as? String else { return }
        let envelope = WatchProtocol.envelope(entity: "active_workout", id: id, revision: revision, payload: body)
        if send(envelope, action: action) { active = envelope; projectWidgets() }
    }
    func mutateExercises(_ change: (inout [WatchJSON]) -> Void) {
        var body = payload; var list = exercises
        change(&list); body["exercises"] = list; commit(body)
    }
    func addExercise(_ template: WatchJSON, replacing: Int? = nil) {
        mutateExercises { list in
            if let index = replacing, list.indices.contains(index) { list[index] = makeExercise(template) }
            else { list.append(makeExercise(template)) }
        }
    }
    func saveSet(exercise: Int, index: Int, set: WatchJSON, completed: Bool) {
        guard exercises.indices.contains(exercise) else { return }
        let before = exercises[exercise]["sets"] as? [WatchJSON] ?? []
        guard before.indices.contains(index) else { return }
        var edited = set
        let stamp: WatchJSON = ["revision": revision, "origin": "watch"]
        edited["completed"] = completed
        if completed { edited["completedAtEpochMs"] = WatchProtocol.now }
        var versions = WatchProtocol.json(edited["syncVersions"])
        for (field, key) in [("weight", "weight"), ("reps", "reps"), ("completion", "completed")] {
            if WatchProtocol.encode(["v": before[index][key] ?? NSNull()]) != WatchProtocol.encode(["v": edited[key] ?? NSNull()]) {
                versions[field] = stamp
            }
        }
        edited["syncVersions"] = versions
        mutateExercises { list in var sets = before; sets[index] = edited; list[exercise]["sets"] = sets }
        if completed {
            evaluatePR(exercise: exercise, set: edited, previous: before)
            startRest(seconds: 90)
            WKInterfaceDevice.current().play(.success)
        }
    }
    func appendSet(_ index: Int) {
        mutateExercises { list in
            guard list.indices.contains(index) else { return }
            var sets = list[index]["sets"] as? [WatchJSON] ?? []
            sets.append(["wireId": "watch_set_" + UUID().uuidString, "setIndex": sets.count + 1,
                         "weight": 0, "reps": 0, "completed": false, "setType": "standard"])
            list[index]["sets"] = sets
        }
    }
    func finish(discard: Bool, saveTemplate: Bool = false, notifyPhone: Bool = true) {
        guard let session = active, let id = session["entityId"] as? String else { return }
        var body = payload
        body["endedAtEpochMs"] = WatchProtocol.now
        body["activeEnergyKcal"] = WorkoutHealth.shared.energy
        let final = WatchProtocol.envelope(entity: "active_workout", id: id, revision: revision, payload: body)
        guard send(final, action: discard ? "discarded" : "finished", saveTemplate: saveTemplate, terminal: true) else { return }
        summary = discard ? nil : final
        active = nil
        cancelRest()
        WorkoutHealth.shared.finish(id: id, discard: discard)
        projectWidgets()
    }
    @discardableResult private func rememberTerminal(_ id: String) -> Bool {
        transport.disk.update { state in
            var ended = state["terminal"] as? [String] ?? []
            if !ended.contains(id) { ended.append(id) }; state["terminal"] = ended
        }
    }
    @discardableResult func healthSaved(id: String, uuid: String) -> Bool {
        let archived = WatchProtocol.json(transport.disk.read("healthWorkoutSnapshots"))[id] as? WatchJSON
        let raw = active?["entityId"] as? String == id ? active : archived ?? transport.disk.read("summary") as? WatchJSON
        guard let source = raw, source["entityId"] as? String == id else { return false }
        var body = WatchProtocol.payload(source)
        body["healthExport"] = ["owner": "watch", "status": "saved", "healthKitUuid": uuid]
        let envelope = WatchProtocol.envelope(entity: "active_workout", id: id, revision: revision, payload: body)
        let eventId = UUID().uuidString
        return transport.enqueue(kind: "workout", payload: ["eventId": eventId, "action": "healthSaved", "session_json": WatchProtocol.encode(envelope)], id: eventId) { state in
            var snapshots = state["healthWorkoutSnapshots"] as? WatchJSON ?? [:]
            snapshots.removeValue(forKey: id); state["healthWorkoutSnapshots"] = snapshots
        }
    }
    func command(_ kind: String, values: WatchJSON) {
        var command = values
        command["commandId"] = UUID().uuidString
        command["createdAtEpochMs"] = WatchProtocol.now
        command["localDate"] = WatchProtocol.day()
        if transport.enqueue(kind: kind, payload: command, id: command["commandId"] as! String) {
            WKInterfaceDevice.current().play(.success)
            notice = transport.reachable ? "Saved · syncing with iPhone" : "Saved on watch · waiting for iPhone"
            objectWillChange.send()
        } else { notice = "Could not save. Please try again." }
    }
    func toggleFast(hours: Int = 16) {
        let running = fasting["hasActiveFast"] as? Bool == true
        let now = WatchProtocol.now
        let target = running ? WatchProtocol.int(fasting["targetSeconds"]) : hours * 3600
        var values: WatchJSON = ["action": running ? "stop" : "start", "targetSeconds": target, "completed": running]
        values["startedAtEpochMs"] = running ? fasting["startedAtEpochMs"] : now
        if running { values["endedAtEpochMs"] = now }
        command("fastingCommand", values: values)
        projectWidgets()
    }
    func startRest(seconds: Int) {
        _ = scheduleRest(["endsAtEpochMs": WatchProtocol.now + Int64(seconds * 1000), "totalSeconds": seconds, "alert": true])
    }
    func cancelRest() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["herculex-rest"])
        _ = transport.disk.update { $0.removeValue(forKey: "rest") }; objectWillChange.send()
    }
    var restEnd: Date? {
        let ms = WatchProtocol.number(WatchProtocol.json(transport.disk.read("rest"))["endsAtEpochMs"])
        return ms > 0 ? Date(timeIntervalSince1970: ms / 1000) : nil
    }
    private func scheduleRest(_ rest: WatchJSON, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard active != nil else { completion?(false); return false }
        if let id = rest["entityId"] as? String, id != active?["entityId"] as? String { completion?(false); return false }
        let endsAt = WatchProtocol.number(rest["endsAtEpochMs"]) / 1000
        guard transport.disk.update({ $0["rest"] = rest }) else { completion?(false); return false }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["herculex-rest"])
        let remaining = endsAt - Date().timeIntervalSince1970
        if rest["alert"] as? Bool == true && remaining > 0 {
            let content = UNMutableNotificationContent()
            content.title = "It's go time"
            content.body = rest["label"] as? String ?? "Time for your next set"
            content.sound = .default
            let request = UNNotificationRequest(identifier: "herculex-rest", content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false))
            center.getNotificationSettings { settings in
                guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                    completion?(false); return
                }
                DispatchQueue.main.async {
                    // Authorization and scheduling callbacks can return after
                    // a newer timer/cancel. Never reinstall the old alert.
                    guard WatchProtocol.number(WatchProtocol.json(self.transport.disk.read("rest"))["endsAtEpochMs"]) == WatchProtocol.number(rest["endsAtEpochMs"]) else {
                        completion?(false); return
                    }
                    center.add(request) { error in
                        DispatchQueue.main.async {
                            let current = WatchProtocol.number(WatchProtocol.json(self.transport.disk.read("rest"))["endsAtEpochMs"])
                            completion?(error == nil && current == WatchProtocol.number(rest["endsAtEpochMs"]))
                        }
                    }
                }
            }
        } else { completion?(true) }
        objectWillChange.send()
        return true
    }
    private func projectWidgets() {
        var projected = cache
        projected["fasting"] = fasting
        var projectedMacros = macros
        for key in ["calories", "protein", "carbs", "fats", "water_ml"] { projectedMacros[key] = macroValue(key) }
        projectedMacros["day"] = WatchProtocol.day()
        projected["macros"] = projectedMacros
        _ = widgets.update { $0["cache"] = projected; $0["active"] = active ?? [:]; $0["updatedAt"] = WatchProtocol.now }
        WidgetCenter.shared.reloadAllTimelines()
    }
    private func evaluatePR(exercise: Int, set: WatchJSON, previous: [WatchJSON]) {
        guard set["isWarmup"] as? Bool != true else { return }
        let template = WatchProtocol.json(exercises[exercise]["template"])
        let weight = WatchProtocol.number(set["weight"]), reps = WatchProtocol.number(set["reps"])
        func estimate(_ w: Double, _ r: Double) -> Double {
            guard w > 0 && r >= 1 else { return 0 }
            if r == 1 { return w }
            return r <= 12 ? (w * (1 + r / 30) + w * 36 / (37 - r)) / 2 : w * (1 + r / 30)
        }
        let baseline = max(estimate(WatchProtocol.number(template["prevWeight"]), WatchProtocol.number(template["prevReps"])),
                           previous.filter { $0["completed"] as? Bool == true && $0["isWarmup"] as? Bool != true }.map { estimate(WatchProtocol.number($0["weight"]), WatchProtocol.number($0["reps"])) }.max() ?? 0)
        if baseline > 0 && estimate(weight, reps) > baseline + 0.4 {
            notice = "🏆 New 1RM PR · " + (template["name"] as? String ?? "Exercise")
        } else {
            let peers = previous.filter { $0["completed"] as? Bool == true && $0["isWarmup"] as? Bool != true }
            let previousWeight = WatchProtocol.number(template["prevWeight"])
            let maximumWeight = max(previousWeight, peers.map { WatchProtocol.number($0["weight"]) }.max() ?? 0)
            let matching = peers.filter { abs(WatchProtocol.number($0["weight"]) - weight) < 0.6 }
            let templateReps = abs(previousWeight - weight) < 0.6 ? WatchProtocol.number(template["prevReps"]) : 0
            let maximumReps = max(templateReps, matching.map { WatchProtocol.number($0["reps"]) }.max() ?? 0)
            if maximumReps > 0 && reps > maximumReps {
                notice = "🏆 Rep PR · " + (template["name"] as? String ?? "Exercise")
            } else if maximumWeight > 0 && weight > maximumWeight + 0.4 {
                notice = "🏆 Weight PR · " + (template["name"] as? String ?? "Exercise")
            }
        }
    }
}
