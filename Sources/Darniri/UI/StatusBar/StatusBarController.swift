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
        button.image = Self.statusIcon()
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

    private static func statusIcon() -> NSImage {
        let image: NSImage
        if let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "png"),
           let bundled = NSImage(contentsOf: url)
        {
            if let retinaURL = Bundle.main.url(forResource: "StatusIcon@2x", withExtension: "png"),
               let retinaData = try? Data(contentsOf: retinaURL),
               let retina = NSBitmapImageRep(data: retinaData)
            {
                retina.size = NSSize(width: 18, height: 18)
                bundled.addRepresentation(retina)
            }
            image = bundled
        } else {
            // Standalone SwiftPM runs have no app-bundle resources.
            image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
                NSColor.black.setStroke()
                for rect in [
                    NSRect(x: 2, y: 2, width: 5, height: 14),
                    NSRect(x: 8.5, y: 8.5, width: 7.5, height: 6),
                    NSRect(x: 8.5, y: 2, width: 6.5, height: 5)
                ] {
                    let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
                    path.lineWidth = 1.2
                    path.stroke()
                }
                let orbit = NSBezierPath()
                orbit.move(to: NSPoint(x: 0.8, y: 6))
                orbit.curve(
                    to: NSPoint(x: 17.2, y: 12),
                    controlPoint1: NSPoint(x: 0, y: -1),
                    controlPoint2: NSPoint(x: 18.5, y: 3)
                )
                orbit.lineWidth = 1
                orbit.stroke()
                return true
            }
        }
        image.size = NSSize(width: 18, height: 18)
        image.accessibilityDescription = "Darniri"
        image.isTemplate = true
        return image
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
