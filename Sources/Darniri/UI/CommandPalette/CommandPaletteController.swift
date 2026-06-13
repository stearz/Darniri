import AppKit
import ApplicationServices
import SwiftUI

struct CommandPaletteWindowItem: Identifiable {
    let id: WindowToken
    let handle: WindowHandle
    let title: String
    let appName: String
    let appIcon: NSImage?
    let workspaceName: String
}

struct CommandPaletteAppSnapshot: Equatable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?
    let isTerminated: Bool

    init(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        localizedName: String?,
        isTerminated: Bool
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.isTerminated = isTerminated
    }

    init(app: NSRunningApplication) {
        processIdentifier = app.processIdentifier
        bundleIdentifier = app.bundleIdentifier
        localizedName = app.localizedName
        isTerminated = app.isTerminated
    }
}

struct CommandPaletteSummonAnchor: Equatable {
    let token: WindowToken
    let workspaceId: WorkspaceDescriptor.ID
}

private struct CommandPaletteFocusTarget {
    let app: CommandPaletteAppSnapshot
    let focusedWindow: AXUIElement?
}

enum CommandPaletteSelectionID: Hashable {
    case window(WindowToken)
}

enum CommandPaletteSelectionTrigger {
    case primary
    case alternate
}

@MainActor
struct CommandPaletteEnvironment {
    var frontmostApplication: () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }
    var runningApplication: (pid_t) -> NSRunningApplication? = { NSRunningApplication(processIdentifier: $0) }
    var activateDarniri: () -> Void = { NSApp.activate(ignoringOtherApps: true) }
    var navigateToWindow: (WMController, WindowHandle) -> Void = { controller, handle in
        controller.navigateToCommandPaletteWindow(handle)
    }

    var summonWindowRight: (WMController, WindowHandle, WindowToken, WorkspaceDescriptor.ID) -> Void = {
        controller,
        handle,
        anchorToken,
        anchorWorkspaceId in
        controller.summonCommandPaletteWindowRight(
            handle,
            anchorToken: anchorToken,
            anchorWorkspaceId: anchorWorkspaceId
        )
    }
}

@MainActor
final class CommandPaletteController: NSObject, ObservableObject, NSWindowDelegate {
    struct InlineHint: Equatable {
        let title: String
        let shortcut: String
    }

    @Published private(set) var isVisible = false
    @Published var searchText = "" {
        didSet { updateSelectionAfterFilterChange() }
    }

    @Published var selectedMode: CommandPaletteMode = .windows {
        didSet { handleModeChange(from: oldValue) }
    }

    @Published var selectedItemID: CommandPaletteSelectionID?
    @Published private(set) var windows: [CommandPaletteWindowItem] = [] {
        didSet { updateSelectionAfterFilterChange() }
    }

    private let environment: CommandPaletteEnvironment
    private let motionPolicy: MotionPolicy
    private let ownedWindowRegistry: OwnedWindowRegistry
    private var panel: NSPanel?
    private var eventMonitor: Any?

    private weak var wmController: WMController?
    private var restoreFocusTarget: CommandPaletteFocusTarget?
    private var summonAnchor: CommandPaletteSummonAnchor?
    private var isProgrammaticDismiss = false

    private enum DismissReason {
        case cancel
        case selection
        case deactivation
        case superseded
    }

    private enum SelectionAction {
        case navigateWindow(WMController, WindowHandle)
        case summonWindowRight(WMController, WindowHandle, CommandPaletteSummonAnchor)
    }

    init(
        motionPolicy: MotionPolicy,
        environment: CommandPaletteEnvironment = .init(),
        ownedWindowRegistry: OwnedWindowRegistry = .shared
    ) {
        self.motionPolicy = motionPolicy
        self.environment = environment
        self.ownedWindowRegistry = ownedWindowRegistry
        super.init()
    }

    var filteredWindowItems: [CommandPaletteWindowItem] {
        filterWindowItems(windows, query: searchText)
    }

    var isSummonRightAvailable: Bool {
        summonAnchor != nil
    }

    func toggle(wmController: WMController) {
        if isVisible {
            dismiss(reason: .cancel)
        } else {
            show(wmController: wmController)
        }
    }

