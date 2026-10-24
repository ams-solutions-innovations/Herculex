import Combine
import Foundation
import HealthKit

final class WorkoutHealth: NSObject, ObservableObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = WorkoutHealth()
    @Published var heartRate: Double = 0
    @Published var energy: Double = 0
    @Published var availability = "Apple Health optional"
    var onMetrics: ((Double, Double) -> Void)?
    private let health = HKHealthStore()
    private let disk = WatchTransport.shared.disk
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var workoutId: String?
    private var finishing = false
    private var preparing = false
    private var pendingBuilders: [String: HKWorkoutBuilder] = [:]
    private var saving: Set<String> = []

    func start(id: String, start: Date) {
        guard workoutId != id, session == nil, !preparing, HKHealthStore.isHealthDataAvailable() else { return }
        heartRate = 0; energy = 0
        preparing = true
        let types: Set<HKSampleType> = [.workoutType(), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        health.requestAuthorization(toShare: types, read: read) { _, error in
            DispatchQueue.main.async {
                self.preparing = false
                guard error == nil, self.health.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
                    self.availability = "Health access off · manual logging available"; return
                }
                guard WatchStore.shared.active?["entityId"] as? String == id else { return }
                do {
                    let configuration = HKWorkoutConfiguration()
                    configuration.activityType = .traditionalStrengthTraining
                    configuration.locationType = .indoor
                    let session = try HKWorkoutSession(healthStore: self.health, configuration: configuration)
                    self.attach(session, id: id)
                    session.startActivity(with: start)
                    self.builder?.beginCollection(withStart: start) { success, error in
                        DispatchQueue.main.async {
                            self.availability = success ? "Recording in Apple Health" : "Health recording unavailable"
                        }
                    }
                } catch { self.availability = "Health recording unavailable" }
            }
        }
    }
    private func attach(_ session: HKWorkoutSession, id: String) {
        self.session = session
        workoutId = id
        heartRate = 0; energy = 0
        session.delegate = self
        let builder = session.associatedWorkoutBuilder()
        self.builder = builder
        builder.delegate = self
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: session.workoutConfiguration)
        builder.addMetadata([HKMetadataKeySyncIdentifier: "com.ams.herculex." + id,
                             HKMetadataKeySyncVersion: 1, "herculexSessionId": id]) { _, _ in }
        _ = disk.update { $0["healthActiveId"] = id }
    }
    func recover() {
        guard session == nil else { return }
        health.recoverActiveWorkoutSession { recovered, _ in
            DispatchQueue.main.async {
                var recoveredId: String?
                if let recovered = recovered, let id = self.disk.read("healthActiveId") as? String {
                    recoveredId = id
                    self.attach(recovered, id: id)
                    let finish = WatchProtocol.json(WatchProtocol.json(self.disk.read("healthFinishes"))[id])
                    if !finish.isEmpty {
                        self.finish(id: id, discard: finish["discard"] as? Bool == true)
                    }
                    self.availability = "Recording in Apple Health"
                }
                for id in WatchProtocol.json(self.disk.read("healthFinishes")).keys where id != recoveredId {
                    self.recoverSaved(id: id)
                }
            }
        }
    }
    func finish(id: String, discard: Bool) {
        guard workoutId == id, let session = session, let builder = builder else { return }
        guard !finishing else { return }
        finishing = true
        let previous = WatchProtocol.json(WatchProtocol.json(disk.read("healthFinishes"))[id])
        let endMs = previous["endedAt"] as? NSNumber ?? NSNumber(value: WatchProtocol.now)
        guard disk.update({ state in
            var finishes = state["healthFinishes"] as? WatchJSON ?? [:]
            finishes[id] = ["discard": discard, "endedAt": endMs]
            state["healthFinishes"] = finishes
        }) else { finishing = false; availability = "Health save pending"; return }
        session.end()
        builder.endCollection(withEnd: Date(timeIntervalSince1970: endMs.doubleValue / 1000)) { success, _ in
            DispatchQueue.main.async {
                self.pendingBuilders[id] = builder
                self.session = nil; self.builder = nil; self.workoutId = nil; self.finishing = false
                if discard {
                    builder.discardWorkout()
                    self.clear(id)
                } else if success {
                    self.saveIfOwned(id: id)
                } else { self.availability = "Health save pending" }
            }
        }
    }
    func resolveOwnership(id: String, ownership: WatchJSON) {
        if ownership["owner"] as? String == "phone", ownership["status"] as? String != "unclaimed" {
            if workoutId == id, session != nil { finish(id: id, discard: true); return }
            pendingBuilders[id]?.discardWorkout()
            clear(id)
            return
        }
        if pendingBuilders[id] != nil { saveIfOwned(id: id) } else { recoverSaved(id: id) }
    }
    private func saveIfOwned(id: String) {
        let ownership = WatchProtocol.json(WatchProtocol.json(disk.read("healthOwners"))[id])
        // A watch-origin workout can save offline. A phone-origin workout must
        // first receive its ownership claim from the phone's SQLite transaction.
        let raw = WatchProtocol.json(WatchProtocol.json(disk.read("healthWorkoutSnapshots"))[id])
        let phoneOrigin = WatchProtocol.json(WatchProtocol.payload(raw)["template"])["id"] as? String == "phone_session"
        guard !phoneOrigin || ownership["owner"] as? String == "watch" else {
            availability = "Health save waiting for iPhone"; return
        }
        guard !saving.contains(id) else { return }
        guard let builder = pendingBuilders[id] else { recoverSaved(id: id); return }
        saving.insert(id)
        findSaved(id: id) { existing in
            if let existing = existing { self.didSave(id: id, uuid: existing); return }
            builder.finishWorkout { workout, _ in
                DispatchQueue.main.async {
                    guard let workout = workout else { self.saving.remove(id); self.availability = "Health save pending"; return }
                    self.didSave(id: id, uuid: workout.uuid.uuidString)
                }
            }
        }
    }
    private func findSaved(id: String, completion: @escaping (String?) -> Void) {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
                                                   allowedValues: ["com.ams.herculex." + id])
        let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, _ in
            DispatchQueue.main.async { completion(samples?.first?.uuid.uuidString) }
        }
        health.execute(query)
    }
    private func recoverSaved(id: String) {
        guard WatchProtocol.json(disk.read("healthFinishes"))[id] != nil else { return }
        guard !saving.contains(id) else { return }
        findSaved(id: id) { existing in
            if let existing = existing { self.didSave(id: id, uuid: existing) }
            else { self.rebuildFinishedWorkout(id: id) }
        }
    }
    private func rebuildFinishedWorkout(id: String) {
        let finish = WatchProtocol.json(WatchProtocol.json(disk.read("healthFinishes"))[id])
        if finish["discard"] as? Bool == true { clear(id); return }
        let snapshot = WatchProtocol.json(WatchProtocol.json(disk.read("healthWorkoutSnapshots"))[id])
        let body = WatchProtocol.payload(snapshot)
        guard let startMs = body["startedAtEpochMs"] as? NSNumber,
              let endMs = body["endedAtEpochMs"] as? NSNumber else { return }
        let owner = WatchProtocol.json(WatchProtocol.json(disk.read("healthOwners"))[id])
        let phoneOrigin = WatchProtocol.json(body["template"])["id"] as? String == "phone_session"
        guard !phoneOrigin || owner["owner"] as? String == "watch", !saving.contains(id) else { return }
        // Only reconstruct sessions that were actually recorded live and whose
        // end was persisted before a crash. The sync identifier is stable.
        saving.insert(id)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining; configuration.locationType = .indoor
        let rebuilt = HKWorkoutBuilder(healthStore: health, configuration: configuration, device: .local())
        let start = Date(timeIntervalSince1970: startMs.doubleValue / 1000)
        let end = Date(timeIntervalSince1970: endMs.doubleValue / 1000)
        rebuilt.beginCollection(withStart: start) { success, _ in
            guard success else { DispatchQueue.main.async { self.saving.remove(id) }; return }
            rebuilt.addMetadata([HKMetadataKeySyncIdentifier: "com.ams.herculex." + id, HKMetadataKeySyncVersion: 1, "herculexSessionId": id]) { _, _ in
                let energy = max(0, WatchProtocol.number(body["activeEnergyKcal"]))
                let samples: [HKSample] = energy > 0 ? [HKQuantitySample(type: HKQuantityType(.activeEnergyBurned), quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energy), start: start, end: end)] : []
                rebuilt.add(samples) { _, _ in
                    rebuilt.endCollection(withEnd: end) { ended, _ in
                        guard ended else { DispatchQueue.main.async { self.saving.remove(id) }; return }
                        rebuilt.finishWorkout { workout, _ in
                            DispatchQueue.main.async {
                                self.saving.remove(id)
                                if let workout = workout { self.didSave(id: id, uuid: workout.uuid.uuidString) }
                            }
                        }
                    }
                }
            }
        }
    }
    private func didSave(id: String, uuid: String) {
        let recorded = disk.update { state in
            var exports = state["healthSaved"] as? WatchJSON ?? [:]
            exports[id] = uuid; state["healthSaved"] = exports
        }
        if recorded && WatchStore.shared.healthSaved(id: id, uuid: uuid) { clear(id) }
        else { saving.remove(id) }
        availability = "Saved in Apple Health"
    }
    private func clear(_ id: String) {
        _ = disk.update { state in
            var finishes = state["healthFinishes"] as? WatchJSON ?? [:]
            finishes.removeValue(forKey: id); state["healthFinishes"] = finishes
            if state["healthActiveId"] as? String == id { state.removeValue(forKey: "healthActiveId") }
            var snapshots = state["healthWorkoutSnapshots"] as? WatchJSON ?? [:]
            snapshots.removeValue(forKey: id); state["healthWorkoutSnapshots"] = snapshots
        }
        pendingBuilders.removeValue(forKey: id); saving.remove(id)
        if workoutId == id { session = nil; builder = nil; workoutId = nil; finishing = false; heartRate = 0; energy = 0 }
    }
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {}
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.availability = "Health recording interrupted · manual logging available" }
    }
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        DispatchQueue.main.async {
            guard self.builder === workoutBuilder else { return }
            if let value = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity() {
                self.heartRate = value.doubleValue(for: .count().unitDivided(by: .minute()))
            }
            if let value = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() {
                self.energy = value.doubleValue(for: .kilocalorie())
            }
            self.onMetrics?(self.heartRate, self.energy)
        }
    }
}
