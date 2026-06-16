import AppKit
import Observation

@MainActor @Observable
public final class AppBootstrapState {
    var settings: SettingsStore?
    var controller: WMController?

    public init() {}

    public var isReady: Bool {
        settings != nil && controller != nil
    }

    public func registerRedirectWindow(_ window: NSWindow) {
        OwnedWindowRegistry.shared.register(window)
    }

    public func unregisterRedirectWindow(_ window: NSWindow) {
        OwnedWindowRegistry.shared.unregister(window)
    }

    public func showSettingsAndCloseRedirectWindow(_ window: NSWindow?) {
        guard let settings, let controller else { return }
        SettingsWindowController.shared.show(
            settings: settings,
            controller: controller
        )
        guard let window else { return }
        unregisterRedirectWindow(window)
        DispatchQueue.main.async {
            window.close()
        }
    }
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public nonisolated(unsafe) weak static var sharedBootstrap: AppBootstrapState?

    public override init() {
        super.init()
    }

    private var statusBarController: StatusBarController?
    private var runtimeStateStore: RuntimeStateStore?

    public func applicationDidFinishLaunching(_: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        bootstrapApplication()
    }

    public func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        return .terminateNow
    }

    public func applicationWillTerminate(_: Notification) {
        if let controller = AppDelegate.sharedBootstrap?.controller {
            controller.serviceLifecycleManager.stop()
            controller.workspaceManager.flushPersistedWindowRestoreCatalogNow()
            // Restore macOS symbolic hotkeys (re-enable Spaces/Mission Control shortcuts).
            controller.symbolicHotkeyController.deactivate()
        }
        AppDelegate.sharedBootstrap?.settings?.flushNow()
        runtimeStateStore?.flushNow()
    }

    func bootstrapApplication() {
        switch AppBootstrapPlanner.decision() {
        case .boot:
            finishBootstrap()
        }
    }

    func finishBootstrap() {
        // Settings-migration epoch persistence deleted under clean-break (PURGE-02);
        // settings.toml IS the source of truth.

        let storagePaths = DarniriStoragePaths.live
        let runtimeState = RuntimeStateStore(directory: storagePaths.stateDirectory)
        self.runtimeStateStore = runtimeState

        let settings = SettingsStore(
            persistence: SettingsFilePersistence(directory: storagePaths.configDirectory),
            runtimeState: runtimeState
        )
        let controller = WMController(settings: settings)
        controller.applyPersistedSettings(settings)

        AppDelegate.sharedBootstrap?.settings = settings
        AppDelegate.sharedBootstrap?.controller = controller

        statusBarController = StatusBarController(
            settings: settings,
            controller: controller
        )
        controller.statusBarController = statusBarController
        settings.onExternalSettingsReloaded = { [weak controller, weak self] in
            guard let controller else { return }
            controller.applyPersistedSettings(settings)
            self?.statusBarController?.refreshMenu()
        }
        statusBarController?.setup()
    }

}
