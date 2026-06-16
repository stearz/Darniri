import ApplicationServices
@testable import Darniri
import XCTest

/// Unit coverage for the Phase 1 dynamic-row stack: the empty-buffer invariant enforced
/// by `normalizeRowStack`/`normalizeAllRowStacks`, and the `createRow`/`removeRow`
/// ordering primitives.
@MainActor
final class DynamicRowStackTests: XCTestCase {
    // MARK: - Fixtures

    private func makeManager() -> WorkspaceManager {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DarniriRowTests-\(UUID().uuidString)", isDirectory: true)
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

    private func monitorId(_ manager: WorkspaceManager) -> Monitor.ID {
        manager.monitors.first!.id
    }

    private func rowIds(_ manager: WorkspaceManager, on monitorId: Monitor.ID) -> [WorkspaceDescriptor.ID] {
        manager.workspaces(on: monitorId).map(\.id)
    }

    private var nextWindowId = 7_000
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

    // MARK: - Invariant

    func testEmptyMonitorBootstrapsExactlyOneRow() {
        let manager = makeManager()
        let mon = monitorId(manager)

        // A brand-new/empty monitor has exactly ONE empty row (degenerate buffer).
        XCTAssertEqual(rowIds(manager, on: mon).count, 1)
    }

    func testAddingContentYieldsOneEmptyBufferAboveAndBelow() {
        let manager = makeManager()
        let mon = monitorId(manager)

        let contentRow = rowIds(manager, on: mon)[0]
        XCTAssertTrue(manager.setActiveWorkspace(contentRow, on: mon))
        _ = addWindow(manager, to: contentRow)

        manager.normalizeRowStack(on: mon)

        let ids = rowIds(manager, on: mon)
        XCTAssertEqual(ids.count, 3, "Expected [emptyTop, content, emptyBottom]")
        XCTAssertEqual(ids[1], contentRow, "Content row stays in the middle")
        // Top and bottom are fresh, distinct empty buffers.
        XCTAssertNotEqual(ids[0], contentRow)
        XCTAssertNotEqual(ids[2], contentRow)
        XCTAssertTrue(manager.entries(in: ids[0]).isEmpty)
        XCTAssertTrue(manager.entries(in: ids[2]).isEmpty)
        XCTAssertFalse(manager.entries(in: ids[1]).isEmpty)
    }

    func testInteriorEmptyRowsAreRemoved() {
        let manager = makeManager()
        let mon = monitorId(manager)

        // Build a stack with two content rows and an empty interior row between them:
        // [emptyTop, contentA, emptyInterior, contentB, emptyBottom]
        let base = rowIds(manager, on: mon)[0]
        let contentA = base
        let interior = manager.createRow(on: mon, at: 1)
        let contentB = manager.createRow(on: mon, at: 2)
        _ = addWindow(manager, to: contentA)
        _ = addWindow(manager, to: contentB)
        // Keep the user standing on contentA so the visible-row exemption does not apply
        // to the interior row under test.
        XCTAssertTrue(manager.setActiveWorkspace(contentA, on: mon))

        manager.normalizeRowStack(on: mon)

        let ids = rowIds(manager, on: mon)
        XCTAssertFalse(ids.contains(interior), "Empty interior row must be removed")
        // Final shape: one empty buffer top, the two content rows, one empty buffer bottom.
        XCTAssertEqual(ids.count, 4)
        XCTAssertEqual(Set([contentA, contentB]).isSubset(of: Set(ids)), true)
        XCTAssertTrue(manager.entries(in: ids.first!).isEmpty)
        XCTAssertTrue(manager.entries(in: ids.last!).isEmpty)
    }

    func testEdgeEmptyRunsCollapseToOne() {
        let manager = makeManager()
        let mon = monitorId(manager)

        let content = rowIds(manager, on: mon)[0]
        _ = addWindow(manager, to: content)
        XCTAssertTrue(manager.setActiveWorkspace(content, on: mon))

        // Manually create runs of empty rows at both edges.
        _ = manager.createRow(on: mon, at: 0) // extra empty top
        _ = manager.createRow(on: mon, at: 0) // another extra empty top
        let total = rowIds(manager, on: mon).count
        _ = manager.createRow(on: mon, at: total) // extra empty bottom
        _ = manager.createRow(on: mon, at: rowIds(manager, on: mon).count) // another empty bottom

        manager.normalizeRowStack(on: mon)

        let ids = rowIds(manager, on: mon)
        XCTAssertEqual(ids.count, 3, "Edge runs collapse to exactly one empty row each side")
        XCTAssertEqual(ids[1], content)
        XCTAssertTrue(manager.entries(in: ids[0]).isEmpty)
        XCTAssertTrue(manager.entries(in: ids[2]).isEmpty)
    }

    func testVisibleEmptyInteriorRowIsNotDeleted() {
        let manager = makeManager()
        let mon = monitorId(manager)

        // [emptyTop, contentA, visibleEmptyInterior, contentB, emptyBottom]
        let contentA = rowIds(manager, on: mon)[0]
        let interior = manager.createRow(on: mon, at: 1)
        let contentB = manager.createRow(on: mon, at: 2)
        _ = addWindow(manager, to: contentA)
        _ = addWindow(manager, to: contentB)

        // The user is standing on the empty interior row: it must survive normalization.
        XCTAssertTrue(manager.setActiveWorkspace(interior, on: mon))

        manager.normalizeRowStack(on: mon)

        let ids = rowIds(manager, on: mon)
        XCTAssertTrue(ids.contains(interior), "Visible empty interior row must NOT be deleted")
        XCTAssertTrue(manager.entries(in: interior).isEmpty)

        // Once the user navigates away (visible moves to contentA), the now-non-visible
        // empty interior row is reclaimed.
        XCTAssertTrue(manager.setActiveWorkspace(contentA, on: mon))
        manager.normalizeRowStack(on: mon)
        XCTAssertFalse(rowIds(manager, on: mon).contains(interior))
    }

    func testNormalizationIsIdempotent() {
        let manager = makeManager()
        let mon = monitorId(manager)

        let content = rowIds(manager, on: mon)[0]
        _ = addWindow(manager, to: content)
        XCTAssertTrue(manager.setActiveWorkspace(content, on: mon))

        manager.normalizeRowStack(on: mon)
        let first = rowIds(manager, on: mon)
        manager.normalizeRowStack(on: mon)
        let second = rowIds(manager, on: mon)
        XCTAssertEqual(first, second, "Re-running normalization on a normalized stack is a no-op")
    }

    // MARK: - createRow / removeRow ordering

    func testCreateRowInsertsAtRequestedIndex() {
        let manager = makeManager()
        let mon = monitorId(manager)

        let base = rowIds(manager, on: mon)
        XCTAssertEqual(base.count, 1)

        let top = manager.createRow(on: mon, at: 0)
        let bottom = manager.createRow(on: mon, at: 2)
        let middle = manager.createRow(on: mon, at: 1)

        let ids = rowIds(manager, on: mon)
        XCTAssertEqual(ids, [top, middle, base[0], bottom])
    }

    func testCreateRowClampsOutOfRangeIndex() {
        let manager = makeManager()
        let mon = monitorId(manager)
        let base = rowIds(manager, on: mon)[0]

        let appended = manager.createRow(on: mon, at: 999)
        XCTAssertEqual(rowIds(manager, on: mon), [base, appended])

        let prepended = manager.createRow(on: mon, at: -5)
        XCTAssertEqual(rowIds(manager, on: mon), [prepended, base, appended])
    }

    func testRemoveRowDropsFromOrderAndDescriptors() {
        let manager = makeManager()
        let mon = monitorId(manager)
        let base = rowIds(manager, on: mon)[0]
        let extra = manager.createRow(on: mon, at: 1)

        XCTAssertEqual(rowIds(manager, on: mon), [base, extra])
        XCTAssertNotNil(manager.descriptor(for: extra))

        manager.removeRow(extra)

        XCTAssertEqual(rowIds(manager, on: mon), [base])
        XCTAssertNil(manager.descriptor(for: extra), "Removed row descriptor is gone")
    }

    func testNormalizeAllRowStacksBootstrapsAndBuffers() {
        let manager = makeManager()
        let mon = monitorId(manager)

        // Tear the stack down to nothing, then let the choke-point entry rebuild it.
        for id in rowIds(manager, on: mon) {
            manager.removeRow(id)
        }
        XCTAssertEqual(rowIds(manager, on: mon).count, 0)

        manager.normalizeAllRowStacks()
        XCTAssertEqual(rowIds(manager, on: mon).count, 1, "Bootstrap yields exactly one empty row")
    }

    // MARK: - Spill → mint (spec lines ~38-39)

    func testMovingWindowIntoBottomBufferMintsNextBufferBeyondIt() {
        let manager = makeManager()
        let mon = monitorId(manager)

        // Establish the buffered shape [emptyTop, content, emptyBottom].
        let content = rowIds(manager, on: mon)[0]
        XCTAssertTrue(manager.setActiveWorkspace(content, on: mon))
        _ = addWindow(manager, to: content)
        manager.normalizeRowStack(on: mon)

        var ids = rowIds(manager, on: mon)
        XCTAssertEqual(ids.count, 3)
        let bottomBuffer = ids[2]
        XCTAssertTrue(manager.entries(in: bottomBuffer).isEmpty)

        // Simulate a spill: a window moves DOWN into the bottom buffer row. That row is now
        // non-empty, so normalization must mint a FRESH empty buffer below it.
        _ = addWindow(manager, to: bottomBuffer)
        manager.normalizeRowStack(on: mon)

        ids = rowIds(manager, on: mon)
        XCTAssertEqual(ids.count, 4, "A new buffer is minted beyond the now-filled bottom row")
        XCTAssertEqual(ids[2], bottomBuffer, "Former bottom buffer keeps its position, now holds content")
        XCTAssertFalse(manager.entries(in: ids[2]).isEmpty)
        XCTAssertTrue(manager.entries(in: ids[3]).isEmpty, "Fresh empty buffer below")
        XCTAssertNotEqual(ids[3], bottomBuffer)
        XCTAssertTrue(manager.entries(in: ids[0]).isEmpty, "Top buffer remains empty")
    }

    func testMovingWindowIntoTopBufferMintsNextBufferAboveIt() {
        let manager = makeManager()
        let mon = monitorId(manager)

        let content = rowIds(manager, on: mon)[0]
        XCTAssertTrue(manager.setActiveWorkspace(content, on: mon))
        _ = addWindow(manager, to: content)
        manager.normalizeRowStack(on: mon)

        var ids = rowIds(manager, on: mon)
        XCTAssertEqual(ids.count, 3)
        let topBuffer = ids[0]

        // Spill UP into the top buffer; normalization mints a fresh empty buffer above it.
        _ = addWindow(manager, to: topBuffer)
        manager.normalizeRowStack(on: mon)

        ids = rowIds(manager, on: mon)
        XCTAssertEqual(ids.count, 4, "A new buffer is minted above the now-filled top row")
        XCTAssertEqual(ids[1], topBuffer, "Former top buffer shifted down by the new buffer")
        XCTAssertFalse(manager.entries(in: ids[1]).isEmpty)
        XCTAssertTrue(manager.entries(in: ids[0]).isEmpty, "Fresh empty buffer above")
        XCTAssertNotEqual(ids[0], topBuffer)
    }

    // MARK: - Navigation contract: no wrap, stops at the buffer

    func testNextPrevInOrderStopAtBufferWithoutWrap() {
        let manager = makeManager()
        let mon = monitorId(manager)

        let content = rowIds(manager, on: mon)[0]
        XCTAssertTrue(manager.setActiveWorkspace(content, on: mon))
        _ = addWindow(manager, to: content)
        manager.normalizeRowStack(on: mon)

        let ids = rowIds(manager, on: mon)
        XCTAssertEqual(ids.count, 3)
        let topBuffer = ids[0]
        let bottomBuffer = ids[2]

        // From the bottom buffer, "next" (down) must NOT wrap to the top.
        XCTAssertNil(
            manager.nextWorkspaceInOrder(on: mon, from: bottomBuffer, wrapAround: false),
            "next at the bottom buffer stops (no wrap)"
        )
        // From the top buffer, "previous" (up) must NOT wrap to the bottom.
        XCTAssertNil(
            manager.previousWorkspaceInOrder(on: mon, from: topBuffer, wrapAround: false),
            "previous at the top buffer stops (no wrap)"
        )
        // Interior moves still resolve.
        XCTAssertEqual(
            manager.nextWorkspaceInOrder(on: mon, from: content, wrapAround: false)?.id,
            bottomBuffer
        )
        XCTAssertEqual(
            manager.previousWorkspaceInOrder(on: mon, from: content, wrapAround: false)?.id,
            topBuffer
        )
    }

    // MARK: - Adjacent interior empties collapse in one pass

    func testTwoAdjacentInteriorEmptyRowsCollapseInOnePass() {
        let manager = makeManager()
        let mon = monitorId(manager)

        // [emptyTop, contentA, interior1(empty), interior2(empty), contentB, emptyBottom]
        let contentA = rowIds(manager, on: mon)[0]
        let interior1 = manager.createRow(on: mon, at: 1)
        let interior2 = manager.createRow(on: mon, at: 2)
        let contentB = manager.createRow(on: mon, at: 3)
        _ = addWindow(manager, to: contentA)
        _ = addWindow(manager, to: contentB)
        // Stand on contentA so neither interior empty is exempt as the visible row.
        XCTAssertTrue(manager.setActiveWorkspace(contentA, on: mon))

        manager.normalizeRowStack(on: mon)

        let ids = rowIds(manager, on: mon)
        XCTAssertFalse(ids.contains(interior1), "First adjacent interior empty removed in one pass")
        XCTAssertFalse(ids.contains(interior2), "Second adjacent interior empty removed in one pass")
        // Final shape: [emptyTop, contentA, contentB, emptyBottom].
        XCTAssertEqual(ids.count, 4)
        XCTAssertEqual(ids[1], contentA)
        XCTAssertEqual(ids[2], contentB)
        XCTAssertTrue(manager.entries(in: ids[0]).isEmpty)
        XCTAssertTrue(manager.entries(in: ids[3]).isEmpty)
    }

    // MARK: - Visible empty row adjacent to an edge

    func testVisibleEmptyRowAdjacentToEdgeIsNotStrandedAndRemintsAfterLeaving() {
        let manager = makeManager()
        let mon = monitorId(manager)

        // [content, emptyBottom] then stand on the bottom empty row (adjacent to the edge).
        let content = rowIds(manager, on: mon)[0]
        _ = addWindow(manager, to: content)
        manager.normalizeRowStack(on: mon)

        var ids = rowIds(manager, on: mon)
        XCTAssertEqual(ids.count, 3) // [emptyTop, content, emptyBottom]
        let bottomBuffer = ids[2]

        // The user navigates onto the empty bottom buffer (an empty row AT the edge).
        XCTAssertTrue(manager.setActiveWorkspace(bottomBuffer, on: mon))
        manager.normalizeRowStack(on: mon)

        ids = rowIds(manager, on: mon)
        // The visible empty edge row must survive (rule 5 — never pull the floor from under
        // the user). The empty buffer rules (1/2) are already satisfied because the edge row
        // is itself empty, so no extra buffer is minted: the user is standing ON the buffer.
        // This is the spec-acceptable end state (Finding 4): [emptyTop, content, visibleEmptyBottom].
        XCTAssertTrue(ids.contains(bottomBuffer), "Visible empty edge-adjacent row must not be deleted")
        XCTAssertEqual(ids.count, 3, "No extra buffer minted; the visible empty row IS the bottom buffer")
        XCTAssertEqual(ids.last!, bottomBuffer, "User is standing on the bottom buffer itself")
        XCTAssertTrue(manager.entries(in: ids.last!).isEmpty)

        // After navigating away, the stack stays at the canonical
        // [emptyTop, content, emptyBottom] shape, re-minted correctly.
        XCTAssertTrue(manager.setActiveWorkspace(content, on: mon))
        manager.normalizeRowStack(on: mon)

        ids = rowIds(manager, on: mon)
        XCTAssertEqual(ids.count, 3, "Stack collapses back to one buffer per edge")
        XCTAssertEqual(ids[1], content)
        XCTAssertTrue(manager.entries(in: ids[0]).isEmpty)
        XCTAssertTrue(manager.entries(in: ids[2]).isEmpty)
    }

    // MARK: - Independent per-monitor stacks

    func testTwoMonitorsBootstrapAndNormalizeIndependently() {
        let manager = makeManager()

        let primary = manager.monitors.first!
        let secondaryId = Monitor.ID(displayId: primary.displayId &+ 1)
        let secondary = Monitor(
            id: secondaryId,
            displayId: secondaryId.displayId,
            frame: CGRect(x: 2000, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 2000, y: 0, width: 1440, height: 900),
            hasNotch: false,
            name: "Secondary"
        )

        manager.applyMonitorConfigurationChange([primary, secondary])
        manager.normalizeAllRowStacks()

        // Each monitor bootstraps exactly one independent empty row.
        XCTAssertEqual(rowIds(manager, on: primary.id).count, 1)
        XCTAssertEqual(rowIds(manager, on: secondary.id).count, 1)
        XCTAssertTrue(
            Set(rowIds(manager, on: primary.id)).isDisjoint(with: Set(rowIds(manager, on: secondary.id))),
            "The two monitors own distinct rows"
        )

        // Adding content + normalizing one monitor buffers ONLY that monitor.
        let primaryContent = rowIds(manager, on: primary.id)[0]
        XCTAssertTrue(manager.setActiveWorkspace(primaryContent, on: primary.id))
        _ = addWindow(manager, to: primaryContent)
        manager.normalizeAllRowStacks()

        XCTAssertEqual(rowIds(manager, on: primary.id).count, 3, "Primary gains top+bottom buffers")
        XCTAssertEqual(rowIds(manager, on: secondary.id).count, 1, "Secondary stays a single empty row")
    }
}
