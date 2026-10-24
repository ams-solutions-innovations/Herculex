import Flutter
import Foundation
import UIKit
import WatchConnectivity
import HealthKit

final class AppleWatchBridge {
    static let shared = AppleWatchBridge()
    private var channel: FlutterMethodChannel?
    private var pendingCommand: (String, String, (Bool) -> Void)?
    private let transport = WatchTransport.shared
    func start() {
        transport.onPacket = { [weak self] packet, done in self?.receive(packet, done: done) }
        transport.activate()
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            self.transport.flush()
        }
    }
    func attach(_ messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "com.example.herculex/wear", binaryMessenger: messenger)
        self.channel = channel
        channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
        transport.drain()
    }
    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? WatchJSON ?? [:]
        let snapshots = ["syncMacros": "macros", "syncCnsToWear": "cns", "syncFastingSnapshot": "fasting",
                         "syncQuickAddFoods": "quickadd", "syncWorkouts": "workouts", "syncCatalog": "catalog"]
        if let kind = snapshots[call.method] {
            transport.publish(kind: kind, payload: args, file: kind == "catalog" || kind == "workouts")
            result(nil); return
        }
        switch call.method {
        case "syncAppleHealthOwnership":
            let saved = transport.enqueue(kind: "healthOwnership", payload: args)
            result(saved ? nil : FlutterError(code: "storage", message: "Could not persist Health ownership", details: nil))
        case "syncActiveSession":
            transport.publish(kind: "session", payload: args)
            if args["is_start"] as? Bool == true, WCSession.isSupported(), WCSession.default.isWatchAppInstalled {
                let configuration = HKWorkoutConfiguration()
                configuration.activityType = .traditionalStrengthTraining
                configuration.locationType = .indoor
                HKHealthStore().startWatchApp(with: configuration) { _, _ in }
            }
            result(nil)
        case "endWorkoutOnWatch":
            transport.forgetSession(args["entity_id"] as? String ?? "")
            let saved = transport.enqueue(kind: "end", payload: args)
            result(saved ? nil : FlutterError(code: "storage", message: "Could not persist workout end", details: nil))
        case "sendAchievement":
            _ = transport.enqueue(kind: "achievement", payload: args)
            result(nil)
        case "syncRestTimer":
            transport.request(kind: "rest", payload: args) { result($0) }
        case "checkPendingWatchWorkout":
            transport.flush(); result(nil)
        case "getWatchSyncStatus":
            result(["reachable": transport.reachable, "pending": transport.pending,
                    "lastConfirmedAtEpochMs": transport.disk.read("lastConfirmedAt") ?? 0])
        case "markWatchFastingCommandApplied", "markWatchQuickAddCommandApplied", "markWatchMacroCommandApplied", "markWatchRamblerCommandApplied":
            if let command = pendingCommand, args["command_id"] as? String == command.0, call.method == command.1 {
                pendingCommand = nil; command.2(true)
            }
            result(nil)
        case "markWatchWorkoutApplied": result(nil) // Android compatibility; Apple uses an awaited callback.
        case "syncMediaState", "mediaActionNative", "openMediaControlsPermission": result(nil)
        case "getMediaInfoNative": result(["supported": false])
        default: result(FlutterMethodNotImplemented)
        }
    }
    private func receive(_ packet: WatchJSON, done: @escaping (Bool) -> Void) {
        guard let channel = channel else { done(false); return }
        let payload = WatchProtocol.json(packet["payload"])
        let kind = packet["kind"] as? String ?? ""
        if kind == "workout" {
            channel.invokeMethod("onAppleWatchWorkoutEvent", arguments: payload) { response in
                done((response as? Bool) == true)
            }
        } else if kind == "requestSync" {
            transport.republishSnapshots()
            channel.invokeMethod("onRequestSync", arguments: nil) { response in
                done((response as? Bool) == true)
            }
        } else {
            let methods: [String: (String, String)] = [
                "fastingCommand": ("onWatchFastingCommand", "markWatchFastingCommandApplied"),
                "quickaddCommand": ("onWatchQuickAddCommand", "markWatchQuickAddCommandApplied"),
                "macroCommand": ("onWatchMacroCommand", "markWatchMacroCommandApplied"),
                "ramblerCommand": ("onWatchRamblerCommand", "markWatchRamblerCommandApplied")]
            guard let pair = methods[kind], let id = payload["commandId"] as? String else { done(false); return }
            pendingCommand = (id, pair.1, done)
            channel.invokeMethod(pair.0, arguments: ["command_json": WatchProtocol.encode(payload)])
            DispatchQueue.main.asyncAfter(deadline: .now() + 45) { [weak self] in
                if self?.pendingCommand?.0 == id {
                    self?.pendingCommand = nil
                    done(false)
                }
            }
        }
    }
}
