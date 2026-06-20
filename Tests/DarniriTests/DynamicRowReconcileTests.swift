import ApplicationServices
@testable import Darniri
import XCTest

/// Regression coverage for the user-reported bug: at launch a pre-existing workspace (a
/// legacy `[[workspaces]]`-loaded / window-adopted workspace that is the visible/active one)
/// was NOT inserted into `rowOrderByMonitor`. Bootstrap instead minted a brand-new empty row,
/// leaving the dynamic row stack disconnected from the workspace the user actually sees — so
/// cross-row spill/switch (which resolve neighbors via `rowOrderByMonitor`) silently no-op'd.
///
/// `normalizeAllRowStacks()` must now RECONCILE the existing visible workspace INTO the row
/// stack (same id, surrounded by exactly one empty buffer above and below) rather than minting
/// a disconnected fresh row beside it.
@MainActor
final class DynamicRowReconcileTests: XCTestCase {
    // MARK: - Fixtures

    /// A settings store carrying a legacy `[[workspaces]] name = "1"` (main monitor) — exactly
    /// the persisted config the user reported. The configured name lets the workspace be made
    /// visible/active via the legacy `workspaceId(for:createIfMissing:)` path WITHOUT ever
    /// touching `createRow`, which is what produces the disconnect on a real launch.
    private func makeManagerWithLegacyWorkspace() -> WorkspaceManager {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DarniriReconcileTests-\(UUID().uuidString)", isDirectory: true)
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
        settings.workspaceConfigurations = [
            WorkspaceConfiguration(name: "1", monitorAssignment: .main)
        ]
        return WorkspaceManager(settings: settings)
    }

    private func monitorId(_ manager: WorkspaceManager) -> Monitor.ID {
        manager.monitors.first!.id
    }

    private func rowIds(_ manager: WorkspaceManager, on monitorId: Monitor.ID) -> [WorkspaceDescriptor.ID] {
        manager.workspaces(on: monitorId).map(\.id)
    }

    private var nextWindowId = 8_000
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

    /// Reproduce the launch-time disconnect WITHOUT `createRow`: create the persisted workspace
    /// via the legacy named path, make it the monitor's visible/active workspace, and put a
    /// window in it — all while it is absent from `rowOrderByMonitor`.
    private func makeDisconnectedVisibleWorkspace(
        _ manager: WorkspaceManager,
        on mon: Monitor.ID
    ) -> WorkspaceDescriptor.ID {
        let visible = manager.workspaceId(for: "1", createIfMissing: true)!
        XCTAssertTrue(
            manager.setActiveWorkspace(visible, on: mon),
            "Legacy named workspace must become visible/active (mirrors launch restore)"
        )
        _ = addWindow(manager, to: visible)
        return visible
    }

    // MARK: - The bug

    func testVisibleWorkspaceIsReconciledIntoRowStackOnNormalize() {
        let manager = makeManagerWithLegacyWorkspace()
        let mon = monitorId(manager)

        let visible = makeDisconnectedVisibleWorkspace(manager, on: mon)

        // Precondition: the visible/active workspace is NOT yet in the monitor's row stack
        // (this is the disconnect that broke cross-row spill).
        XCTAssertFalse(
            rowIds(manager, on: mon).contains(visible),
            "Precondition: the visible workspace starts disconnected from rowOrderByMonitor"
        )

        // Run the choke-point normalization (fires from enqueueRefresh on a real launch).
        manager.normalizeAllRowStacks()

        // The exact visible id must now be in the stack, surrounded by one empty buffer each
        // side: [emptyBuffer, visible, emptyBuffer].
        let ids = rowIds(manager, on: mon)
        XCTAssertEqual(ids.count, 3, "Expected [emptyTop, visibleContent, emptyBottom]")
        XCTAssertEqual(ids[1], visible, "The SAME visible workspace id is the content row (not a fresh mint)")
        XCTAssertNotEqual(ids[0], visible)
        XCTAssertNotEqual(ids[2], visible)
        XCTAssertTrue(manager.entries(in: ids[0]).isEmpty, "Top buffer is empty")
        XCTAssertTrue(manager.entries(in: ids[2]).isEmpty, "Bottom buffer is empty")
        XCTAssertFalse(manager.entries(in: visible).isEmpty, "Content row keeps its window")

        // And spill can now resolve neighbors FROM the visible row.
        XCTAssertEqual(
            manager.previousWorkspaceInOrder(on: mon, from: visible, wrapAround: false)?.id,
            ids[0],
            "previous from the visible row resolves the top buffer (spill up works)"
        )
        XCTAssertEqual(
            manager.nextWorkspaceInOrder(on: mon, from: visible, wrapAround: false)?.id,
            ids[2],
            "next from the visible row resolves the bottom buffer (spill down works)"
        )
    }

    /// Reconciliation must be idempotent: re-running the choke point does not duplicate the
    /// reconciled id or grow the stack.
    func testReconcileIsIdempotent() {
        let manager = makeManagerWithLegacyWorkspace()
        let mon = monitorId(manager)
        let visible = makeDisconnectedVisibleWorkspace(manager, on: mon)

        manager.normalizeAllRowStacks()
        let first = rowIds(manager, on: mon)
        manager.normalizeAllRowStacks()
        let second = rowIds(manager, on: mon)

        XCTAssertEqual(first, second, "Re-running normalization is a no-op once reconciled")
        XCTAssertEqual(first.filter { $0 == visible }.count, 1, "Visible id is never duplicated")
    }

    /// A genuinely empty monitor (no pre-existing workspace) still bootstraps exactly one
    /// empty row — reconciliation must not change that baseline.
    func testTrulyEmptyMonitorStillBootstrapsOneRow() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DarniriReconcileEmpty-\(UUID().uuidString)", isDirectory: true)
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
        let manager = WorkspaceManager(settings: settings)
        let mon = monitorId(manager)

        manager.normalizeAllRowStacks()

        let ids = rowIds(manager, on: mon)
        XCTAssertEqual(ids.count, 1, "Empty monitor bootstraps exactly one empty row")
        XCTAssertTrue(manager.entries(in: ids[0]).isEmpty)
    }
}
