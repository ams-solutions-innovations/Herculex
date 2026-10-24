import SwiftUI
import WatchKit
import HealthKit
import UserNotifications
import WatchConnectivity

class HerculexWatchDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    private var connectivityTasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var contentObservation: NSKeyValueObservation?
    private var activationObservation: NSKeyValueObservation?
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
        contentObservation = WCSession.default.observe(\.hasContentPending, options: [.new]) { [weak self] _, _ in self?.completeConnectivityTasks() }
        activationObservation = WCSession.default.observe(\.activationState, options: [.new]) { [weak self] _, _ in self?.completeConnectivityTasks() }
    }
    func applicationDidBecomeActive() { WatchStore.shared.transport.flush() }
    func handleActiveWorkoutRecovery() { WorkoutHealth.shared.recover() }
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) { WatchStore.shared.requestSync() }
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        WatchStore.shared.transport.flush()
        for task in backgroundTasks {
            if let task = task as? WKWatchConnectivityRefreshBackgroundTask { connectivityTasks.append(task) }
            else { task.setTaskCompletedWithSnapshot(false) }
        }
        completeConnectivityTasks()
    }
    private func completeConnectivityTasks() {
        DispatchQueue.main.async {
            guard WCSession.default.activationState == .activated, !WCSession.default.hasContentPending else { return }
            // WC delegate callbacks enqueue their durable inbox writes on main.
            // Complete after those writes, so suspension cannot drop a delivery.
            DispatchQueue.main.async {
                self.connectivityTasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
                self.connectivityTasks.removeAll()
            }
        }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

@main
struct HerculexWatchApp: App {
    @WKApplicationDelegateAdaptor(HerculexWatchDelegate.self) var delegate
    @StateObject private var store = WatchStore.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            WatchHomeView().environmentObject(store).tint(HxWatch.cyan)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.transport.flush() }
                }
        }
    }
}
