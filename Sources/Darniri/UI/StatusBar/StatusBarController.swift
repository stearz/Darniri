import AppKit

@MainActor
final class StatusBarController: NSObject {
    nonisolated static let mainAutosaveName = StatusItemPersistence.OwnedItem.main.autosaveName

    private var statusItem: NSStatusItem?
    private var menuBuilder: StatusBarMenuBuilder?
    private var menu: NSMenu?
    private let updateChecker = UpdateChecker()

    private let settings: SettingsStore
    private let statusItemDefaults: UserDefaults
    private weak var controller: WMController?

    init(
        settings: SettingsStore,
        controller: WMController,
        statusItemDefaults: UserDefaults = .standard
    ) {
        self.settings = settings
        self.statusItemDefaults = statusItemDefaults
        self.controller = controller
        super.init()
    }

    func setup() {
        guard statusItem == nil else { return }
        installOwnedStatusItems()
    }

    private func installOwnedStatusItems() {
        guard statusItem == nil, let controller else { return }

        StatusItemPersistence.repairOwnedRestoreState(
            defaults: statusItemDefaults,
            screenFrames: NSScreen.screens.map(\.frame)
        )

        let ownedStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        StatusItemPersistence.configureMandatoryItem(ownedStatusItem, as: .main)
        statusItem = ownedStatusItem

        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "o.circle", accessibilityDescription: "Darniri")
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menuBuilder = StatusBarMenuBuilder(settings: settings, controller: controller)
        menuBuilder.onRestartRequested = { UpdateChecker.relaunch() }
        self.menuBuilder = menuBuilder

        updateChecker.onUpdateAvailable = { [weak self] in
            self?.menuBuilder?.isUpdateAvailable = true
            self?.rebuildMenu()
        }
        updateChecker.start()

        rebuildMenu()
    }

    @objc private func handleClick(_: NSStatusBarButton) {
        showMenu()
    }

    private func showMenu() {
        if menu == nil {
            rebuildMenu()
        } else {
            menuBuilder?.updateToggles()
        }
        guard let button = statusItem?.button, let menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    func refreshMenu() {
        menuBuilder?.updateToggles()
    }

    func rebuildMenu() {
        menu = menuBuilder?.buildMenu()
    }

    func cleanup() {
        updateChecker.stop()
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        menuBuilder = nil
        menu = nil
    }
}