    func show(wmController: WMController) {
        if isVisible {
            dismiss(reason: .superseded)
        }

        self.wmController = wmController

        restoreFocusTarget = captureFrontmostFocusTarget()
        summonAnchor = Self.resolveSummonAnchor(for: wmController)
        windows = buildWindowItems(from: wmController)
        searchText = ""
        selectedItemID = nil

        if panel == nil {
            createPanel()
        }

        guard let panel else { return }

        positionPanel(panel)

        selectedMode = .windows

        installEventMonitor()

        isVisible = true
        panel.makeKeyAndOrderFront(nil)
        environment.activateDarniri()

        DispatchQueue.main.async { [weak self] in
            self?.focusSearchField()
        }
    }

    static func selectedWindowHint(isSummonRightAvailable: Bool) -> InlineHint? {
        guard isSummonRightAvailable else { return nil }
        return InlineHint(title: "Summon Right", shortcut: "⇧↩")
    }

    static func windowsStatusText(isSummonRightAvailable: Bool) -> String {
        let summonText = if isSummonRightAvailable {
            "Shift-Enter summons right."
        } else {
            "Shift-Enter unavailable for this session."
        }
        return "Enter jumps. \(summonText)"
    }

    static func resolveSummonAnchor(for wmController: WMController) -> CommandPaletteSummonAnchor? {
        guard let activeWorkspace = wmController.activeWorkspace() else { return nil }

        let anchorToken = if let focusedToken = wmController.workspaceManager.focusedToken,
                             let entry = wmController.workspaceManager.entry(for: focusedToken),
                             entry.workspaceId == activeWorkspace.id
        {
            focusedToken
        } else {
            wmController.workspaceManager.lastFocusedToken(in: activeWorkspace.id)
        }

        guard let anchorToken,
              let entry = wmController.workspaceManager.entry(for: anchorToken),
              entry.workspaceId == activeWorkspace.id
        else {
            return nil
        }

        return .init(token: anchorToken, workspaceId: activeWorkspace.id)
    }

    func windowDidResignKey(_: Notification) {
        guard isVisible, !isProgrammaticDismiss else { return }
        dismiss(reason: .deactivation)
    }

    private func handleModeChange(from oldValue: CommandPaletteMode) {
        guard selectedMode != oldValue else { return }
        updateSelectionAfterFilterChange()
        DispatchQueue.main.async { [weak self] in
            self?.focusSearchField()
        }
    }

    private func filterWindowItems(
        _ items: [CommandPaletteWindowItem],
        query rawQuery: String
    ) -> [CommandPaletteWindowItem] {
        let trimmedQuery = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            return items
        }
        let query = trimmedQuery.lowercased()

        let scored: [(CommandPaletteWindowItem, Int)] = items.compactMap { item in
            let titleLower = item.title.lowercased()
            let appLower = item.appName.lowercased()

            if let range = titleLower.range(of: query) {
                let pos = titleLower.distance(from: titleLower.startIndex, to: range.lowerBound)
                return (item, pos)
            }

            if let range = appLower.range(of: query) {
                let pos = appLower.distance(from: appLower.startIndex, to: range.lowerBound)
                return (item, 1000 + pos)
            }

            return nil
        }

