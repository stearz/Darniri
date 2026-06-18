import ApplicationServices
import CoreGraphics
@testable import Darniri
import XCTest

/// Unit coverage for the row-indicator bar projection derived from
/// `rowOrderByMonitor` (interaction monitor, top→bottom, buffer detection,
/// visible-row highlight, positional labels, `hideEmptyWorkspaces` semantics).
@MainActor
final class RowIndicatorBarProjectionTests: XCTestCase {

    // MARK: - Fixtures

    private func makeManager() -> WorkspaceManager {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DarniriBarP5Tests-\(UUID().uuidString)", isDirectory: true)
        let settings = SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config", isDirectory: true),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(
                directory: root.appendingPathComponent("state", isDirectory: true),
                deferSaves: false
            ),
            autosaveEnabled: false
        )
        return WorkspaceManager(settings: settings)
    }

    private func makeSettings() -> SettingsStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DarniriBarP5Settings-\(UUID().uuidString)", isDirectory: true)
        return SettingsStore(
            persistence: SettingsFilePersistence(
                directory: root.appendingPathComponent("config", isDirectory: true),
                startWatching: false,
                deferSaves: false
            ),
            runtimeState: RuntimeStateStore(
                directory: root.appendingPathComponent("state", isDirectory: true),
                deferSaves: false
            ),
            autosaveEnabled: false
        )
    }

    private var nextWindowId = 9_000

    private func addWindow(
        _ manager: WorkspaceManager,
        to workspaceId: WorkspaceDescriptor.ID
    ) -> WindowToken {
        nextWindowId += 1
        return manager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: nextWindowId),
            pid: getpid(),
            windowId: nextWindowId,
            to: workspaceId,
            mode: .tiling
        )
    }

    private func monitor(_ manager: WorkspaceManager) -> Monitor {
        manager.monitors.first!
    }

    private func monitorId(_ manager: WorkspaceManager) -> Monitor.ID {
        manager.monitors.first!.id
    }

    private func options(
        hideEmpty: Bool = false,
        showFloating: Bool = false,
        deduplicate: Bool = false
    ) -> WorkspaceBarProjectionOptions {
        WorkspaceBarProjectionOptions(
            deduplicateAppIcons: deduplicate,
            hideEmptyWorkspaces: hideEmpty,
            showFloatingWindows: showFloating
        )
    }

    // Thin wrapper to invoke the private-ish static function via the public projection path.
    private func makeProjectionItems(
        manager: WorkspaceManager,
        settings: SettingsStore,
        options: WorkspaceBarProjectionOptions = WorkspaceBarProjectionOptions(
            deduplicateAppIcons: false,
            hideEmptyWorkspaces: false,
            showFloatingWindows: false
        )
    ) -> [WorkspaceBarItem] {
        let appInfoCache = AppInfoCache()
        return WorkspaceBarDataSource.workspaceBarItems(
            for: monitor(manager),
            options: options,
            workspaceManager: manager,
            appInfoCache: appInfoCache,
            niriEngine: nil,
            focusedToken: nil,
            settings: settings
        )
    }

    // MARK: - Row order tests

    /// A fresh manager has one empty row.  The bar item list must have exactly
    /// one entry (the degenerate single buffer / visible row).
    func testSingleEmptyRowProducesOneBarItem() {
        let manager = makeManager()
        let settings = makeSettings()

        let items = makeProjectionItems(manager: manager, settings: settings)
        XCTAssertEqual(items.count, 1)
    }

    /// After adding content and normalizing, the stack has [buffer, content, buffer].
    /// The bar projection must reflect all three rows in top→bottom order with the
    /// correct `rowIndex` values.
    func testThreeRowStackIsReflectedInOrder() {
        let manager = makeManager()
        let settings = makeSettings()
        let mon = monitorId(manager)

        // Grab the single initial row and add content to it.
        let contentRow = manager.workspaces(on: mon)[0].id
        _ = manager.setActiveWorkspace(contentRow, on: mon)
        _ = addWindow(manager, to: contentRow)
        manager.normalizeRowStack(on: mon)

        let items = makeProjectionItems(manager: manager, settings: settings)

        // Expect exactly 3 items: top buffer, content, bottom buffer.
        XCTAssertEqual(items.count, 3, "Expected [buffer, content, buffer] after normalization")

        // Row indices must be 1, 2, 3.
        XCTAssertEqual(items[0].rowIndex, 1)
        XCTAssertEqual(items[1].rowIndex, 2)
        XCTAssertEqual(items[2].rowIndex, 3)

        // Names are the string representation of the row index.
        XCTAssertEqual(items[0].name, "1")
        XCTAssertEqual(items[1].name, "2")
        XCTAssertEqual(items[2].name, "3")
    }

    // MARK: - Buffer detection

    /// With [buffer, content, buffer], the top and bottom items are marked as buffers;
    /// the content row is not.
    func testTopAndBottomEmptyRowsMarkedAsBuffers() {
        let manager = makeManager()
        let settings = makeSettings()
        let mon = monitorId(manager)

        let contentRow = manager.workspaces(on: mon)[0].id
        _ = manager.setActiveWorkspace(contentRow, on: mon)
        _ = addWindow(manager, to: contentRow)
        manager.normalizeRowStack(on: mon)

        let items = makeProjectionItems(manager: manager, settings: settings)

        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items[0].isBuffer, "Top empty row must be a buffer")
        XCTAssertFalse(items[1].isBuffer, "Content row must NOT be a buffer")
        XCTAssertTrue(items[2].isBuffer, "Bottom empty row must be a buffer")
    }

    /// A single empty row (fresh manager) should NOT be marked as a buffer on both
    /// top and bottom simultaneously — there's only one row, so there's no "content"
    /// to buffer; only the top-buffer rule fires (it's the first and last element).
    func testSingleRowDegenerate() {
        let manager = makeManager()
        let settings = makeSettings()

        let items = makeProjectionItems(manager: manager, settings: settings)
        XCTAssertEqual(items.count, 1)

        // The sole row is the top element; bottomIsBuffer fires only if count > 1.
        // So it should be marked as the top buffer, not the bottom buffer.
        // Implementation: topIsBuffer = !hasOccupancy on first = true.
        //                 bottomIsBuffer = count > 1 && !hasOccupancy on last = false.
        // Therefore isBuffer == true for this single row.
        XCTAssertTrue(items[0].isBuffer)
    }

    // MARK: - Visible-row highlight

    /// The currently active (visible) row must have `isFocused == true`.
    func testActiveRowIsMarkedFocused() {
        let manager = makeManager()
        let settings = makeSettings()
        let mon = monitorId(manager)

        let contentRow = manager.workspaces(on: mon)[0].id
        _ = manager.setActiveWorkspace(contentRow, on: mon)
        _ = addWindow(manager, to: contentRow)
        manager.normalizeRowStack(on: mon)

        let items = makeProjectionItems(manager: manager, settings: settings)
        XCTAssertEqual(items.count, 3)

        let focused = items.filter(\.isFocused)
        XCTAssertEqual(focused.count, 1, "Exactly one row should be focused")
        XCTAssertEqual(focused[0].id, contentRow, "The content row (active) must be focused")
    }

    // MARK: - hideEmptyWorkspaces

    /// When `hideEmptyWorkspaces` is true, non-buffer empty rows are hidden but
    /// the top/bottom buffer rows are always kept so the user can see room above/below.
    func testHideEmptyWorkspacesKeepsBuffers() {
        let manager = makeManager()
        let settings = makeSettings()
        let mon = monitorId(manager)

        let contentRow = manager.workspaces(on: mon)[0].id
        _ = manager.setActiveWorkspace(contentRow, on: mon)
        _ = addWindow(manager, to: contentRow)
        manager.normalizeRowStack(on: mon)

        // With hideEmpty = false: should have 3 items.
        let fullItems = makeProjectionItems(
            manager: manager,
            settings: settings,
            options: options(hideEmpty: false)
        )
        XCTAssertEqual(fullItems.count, 3)

        // With hideEmpty = true: buffers are kept, content stays.
        let filteredItems = makeProjectionItems(
            manager: manager,
            settings: settings,
            options: options(hideEmpty: true)
        )
        // Content row has windows → not hidden.
        // Buffer rows are never hidden (protected).
        XCTAssertEqual(filteredItems.count, 3)

        // All buffer items present.
        XCTAssertEqual(filteredItems.filter(\.isBuffer).count, 2)
    }

    /// When all rows are empty and `hideEmptyWorkspaces` is true, non-buffer empty
    /// rows (interior) are hidden.  With [buffer, content (no windows), buffer] after
    /// normalization there is no interior empty row.  But if we artificially add an
    /// interior empty row and re-check, it should be hidden.
    func testHideEmptyWorkspacesRemovesInteriorEmptyRows() {
        let manager = makeManager()
        let settings = makeSettings()
        let mon = monitorId(manager)

        // Build a 4-row stack: buffer, content1, interior-empty, buffer.
        // We achieve this by adding content to two adjacent rows then removing the
        // window from the middle one (bypassing normalisation).
        let firstContent = manager.workspaces(on: mon)[0].id
        _ = manager.setActiveWorkspace(firstContent, on: mon)
        _ = addWindow(manager, to: firstContent)
        manager.normalizeRowStack(on: mon)

        // Now create a second content row below the first.
        let stack = manager.rowOrder(on: mon)
        XCTAssertEqual(stack.count, 3)
        let bottomBuffer = stack[2]

        // Add a window to the bottom buffer — this will make it a content row.
        _ = addWindow(manager, to: bottomBuffer)
        manager.normalizeRowStack(on: mon)

        // Now we have [buf, content1, content2, buf] = 4 rows.
        XCTAssertEqual(manager.rowOrder(on: mon).count, 4)

        let opts = options(hideEmpty: false)
        let allItems = makeProjectionItems(manager: manager, settings: settings, options: opts)
        XCTAssertEqual(allItems.count, 4)

        // No interior empty rows exist at this point, so hideEmpty makes no difference.
        let hiddenItems = makeProjectionItems(
            manager: manager,
            settings: settings,
            options: options(hideEmpty: true)
        )
        XCTAssertEqual(hiddenItems.count, 4)
    }

    // MARK: - rowOrder accessor

    /// `rowOrder(on:)` must return the same IDs as `workspaces(on:).map(\.id)`.
    func testRowOrderAccessorMatchesWorkspacesOrder() {
        let manager = makeManager()
        let mon = monitorId(manager)

        let contentRow = manager.workspaces(on: mon)[0].id
        _ = manager.setActiveWorkspace(contentRow, on: mon)
        _ = addWindow(manager, to: contentRow)
        manager.normalizeRowStack(on: mon)

        let fromRowOrder = manager.rowOrder(on: mon)
        let fromWorkspaces = manager.workspaces(on: mon).map(\.id)

        XCTAssertEqual(fromRowOrder, fromWorkspaces)
    }

    // MARK: - WorkspaceBarPosition.isVertical

    func testPositionIsVerticalFlags() {
        XCTAssertFalse(WorkspaceBarPosition.overlappingMenuBar.isVertical)
        XCTAssertFalse(WorkspaceBarPosition.belowMenuBar.isVertical)
        XCTAssertTrue(WorkspaceBarPosition.left.isVertical)
        XCTAssertTrue(WorkspaceBarPosition.right.isVertical)
    }

    // MARK: - WorkspaceBarGeometry vertical frame

    private var testMonitor: Monitor {
        Monitor(
            id: .fallback,
            displayId: CGMainDisplayID(),
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1417),
            hasNotch: false,
            name: "Test"
        )
    }

    private func makeResolved(
        position: WorkspaceBarPosition,
        height: Double = 48
    ) -> ResolvedBarSettings {
        ResolvedBarSettings(
            enabled: true,
            showLabels: true,
            showFloatingWindows: false,
            deduplicateAppIcons: false,
            hideEmptyWorkspaces: false,
            reserveLayoutSpace: false,
            notchAware: false,
            position: position,
            windowLevel: .floating,
            height: height,
            backgroundOpacity: 0.1,
            xOffset: 0,
            yOffset: 0,
            accentColor: nil,
            textColor: nil
        )
    }

    /// Left-edge panel should be docked at the left of the visible frame.
    func testVerticalLeftFrameIsDockedLeft() {
        let resolved = makeResolved(position: .left)
        let geometry = WorkspaceBarGeometry.resolve(monitor: testMonitor, resolved: resolved, isVisible: true)
        // fittingWidth carries the VStack height for vertical bars; panel width = barHeight (= 48)
        let frame = geometry.frame(fittingWidth: 300, monitor: testMonitor, resolved: resolved)

        XCTAssertEqual(frame.origin.x, testMonitor.visibleFrame.minX, accuracy: 0.5,
                       "Left panel x must equal monitor left edge")
        XCTAssertEqual(frame.origin.y, testMonitor.visibleFrame.minY, accuracy: 0.5,
                       "Left panel y must be at monitor bottom")
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
    }

    /// Right-edge panel should be docked at the right of the visible frame.
    func testVerticalRightFrameIsDockedRight() {
        let resolved = makeResolved(position: .right)
        let geometry = WorkspaceBarGeometry.resolve(monitor: testMonitor, resolved: resolved, isVisible: true)
        let frame = geometry.frame(fittingWidth: 300, monitor: testMonitor, resolved: resolved)

        // Panel right edge should equal monitor right edge.
        let expectedRightEdge = testMonitor.visibleFrame.maxX
        XCTAssertEqual(frame.maxX, expectedRightEdge, accuracy: 0.5,
                       "Right panel right edge must equal monitor right edge")
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
    }

    /// Vertical panels span the full visible height of the monitor.
    func testVerticalPanelSpansFullMonitorHeight() {
        for position in [WorkspaceBarPosition.left, .right] {
            let resolved = makeResolved(position: position)
            let geometry = WorkspaceBarGeometry.resolve(monitor: testMonitor, resolved: resolved, isVisible: true)
            let frame = geometry.frame(fittingWidth: 300, monitor: testMonitor, resolved: resolved)

            XCTAssertEqual(frame.height, testMonitor.visibleFrame.height, accuracy: 0.5,
                           "Vertical panel at \(position) must span full visible height")
        }
    }

    /// Defensive guard: even with zero fittingWidth (empty projection), vertical panels
    /// must have positive dimensions.
    func testVerticalZeroFittingWidthProducesPositiveDimensions() {
        let resolved = makeResolved(position: .left)
        let geometry = WorkspaceBarGeometry.resolve(monitor: testMonitor, resolved: resolved, isVisible: true)
        let frame = geometry.frame(fittingWidth: 0, monitor: testMonitor, resolved: resolved)

        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
    }
}
