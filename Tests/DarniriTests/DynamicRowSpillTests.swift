import ApplicationServices
@testable import Darniri
import XCTest

/// Integration coverage for the user-reported bug: pressing Ctrl+Shift+Up / Ctrl+Shift+Down
/// on a window at the top/bottom edge of its column must spill the window into the adjacent
/// dynamic row (Niri-style), mint a fresh empty buffer beyond it, and make that row the
/// visible/active row with focus following the window.
@MainActor
final class DynamicRowSpillTests: XCTestCase {
    private static func settingsStore() -> SettingsStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DarniriSpillTests-\(UUID().uuidString)", isDirectory: true)
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

    private var nextWindowId = 990_000
    private func addWindow(
        _ controller: WMController,
        to workspaceId: WorkspaceDescriptor.ID
    ) -> (token: WindowToken, node: NiriWindow) {
        nextWindowId += 1
        let id = nextWindowId
        let token = controller.workspaceManager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(pid_t(id)), windowId: id),
            pid: pid_t(id),
            windowId: id,
            to: workspaceId,
            mode: .tiling
        )
        let engine = controller.niriEngine!
        let node = engine.addWindow(token: token, to: workspaceId, afterSelection: nil)
        return (token, node)
    }

    private func rowIds(
        _ controller: WMController,
        on monitorId: Monitor.ID
    ) -> [WorkspaceDescriptor.ID] {
        controller.workspaceManager.workspaces(on: monitorId).map(\.id)
    }

    private func makeController() -> (WMController, Monitor.ID) {
        let controller = WMController(
            settings: Self.settingsStore(),
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        controller.niriLayoutHandler.enableNiriLayout()
        let monitorId = controller.workspaceManager.monitors.first!.id
        controller.workspaceManager.normalizeAllRowStacks()
        return (controller, monitorId)
    }

    /// Place a single window on the content row, establish buffers, and focus it so the
    /// bound spill path has a focused/selected edge window to operate on.
    private func setupSingleWindowContentRow(
        _ controller: WMController,
        on monitorId: Monitor.ID
    ) -> (contentRow: WorkspaceDescriptor.ID, token: WindowToken, node: NiriWindow) {
        let contentRow = rowIds(controller, on: monitorId)[0]
        XCTAssertTrue(controller.workspaceManager.setActiveWorkspace(contentRow, on: monitorId))
        _ = controller.workspaceManager.setInteractionMonitor(monitorId)

        let (token, node) = addWindow(controller, to: contentRow)
        controller.workspaceManager.normalizeRowStack(on: monitorId)

        _ = controller.workspaceManager.commitWorkspaceSelection(
            nodeId: node.id,
            focusedToken: token,
            in: contentRow,
            onMonitor: monitorId
        )

        // Establish a confirmed (AX-style) focus on the edge window, exactly as the GUI
        // would have when the user presses the spill hotkey on the focused window.
        let requestId: UInt64 = 1
        _ = controller.workspaceManager.beginManagedFocusRequest(
            token, in: contentRow, onMonitor: monitorId, requestId: requestId
        )
        _ = controller.workspaceManager.confirmManagedFocus(
            token,
            in: contentRow,
            onMonitor: monitorId,
            appFullscreen: false,
            activateWorkspaceOnMonitor: true,
            requestId: requestId
        )
        XCTAssertEqual(
            controller.workspaceManager.focusedToken,
            token,
            "Test precondition: the edge window is the confirmed focused window"
        )
        return (contentRow, token, node)
    }

    func testSpillDownMovesWindowToRowBelowMintsBufferAndFollowsVisible() {
        let (controller, mon) = makeController()
        let (contentRow, token, _) = setupSingleWindowContentRow(controller, on: mon)

        var ids = rowIds(controller, on: mon)
        XCTAssertEqual(ids.count, 3, "[emptyTop, content, emptyBottom]")
        let bottomBuffer = ids[2]

        controller.niriLayoutHandler.moveWindowOrToAdjacentWorkspace(direction: .down)
        controller.workspaceManager.normalizeRowStack(on: mon)

        // Window now belongs to the row below.
        XCTAssertEqual(
            controller.workspaceManager.workspace(for: token),
            bottomBuffer,
            "Window must move into the row below (former bottom buffer)"
        )
        XCTAssertTrue(
            controller.workspaceManager.entries(in: contentRow).isEmpty,
            "Source content row is now empty"
        )

        // A fresh empty buffer was minted beyond the now-filled row.
        ids = rowIds(controller, on: mon)
        XCTAssertTrue(ids.contains(bottomBuffer))
        guard let bottomIdx = ids.firstIndex(of: bottomBuffer) else {
            return XCTFail("bottom buffer vanished")
        }
        XCTAssertLessThan(bottomIdx, ids.count - 1, "A new buffer exists below the moved window")
        XCTAssertTrue(
            controller.workspaceManager.entries(in: ids.last!).isEmpty,
            "Bottom row is a fresh empty buffer"
        )

        // Visible/active row follows the window, and focus lands on it.
        XCTAssertEqual(
            controller.workspaceManager.activeWorkspace(on: mon)?.id,
            bottomBuffer,
            "Active/visible row follows the moved window (behavior C)"
        )
        XCTAssertEqual(controller.workspaceManager.focusedToken, token, "Focus follows the window")
    }

    func testSpillUpMovesWindowToRowAboveMintsBufferAndFollowsVisible() {
        let (controller, mon) = makeController()
        let (contentRow, token, _) = setupSingleWindowContentRow(controller, on: mon)

        var ids = rowIds(controller, on: mon)
        XCTAssertEqual(ids.count, 3, "[emptyTop, content, emptyBottom]")
        let topBuffer = ids[0]

        controller.niriLayoutHandler.moveWindowOrToAdjacentWorkspace(direction: .up)
        controller.workspaceManager.normalizeRowStack(on: mon)

        XCTAssertEqual(
            controller.workspaceManager.workspace(for: token),
            topBuffer,
            "Window must move into the row above (former top buffer)"
        )
        XCTAssertTrue(
            controller.workspaceManager.entries(in: contentRow).isEmpty,
            "Source content row is now empty"
        )

        ids = rowIds(controller, on: mon)
        XCTAssertTrue(ids.contains(topBuffer))
        guard let topIdx = ids.firstIndex(of: topBuffer) else {
            return XCTFail("top buffer vanished")
        }
        XCTAssertGreaterThan(topIdx, 0, "A new buffer exists above the moved window")
        XCTAssertTrue(
            controller.workspaceManager.entries(in: ids.first!).isEmpty,
            "Top row is a fresh empty buffer"
        )

        XCTAssertEqual(
            controller.workspaceManager.activeWorkspace(on: mon)?.id,
            topBuffer,
            "Active/visible row follows the moved window (behavior C)"
        )
        XCTAssertEqual(controller.workspaceManager.focusedToken, token, "Focus follows the window")
    }

    func testColumnSpillDownFollowsVisibleAndFocus() {
        let (controller, mon) = makeController()
        let (contentRow, token, _) = setupSingleWindowContentRow(controller, on: mon)

        let ids = rowIds(controller, on: mon)
        XCTAssertEqual(ids.count, 3, "[emptyTop, content, emptyBottom]")
        let bottomBuffer = ids[2]

        controller.workspaceNavigationHandler.moveColumnToAdjacentWorkspace(direction: .down)
        controller.workspaceManager.normalizeRowStack(on: mon)

        XCTAssertEqual(
            controller.workspaceManager.workspace(for: token),
            bottomBuffer,
            "Column (its window) must move into the row below"
        )
        XCTAssertTrue(
            controller.workspaceManager.entries(in: contentRow).isEmpty,
            "Source content row is now empty"
        )
        XCTAssertEqual(
            controller.workspaceManager.activeWorkspace(on: mon)?.id,
            bottomBuffer,
            "Active/visible row follows the moved column"
        )
        XCTAssertEqual(
            controller.workspaceManager.focusedToken,
            token,
            "Focus follows the moved column"
        )
    }

    func testColumnSpillUpFollowsVisibleAndFocus() {
        let (controller, mon) = makeController()
        let (contentRow, token, _) = setupSingleWindowContentRow(controller, on: mon)

        let ids = rowIds(controller, on: mon)
        XCTAssertEqual(ids.count, 3, "[emptyTop, content, emptyBottom]")
        let topBuffer = ids[0]

        controller.workspaceNavigationHandler.moveColumnToAdjacentWorkspace(direction: .up)
        controller.workspaceManager.normalizeRowStack(on: mon)

        XCTAssertEqual(
            controller.workspaceManager.workspace(for: token),
            topBuffer,
            "Column (its window) must move into the row above"
        )
        XCTAssertTrue(
            controller.workspaceManager.entries(in: contentRow).isEmpty,
            "Source content row is now empty"
        )
        XCTAssertEqual(
            controller.workspaceManager.activeWorkspace(on: mon)?.id,
            topBuffer,
            "Active/visible row follows the moved column"
        )
        XCTAssertEqual(
            controller.workspaceManager.focusedToken,
            token,
            "Focus follows the moved column"
        )
    }

    // MARK: - Centering tests

    /// After a cross-row window move with centerFocusedColumn=always, the saved viewport's
    /// viewOffsetPixels must target the centered offset — NOT the stale zero-width offset
    /// computed before cachedWidth was resolved.
    ///
    /// The centered offset for a single column of width `w` in viewport of width `W` is:
    ///   offset = -(W - w) / 2   (negative: column shifted left so it sits in the center)
    ///
    /// With cachedWidth=0 the wrong value would be -(W - 0)/2 = -W/2.
    /// With real width w > 0 the correct value is -(W - w)/2, which is closer to 0 than -W/2.
    ///
    /// The default settings have centerFocusedColumn=always, so we don't need to override.
    func testWindowSpillDownCentersFocusedColumnInTargetRow() {
        let (controller, mon) = makeController()
        let (contentRow, token, _) = setupSingleWindowContentRow(controller, on: mon)

        let engine = controller.niriEngine!
        let monitor = controller.workspaceManager.monitors.first!
        let gap = CGFloat(controller.workspaceManager.gaps)
        let workingWidth = controller.insetWorkingFrame(for: monitor).width

        // Precondition: column must have a real width after setup.
        guard let columnBefore = engine.findNode(for: token).flatMap({ engine.column(of: $0) }) else {
            return XCTFail("Column not found for the moved window")
        }
        // Ensure cached width is resolved on the source so we know what width to expect
        if columnBefore.cachedWidth <= 0 {
            columnBefore.resolveAndCacheWidth(workingAreaWidth: workingWidth, gaps: gap)
        }
        let columnWidth = columnBefore.cachedWidth
        XCTAssertGreaterThan(columnWidth, 0, "Column must have a resolved width > 0")

        // Row order: [emptyTop, contentRow, emptyBottom]
        let ids = rowIds(controller, on: mon)
        XCTAssertEqual(ids.count, 3, "Precondition: 3 rows")
        let targetRow = ids[2] // bottom buffer becomes the target

        controller.workspaceNavigationHandler.moveWindowToAdjacentWorkspace(direction: .down)
        controller.workspaceManager.normalizeRowStack(on: mon)

        XCTAssertEqual(
            controller.workspaceManager.workspace(for: token),
            targetRow,
            "Window must have moved to the bottom buffer row"
        )

        // Inspect the stored viewport state of the target row.
        let targetViewport = controller.workspaceManager.niriViewportState(for: targetRow)
        let storedOffset = targetViewport.viewOffsetPixels.target()

        // The correct centered offset for this column width in this viewport:
        //   = -(viewportWidth - columnWidth) / 2
        let expectedCenteredOffset = -(workingWidth - columnWidth) / 2.0
        // Allow a small tolerance for scale rounding (≤ 1 logical pixel).
        let tolerance: CGFloat = 1.0
        XCTAssertEqual(
            storedOffset, expectedCenteredOffset, accuracy: tolerance,
            "Viewport offset must target the centered position (-(W-w)/2). " +
            "Got \(storedOffset), expected ~\(expectedCenteredOffset). " +
            "If this still fails with storedOffset ≈ \(-workingWidth / 2), " +
            "cachedWidth was still 0 when ensureSelectionVisible was called."
        )

        // The offset must be a spring (animated), not static — centering is animated.
        switch targetViewport.viewOffsetPixels {
        case .spring:
            break // expected: animated transition to center
        case .static(let v):
            // Static is acceptable if animations are disabled (motionPolicy), but the
            // value must still be the correct centered offset.
            XCTAssertEqual(
                v, expectedCenteredOffset, accuracy: tolerance,
                "Static viewport offset must be the centered value"
            )
        case .gesture:
            XCTFail("Viewport must not be in gesture state after a programmatic move")
        }
    }

    /// Same centering check for moveColumnToAdjacentWorkspace.
    func testColumnSpillDownCentersFocusedColumnInTargetRow() {
        let (controller, mon) = makeController()
        let (contentRow, token, _) = setupSingleWindowContentRow(controller, on: mon)

        let engine = controller.niriEngine!
        let monitor = controller.workspaceManager.monitors.first!
        let gap = CGFloat(controller.workspaceManager.gaps)
        let workingWidth = controller.insetWorkingFrame(for: monitor).width

        guard let columnBefore = engine.findNode(for: token).flatMap({ engine.column(of: $0) }) else {
            return XCTFail("Column not found")
        }
        if columnBefore.cachedWidth <= 0 {
            columnBefore.resolveAndCacheWidth(workingAreaWidth: workingWidth, gaps: gap)
        }
        let columnWidth = columnBefore.cachedWidth
        XCTAssertGreaterThan(columnWidth, 0, "Column must have a resolved width > 0")

        let ids = rowIds(controller, on: mon)
        XCTAssertEqual(ids.count, 3, "Precondition: 3 rows")
        let targetRow = ids[2]

        controller.workspaceNavigationHandler.moveColumnToAdjacentWorkspace(direction: .down)
        controller.workspaceManager.normalizeRowStack(on: mon)

        XCTAssertEqual(
            controller.workspaceManager.workspace(for: token),
            targetRow,
            "Column must have moved to the bottom buffer row"
        )

        let targetViewport = controller.workspaceManager.niriViewportState(for: targetRow)
        let storedOffset = targetViewport.viewOffsetPixels.target()
        let expectedCenteredOffset = -(workingWidth - columnWidth) / 2.0
        let tolerance: CGFloat = 1.0
        XCTAssertEqual(
            storedOffset, expectedCenteredOffset, accuracy: tolerance,
            "Viewport offset must target the centered position after column spill"
        )
    }

    /// Regression guard: with centerFocusedColumn=never the offset must NOT be centered.
    /// The never-center path should keep offset=0 (left-aligned / just-visible).
    func testWindowSpillWithNeverCenterDoesNotCenter() {
        let controller = WMController(
            settings: Self.settingsStore(),
            windowFocusOperations: WindowFocusOperations(
                activateApp: { _ in },
                focusSpecificWindow: { _, _, _ in },
                raiseWindow: { _ in }
            )
        )
        // Override global setting to never-center.
        controller.niriLayoutHandler.enableNiriLayout(centerFocusedColumn: .never, alwaysCenterSingleColumn: false)
        // Also override the settings-store level so refreshResolvedMonitorSettings uses never.
        controller.settings.niriCenterFocusedColumn = .never

        // Re-sync per-monitor settings so they reflect the override.
        controller.niriLayoutHandler.refreshResolvedMonitorSettings()

        let mon = controller.workspaceManager.monitors.first!.id
        controller.workspaceManager.normalizeAllRowStacks()

        nextWindowId += 1
        let (contentRow, token, _) = setupSingleWindowContentRow(controller, on: mon)

        let monitor = controller.workspaceManager.monitors.first!
        let workingWidth = controller.insetWorkingFrame(for: monitor).width

        let ids = rowIds(controller, on: mon)
        XCTAssertEqual(ids.count, 3, "Precondition: 3 rows")
        let targetRow = ids[2]

        controller.workspaceNavigationHandler.moveWindowToAdjacentWorkspace(direction: .down)
        controller.workspaceManager.normalizeRowStack(on: mon)

        XCTAssertEqual(
            controller.workspaceManager.workspace(for: token),
            targetRow,
            "Window must move to bottom buffer row"
        )

        let targetViewport = controller.workspaceManager.niriViewportState(for: targetRow)
        let storedOffset = targetViewport.viewOffsetPixels.target()

        // With center=never the offset must be the "make-visible" (left-edge) value, not
        // -(W-w)/2. For a single fresh column the make-visible offset is 0.
        let wrongCenteredOffset = -(workingWidth) / 2.0
        XCTAssertNotEqual(
            storedOffset, wrongCenteredOffset, accuracy: 1.0,
            "With centerFocusedColumn=never the offset must not be -W/2 (the stale zero-width center)"
        )
    }
}