        return scored
            .sorted { a, b in
                if a.1 != b.1 { return a.1 < b.1 }
                if a.0.title.count != b.0.title.count { return a.0.title.count < b.0.title.count }
                return a.0.title < b.0.title
            }
            .map(\.0)
    }

    private func buildWindowItems(from wmController: WMController) -> [CommandPaletteWindowItem] {
        let entries = wmController.workspaceManager.allEntries()
        var items: [CommandPaletteWindowItem] = []
        items.reserveCapacity(entries.count)

        for entry in entries {
            guard entry.layoutReason == .standard else { continue }

            let title = AXWindowService.titlePreferFast(windowId: UInt32(entry.windowId)) ?? ""
            let appInfo = wmController.appInfoCache.info(for: entry.handle.pid)
            let workspaceName = wmController.workspaceManager.descriptor(for: entry.workspaceId)?.name ?? "?"

            items.append(CommandPaletteWindowItem(
                id: entry.handle.id,
                handle: entry.handle,
                title: title,
                appName: appInfo?.name ?? "Unknown",
                appIcon: appInfo?.icon,
                workspaceName: workspaceName
            ))
        }

        items.sort { ($0.appName, $0.title) < ($1.appName, $1.title) }
        return items
    }

    private func captureFrontmostFocusTarget() -> CommandPaletteFocusTarget? {
        guard let app = environment.frontmostApplication(),
              !app.isTerminated
        else {
            return nil
        }

        return captureFocusTarget(for: app)
    }

    private func captureFocusTarget(for app: NSRunningApplication) -> CommandPaletteFocusTarget {
        CommandPaletteFocusTarget(
            app: CommandPaletteAppSnapshot(app: app),
            focusedWindow: focusedWindow(for: app)
        )
    }

    private func focusedWindow(for app: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var windowValue: AnyObject?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success else {
            return nil
        }
        guard let windowValue,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeDowncast(windowValue, to: AXUIElement.self)
    }

    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, isVisible else { return event }
            return handleKeyDown(event) ? nil : event
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let relevantModifiers = event.modifierFlags.intersection([.shift, .command, .control, .option])
        let commandOnly = relevantModifiers == .command

        if commandOnly,
           let characters = event.charactersIgnoringModifiers,
           handleModeShortcut(characters)
        {
            return true
        }

        switch event.keyCode {
        case 53:
            dismiss(reason: .cancel)
            return true
        case 126:
            moveSelection(by: -1)
            return true
        case 125:
            moveSelection(by: 1)
            return true
        default:
            guard let trigger = Self.selectionTrigger(
                forKeyCode: event.keyCode,
                modifierFlags: relevantModifiers
            ) else {
                return false
            }
            selectCurrent(trigger: trigger)
            return true
        }
    }

    private static func selectionTrigger(
        forKeyCode keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> CommandPaletteSelectionTrigger? {
        switch keyCode {
        case 36,
             76:
            return modifierFlags == .shift ? .alternate : .primary
        default:
            return nil
        }
    }

    func moveSelection(by delta: Int) {
        let selectionList = currentSelectionList()
        guard !selectionList.isEmpty else { return }

        let currentIndex: Int = if let selectedItemID,
                                   let idx = selectionList.firstIndex(of: selectedItemID)
        {
            idx
        } else {
            0
        }

        let newIndex = (currentIndex + delta + selectionList.count) % selectionList.count
        selectedItemID = selectionList[newIndex]
    }

    func selectCurrent(trigger: CommandPaletteSelectionTrigger = .primary) {
        guard let action = resolvedSelectionAction(for: trigger) else { return }
        dismiss(reason: .selection)
        performSelectionAction(action)
    }

    private func dismiss(reason: DismissReason) {
        removeEventMonitor()
        isVisible = false

        isProgrammaticDismiss = true
        panel?.orderOut(nil)
        isProgrammaticDismiss = false

        let restoreTarget = reason == .cancel ? restoreFocusTarget : nil

        restoreFocusTarget = nil
        summonAnchor = nil
        wmController = nil
        searchText = ""
        selectedItemID = nil
        windows = []

        if let restoreTarget {
            _ = focus(target: restoreTarget)
        }
    }

    private func handleModeShortcut(_ characters: String) -> Bool {
        switch characters {
        case "1":
            selectedMode = .windows
            return true
        default:
            return false
        }
    }

    private func resolvedSelectionAction(
        for trigger: CommandPaletteSelectionTrigger
    ) -> SelectionAction? {
        let filtered = filteredWindowItems
        guard let wmController,
              case let .window(token)? = selectedItemID,
              let item = filtered.first(where: { $0.id == token })
        else {
            return nil
        }
        switch trigger {
        case .primary:
            return .navigateWindow(wmController, item.handle)
        case .alternate:
            guard let summonAnchor else { return nil }
            return .summonWindowRight(wmController, item.handle, summonAnchor)
        }
    }

    private func performSelectionAction(_ action: SelectionAction) {
        switch action {
        case let .navigateWindow(wmController, handle):
            environment.navigateToWindow(wmController, handle)
        case let .summonWindowRight(wmController, handle, summonAnchor):
            environment.summonWindowRight(
                wmController,
                handle,
                summonAnchor.token,
                summonAnchor.workspaceId
            )
        }
    }

    private func focus(target: CommandPaletteFocusTarget) -> Bool {
        guard let app = environment.runningApplication(target.app.processIdentifier),
              !app.isTerminated
        else {
            return false
        }

        if let focusedWindow = target.focusedWindow,
           let windowId = getWindowId(from: focusedWindow)
        {
            SkyLight.shared.orderWindow(UInt32(windowId), relativeTo: 0, order: .above)

            var psn = ProcessSerialNumber()
            if GetProcessForPID(target.app.processIdentifier, &psn) == noErr {
                _ = _SLPSSetFrontProcessWithOptions(&psn, UInt32(windowId), kCPSUserGenerated)
                makeKeyWindow(psn: &psn, windowId: UInt32(windowId))
            }
        }

        app.activate(options: [])
        return true
    }

    private func currentSelectionList() -> [CommandPaletteSelectionID] {
        filteredWindowItems.map { CommandPaletteSelectionID.window($0.id) }
    }

    private func updateSelectionAfterFilterChange() {
        let selectionList = currentSelectionList()
        if selectionList.isEmpty {
            selectedItemID = nil
            return
        }

        if let selectedItemID, !selectionList.contains(selectedItemID) {
            self.selectedItemID = selectionList.first
        } else if selectedItemID == nil {
            selectedItemID = selectionList.first
        }
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 430),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.delegate = self
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.moveToActiveSpace]

        let hostingView = NSHostingView(rootView: makeRootView())
        panel.contentView = hostingView

        ownedWindowRegistry.register(panel)
        self.panel = panel
    }

    private func makeRootView() -> CommandPaletteView {
        CommandPaletteView(controller: self, motionPolicy: motionPolicy)
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = NSScreen.screen(containing: NSEvent.mouseLocation) ?? NSScreen.main else { return }

        let panelWidth: CGFloat = 620
        let panelHeight: CGFloat = 430
        let x = screen.frame.midX - panelWidth / 2
        let y = screen.frame.midY - panelHeight / 2 + 80
        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
    }

    private func findTextField(in view: NSView) -> NSTextField? {
        if let textField = view as? NSTextField, textField.isEditable {
            return textField
        }
        for subview in view.subviews {
            if let found = findTextField(in: subview) {
                return found
            }
        }
        return nil
    }

    private func focusSearchField() {
        guard let contentView = panel?.contentView,
              let textField = findTextField(in: contentView)
        else {
            return
        }
        panel?.makeFirstResponder(textField)
    }

}

