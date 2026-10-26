import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privacyChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeSensitiveFilesFromBackup()
    AppleWatchBridge.shared.start()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    AppleWatchBridge.shared.attach(messenger)

    let channel = FlutterMethodChannel(
      name: "com.ams.herculex/storage_privacy",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "excludeFromBackup" {
        self?.excludeSensitiveFilesFromBackup()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    privacyChannel = channel
  }

  /// Marks sensitive local health/physique directories and SQLite database
  /// files with `isExcludedFromBackup = true` so GDPR Art. 9 data and private
  /// body photos never leak into unencrypted iTunes/iCloud backups.
  private func excludeSensitiveFilesFromBackup() {
    let fm = FileManager.default
    let sensitiveDocFolders = ["physique", "progress_photos", "workout_photos", "labs"]
    let sqliteFiles = ["herculex.sqlite", "herculex.sqlite-wal", "herculex.sqlite-shm"]

    if let docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
      for folder in sensitiveDocFolders {
        var dirURL = docsURL.appendingPathComponent(folder, isDirectory: true)
        if !fm.fileExists(atPath: dirURL.path) {
          try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
        markExcluded(&dirURL)
      }
      for dbFile in sqliteFiles {
        var fileURL = docsURL.appendingPathComponent(dbFile, isDirectory: false)
        if fm.fileExists(atPath: fileURL.path) {
          markExcluded(&fileURL)
        }
      }
    }

    if let appSupportURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      if !fm.fileExists(atPath: appSupportURL.path) {
        try? fm.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
      }
      for dbFile in sqliteFiles {
        var fileURL = appSupportURL.appendingPathComponent(dbFile, isDirectory: false)
        if fm.fileExists(atPath: fileURL.path) {
          markExcluded(&fileURL)
        }
      }
    }
  }

  private func markExcluded(_ url: inout URL) {
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
  }
}
