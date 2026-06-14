import AppKit
import Foundation
import UserNotifications

@MainActor
final class UpdateChecker: NSObject {
    nonisolated(unsafe) private static let categoryID = "darniri.update"
    nonisolated(unsafe) private static let restartActionID = "restart"
    nonisolated(unsafe) private static let notificationID = "darniri.update.available"

    private let launchVersion: String
    private var checkTimer: Timer?
    private(set) var isUpdateAvailable = false
    var onUpdateAvailable: (() -> Void)?

    override init() {
        launchVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        super.init()
        registerNotificationCategory()
        UNUserNotificationCenter.current().delegate = self
    }

    func start() {
        guard checkTimer == nil else { return }
        checkTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdate() }
        }
    }

    func stop() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    private func checkForUpdate() {
        guard !isUpdateAvailable else { return }
        let infoPlistURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: infoPlistURL),
              let diskVersion = plist["CFBundleShortVersionString"] as? String,
              diskVersion != launchVersion
        else { return }
        isUpdateAvailable = true
        stop()
        onUpdateAvailable?()
        postNotification()
    }

    private func registerNotificationCategory() {
        let restartAction = UNNotificationAction(
            identifier: Self.restartActionID,
            title: "Restart",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [restartAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    private func postNotification() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in self.scheduleNotification() }
        }
    }

    private func scheduleNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Darniri update available"
        content.body = "A new version is ready. Restart to apply it."
        content.categoryIdentifier = Self.categoryID
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.notificationID,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    @MainActor
    static func relaunch() {
        let bundlePath = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$REOPEN_PATH\""
        ]
        task.environment = ["REOPEN_PATH": bundlePath]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}

extension UpdateChecker: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let shouldRestart = response.actionIdentifier == UpdateChecker.restartActionID
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        if shouldRestart {
            Task { @MainActor in UpdateChecker.relaunch() }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