private struct CommandPaletteView: View {
    @ObservedObject var controller: CommandPaletteController
    @Bindable var motionPolicy: MotionPolicy

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search windows...", text: $controller.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18))
                    if !controller.searchText.isEmpty {
                        Button(action: { controller.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    Text(
                        CommandPaletteController.windowsStatusText(
                            isSummonRightAvailable: controller.isSummonRightAvailable
                        )
                    )
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if controller.filteredWindowItems.isEmpty {
                CommandPaletteEmptyStateView(
                    symbolName: "macwindow.on.rectangle",
                    text: controller.searchText.isEmpty ? "No windows available" : "No windows found"
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(controller.filteredWindowItems) { item in
                                CommandPaletteWindowRow(
                                    item: item,
                                    isSelected: controller.selectedItemID == .window(item.id),
                                    isSummonRightAvailable: controller.isSummonRightAvailable
                                )
                                .id(CommandPaletteSelectionID.window(item.id))
                                .onTapGesture {
                                    controller.selectedItemID = .window(item.id)
                                    controller.selectCurrent()
                                }
                            }
                        }
                    }
                    .onChange(of: controller.selectedItemID) { _, newValue in
                        if let newValue {
                            if motionPolicy.animationsEnabled {
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    proxy.scrollTo(newValue, anchor: .center)
                                }
                            } else {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 620, height: 430)
        .darniriGlassEffect(in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct CommandPaletteShortcutBadge: View {
    let text: String
    var prominent = false
    var enabled = true

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .opacity(enabled ? 1 : 0.6)
    }

    private var foregroundColor: Color {
        enabled ? (prominent ? .primary : .secondary) : .secondary
    }

    private var backgroundColor: Color {
        prominent ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.14)
    }

    private var borderColor: Color {
        prominent ? Color.accentColor.opacity(0.22) : Color.clear
    }
}

private struct CommandPaletteEmptyStateView: View {
    let symbolName: String
    let text: String

    var body: some View {
        VStack {
            Spacer()
            Image(systemName: symbolName)
                .font(.system(size: 30))
                .foregroundColor(.secondary)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .padding(.top, 8)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CommandPaletteWindowRow: View {
    let item: CommandPaletteWindowItem
    let isSelected: Bool
    let isSummonRightAvailable: Bool

    private var summonHint: CommandPaletteController.InlineHint? {
        guard isSelected else { return nil }
        return CommandPaletteController.selectedWindowHint(isSummonRightAvailable: isSummonRightAvailable)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon = item.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? item.appName : item.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(item.appName)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                if let summonHint {
                    Text(summonHint.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    CommandPaletteShortcutBadge(text: summonHint.shortcut)
                }

                Text(item.workspaceName)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.18))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }
}


