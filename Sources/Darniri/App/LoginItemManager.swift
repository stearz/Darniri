import Foundation
import Observation
import ServiceManagement

@MainActor @Observable
final class LoginItemManager {
    private static let defaultAppliedKey = "loginItemDefaultApplied"

    let isSupported: Bool
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let statusProvider: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    init(
        isSupported: Bool = LoginItemManager.isInstalledApp(Bundle.main.bundleURL),
        defaults: UserDefaults = .standard,
        statusProvider: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }
    ) {
        self.isSupported = isSupported
        self.defaults = defaults
        self.statusProvider = statusProvider
        self.register = register
        self.unregister = unregister
        refresh()
    }

    nonisolated static func isInstalledApp(_ url: URL) -> Bool {
        // Do not register transient development bundles or standalone executables.
        url.lastPathComponent == "Darniri.app"
            && url.deletingLastPathComponent().lastPathComponent == "Applications"
    }

    func refresh() {
        status = isSupported ? statusProvider() : .notFound
    }

    func applyDefaultIfNeeded() {
        guard isSupported, !defaults.bool(forKey: Self.defaultAppliedKey) else { return }
        refresh()
        guard status == .notRegistered else {
            defaults.set(true, forKey: Self.defaultAppliedKey)
            return
        }
        setEnabled(true)
    }

    func setEnabled(_ enabled: Bool) {
        guard isSupported else { return }
        errorMessage = nil
        refresh()
        do {
            if enabled, status == .notRegistered || status == .notFound {
                try register()
            } else if !enabled, isEnabled {
                try unregister()
            }
            defaults.set(true, forKey: Self.defaultAppliedKey)
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
