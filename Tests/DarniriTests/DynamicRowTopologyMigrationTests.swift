import ApplicationServices
@testable import Darniri
import XCTest

/// Coverage: multi-monitor detach/reattach migrates the FULL per-monitor row
/// stack (not just the visible row), never losing windows, and restores remembered rows
/// to a reappearing monitor via `OutputId`. Single-monitor topology churn stays inert.
@MainActor
final class DynamicRowTopologyMigrationTests: XCTestCase {
    // MARK: - Fixtures

    private func makeManager() -> WorkspaceManager {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DarniriTopologyTests-\(UUID().uuidString)", isDirectory: true)
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

    private func rowIds(_ manager: WorkspaceManager, on monitorId: Monitor.ID) -> [WorkspaceDescriptor.ID] {
        manager.workspaces(on: monitorId).map(\.id)
    }

    /// Raw per-monitor stack, NOT filtered to known monitor ids — lets a stranded/orphaned
    /// row under a dead monitor id be detected (`workspaces(on:)` would hide it).
    private func rawRowIds(_ manager: WorkspaceManager, on monitorId: Monitor.ID) -> [WorkspaceDescriptor.ID] {
        manager.rowOrder(on: monitorId)
    }

    /// Total number of windows tracked across all workspaces (no row may swallow a window).
    private func totalWindowCount(_ manager: WorkspaceManager) -> Int {
        manager.allEntries().count
    }

    private var nextWindowId = 9_000
    @discardableResult
    private func addWindow(
        _ manager: WorkspaceManager,
        to workspaceId: WorkspaceDescriptor.ID
    ) -> (token: WindowToken, windowId: Int) {
        nextWindowId += 1
        let windowId = nextWindowId
        let token = manager.addWindow(
            AXWindowRef(element: AXUIElementCreateApplication(getpid()), windowId: windowId),
            pid: getpid(),
            windowId: windowId,
            to: workspaceId,
            mode: .tiling
        )
        return (token, windowId)
    }

    private func secondaryMonitor(_ primary: Monitor, offset: UInt32 = 1) -> Monitor {
        let id = Monitor.ID(displayId: primary.displayId &+ offset)
        return Monitor(
            id: id,
            displayId: id.displayId,
            frame: CGRect(x: 2000, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 2000, y: 0, width: 1440, height: 900),
            hasNotch: false,
            name: "Secondary"
        )
    }

    /// Set up two monitors and return (primary, secondary) after bootstrap+normalize.
    private func makeTwoMonitorManager() -> (manager: WorkspaceManager, primary: Monitor, secondary: Monitor) {
        let manager = makeManager()
        let primary = manager.monitors.first!
        let secondary = secondaryMonitor(primary)
        manager.applyMonitorConfigurationChange([primary, secondary])
        manager.normalizeAllRowStacks()
        return (manager, primary, secondary)
    }

    /// Add `count` distinct content rows (each with one window) to `monitorId`, returning
    /// the content-row ids top→bottom after normalization.
    private func populateContentRows(
        _ manager: WorkspaceManager,
        on monitorId: Monitor.ID,
        count: Int
    ) -> [WorkspaceDescriptor.ID] {
        var created: [WorkspaceDescriptor.ID] = []
        for _ in 0 ..< count {
            // Insert a fresh row just below the current top buffer, fill it, then normalize.
            let id = manager.createRow(on: monitorId, at: 1)
            addWindow(manager, to: id)
            created.append(id)
        }
        manager.normalizeRowStack(on: monitorId)
        // Return them in stack order (filtered to the ones we created, still present).
        let stack = rowIds(manager, on: monitorId)
        return stack.filter { created.contains($0) }
    }

    private func bufferInvariantHolds(_ manager: WorkspaceManager, on monitorId: Monitor.ID) -> Bool {
        let ids = rowIds(manager, on: monitorId)
        guard let first = ids.first, let last = ids.last else { return false }
        if ids.count == 1 { return manager.rowHasNoWindows(first) }
        return manager.rowHasNoWindows(first) && manager.rowHasNoWindows(last)
    }

    // MARK: - Detach migrates ALL rows

    func testDetachMigratesAllContentRowsToSurvivor() {
        let (manager, primary, secondary) = makeTwoMonitorManager()

        // Two content rows on the SECONDARY monitor, each with a window.
        let secondaryContent = populateContentRows(manager, on: secondary.id, count: 2)
        XCTAssertEqual(secondaryContent.count, 2)
        let windowsBefore = secondaryContent.map { manager.entries(in: $0).count }
        XCTAssertEqual(windowsBefore, [1, 1], "Each migrated row holds its window before detach")

        // A content row on the PRIMARY too, so the survivor already has its own stack.
        let primaryContent = populateContentRows(manager, on: primary.id, count: 1).first!

        let totalWindowsBefore = totalWindowCount(manager)

        // Detach the secondary.
        manager.applyMonitorConfigurationChange([primary])

        // All secondary content rows now live in the primary's stack, in order, no loss.
        let primaryStack = rowIds(manager, on: primary.id)
        for rowId in secondaryContent {
            XCTAssertTrue(primaryStack.contains(rowId), "Migrated row \(rowId) is on the survivor")
            XCTAssertEqual(manager.entries(in: rowId).count, 1, "Migrated row keeps its window")
        }
        // Relative order of the migrated rows is preserved.
        let migratedIndices = secondaryContent.map { primaryStack.firstIndex(of: $0)! }
        XCTAssertEqual(migratedIndices, migratedIndices.sorted(), "Migrated rows keep their top→bottom order")
        // The primary's own content row survives.
        XCTAssertTrue(primaryStack.contains(primaryContent))

        // No rows left under the dead monitor id, and the survivor's buffers are correct.
        // Assert on the RAW stack (not `workspaces(on:)`, which filters to known monitor ids
        // and would hide a stranded row leaked under the dead id).
        XCTAssertTrue(rawRowIds(manager, on: secondary.id).isEmpty, "No rows stranded under the detached monitor id")
        // And no row/window vanished: the survivor stack must hold all migrated content rows
        // plus its own, and the global window count is unchanged.
        XCTAssertEqual(
            totalWindowCount(manager),
            totalWindowsBefore,
            "No window lost or duplicated across the detach"
        )
        XCTAssertTrue(bufferInvariantHolds(manager, on: primary.id), "Survivor keeps empty top+bottom buffers")
    }

    // MARK: - Reattach restores remembered rows

    func testReattachRestoresRememberedRowsToFreshStack() {
        let (manager, primary, secondary) = makeTwoMonitorManager()
        let secondaryContent = populateContentRows(manager, on: secondary.id, count: 2)

        // Detach → rows migrate to primary.
        manager.applyMonitorConfigurationChange([primary])
        let primaryAfterDetach = rowIds(manager, on: primary.id)
        for rowId in secondaryContent {
            XCTAssertTrue(primaryAfterDetach.contains(rowId), "Pre-reattach: rows sit on donor")
        }

        // Reattach the SAME monitor (same OutputId: same displayId + name).
        manager.applyMonitorConfigurationChange([primary, secondary])

        // Remembered rows are back on the secondary, in order, with their windows.
        let secondaryStack = rowIds(manager, on: secondary.id)
        for rowId in secondaryContent {
            XCTAssertTrue(secondaryStack.contains(rowId), "Row \(rowId) returned to its monitor")
            XCTAssertEqual(manager.entries(in: rowId).count, 1, "Returned row keeps its window")
        }
        let restoredIndices = secondaryContent.map { secondaryStack.firstIndex(of: $0)! }
        XCTAssertEqual(restoredIndices, restoredIndices.sorted(), "Restored rows keep their order")

        // Donor (primary) no longer holds them.
        let primaryStack = rowIds(manager, on: primary.id)
        for rowId in secondaryContent {
            XCTAssertFalse(primaryStack.contains(rowId), "Donor no longer owns the restored rows")
        }

        // Both stacks normalized.
        XCTAssertTrue(bufferInvariantHolds(manager, on: primary.id))
        XCTAssertTrue(bufferInvariantHolds(manager, on: secondary.id))
    }

    func testReattachByNameWhenDisplayIdChanges() {
        let (manager, primary, secondary) = makeTwoMonitorManager()
        let secondaryContent = populateContentRows(manager, on: secondary.id, count: 1)

        manager.applyMonitorConfigurationChange([primary])

        // Reappear with a DIFFERENT displayId but the SAME unique name → OutputId resolves
        // by name fallback.
        let renumbered = Monitor(
            id: Monitor.ID(displayId: secondary.displayId &+ 100),
            displayId: secondary.displayId &+ 100,
            frame: secondary.frame,
            visibleFrame: secondary.visibleFrame,
            hasNotch: false,
            name: secondary.name
        )
        manager.applyMonitorConfigurationChange([primary, renumbered])

        let stack = rowIds(manager, on: renumbered.id)
        XCTAssertTrue(stack.contains(secondaryContent[0]), "Row restored via unique-name OutputId match")
        XCTAssertTrue(bufferInvariantHolds(manager, on: renumbered.id))
    }

    // MARK: - Finding 1: donor-also-detached must not steal rows to the wrong monitor

    /// S detaches → its rows migrate to P. Then P detaches (S still gone) → P's stack (now
    /// including S's rows) migrates to Q. Reattach S, then reattach P. S's rows must end on S
    /// (their true home), NOT be stolen by P, with no duplication and no window loss.
    func testDonorAlsoDetachedRowsReturnToTrueHome() {
        let manager = makeManager()
        let primary = manager.monitors.first! // P
        let secondary = secondaryMonitor(primary, offset: 1) // S
        let third = secondaryMonitor(primary, offset: 2) // Q (the eventual survivor)
        let q = Monitor(
            id: third.id,
            displayId: third.displayId,
            frame: CGRect(x: 4000, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 4000, y: 0, width: 1440, height: 900),
            hasNotch: false,
            name: "Third"
        )
        manager.applyMonitorConfigurationChange([primary, secondary, q])
        manager.normalizeAllRowStacks()

        // Two content rows on S, one on P, so each has identifiable content.
        let sRows = populateContentRows(manager, on: secondary.id, count: 2)
        let pRows = populateContentRows(manager, on: primary.id, count: 1)
        XCTAssertEqual(sRows.count, 2)
        XCTAssertEqual(pRows.count, 1)
        let totalWindowsBefore = totalWindowCount(manager)

        // 1. Detach S → S's rows migrate to a survivor (P, the main monitor).
        manager.applyMonitorConfigurationChange([primary, q])
        for rowId in sRows {
            XCTAssertTrue(rowIds(manager, on: primary.id).contains(rowId), "S's rows land on survivor P")
        }

        // 2. Detach P (S still gone) → P's rows (its own + S's migrated rows) migrate to Q.
        manager.applyMonitorConfigurationChange([q])
        let qStack = rawRowIds(manager, on: q.id)
        for rowId in sRows + pRows {
            XCTAssertTrue(qStack.contains(rowId), "All content rows land on the only survivor Q")
        }

        // 3. Reattach S (same OutputId). S's rows must come home to S — NOT stay on Q, and NOT
        //    be later grabbed by P.
        manager.applyMonitorConfigurationChange([secondary, q])
        let sStack = rowIds(manager, on: secondary.id)
        for rowId in sRows {
            XCTAssertTrue(sStack.contains(rowId), "S's row \(rowId) returns to S, its true home")
        }
        XCTAssertFalse(sStack.contains(pRows[0]), "S does not grab P's row")

        // 4. Reattach P. P's own row comes home; S's rows must NOT be stolen onto P.
        manager.applyMonitorConfigurationChange([primary, secondary, q])
        let pStack = rowIds(manager, on: primary.id)
        XCTAssertTrue(pStack.contains(pRows[0]), "P's own row returns to P")
        for rowId in sRows {
            XCTAssertFalse(pStack.contains(rowId), "P does NOT steal S's rows (no double-home)")
            XCTAssertTrue(rowIds(manager, on: secondary.id).contains(rowId), "S keeps its rows")
        }

        // No row duplication across the whole stack, and no window loss.
        let allStacks = rawRowIds(manager, on: primary.id)
            + rawRowIds(manager, on: secondary.id)
            + rawRowIds(manager, on: q.id)
        XCTAssertEqual(Set(allStacks).count, allStacks.count, "No row id appears in two monitor stacks")
        XCTAssertEqual(totalWindowCount(manager), totalWindowsBefore, "No window lost or duplicated")
        XCTAssertTrue(bufferInvariantHolds(manager, on: primary.id))
        XCTAssertTrue(bufferInvariantHolds(manager, on: secondary.id))
        XCTAssertTrue(bufferInvariantHolds(manager, on: q.id))
    }

    // MARK: - Finding 2: name collision must not steal the other display's rows

    /// Two detached monitors share an identical `name` but differ in `displayId`. Reattaching
    /// one (by name fallback, displayId changed) must NOT grab the OTHER's remembered rows.
    func testNameCollisionDoesNotStealOtherMonitorsRows() {
        let manager = makeManager()
        let primary = manager.monitors.first!
        // Two twins: same name "Twin", different displayIds and positions.
        let twinA = Monitor(
            id: Monitor.ID(displayId: primary.displayId &+ 10),
            displayId: primary.displayId &+ 10,
            frame: CGRect(x: 2000, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 2000, y: 0, width: 1440, height: 900),
            hasNotch: false,
            name: "Twin"
        )
        let twinB = Monitor(
            id: Monitor.ID(displayId: primary.displayId &+ 20),
            displayId: primary.displayId &+ 20,
            frame: CGRect(x: 4000, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 4000, y: 0, width: 1440, height: 900),
            hasNotch: false,
            name: "Twin"
        )
        manager.applyMonitorConfigurationChange([primary, twinA, twinB])
        manager.normalizeAllRowStacks()

        let aRows = populateContentRows(manager, on: twinA.id, count: 1)
        let bRows = populateContentRows(manager, on: twinB.id, count: 1)

        // Detach BOTH twins → both remembered under (displayId, "Twin") keys, rows on primary.
        manager.applyMonitorConfigurationChange([primary])

        // Reattach twinA with a CHANGED displayId (so only the name "Twin" can match) while
        // twinB is STILL gone. Because two remembered keys carry the name "Twin", the name
        // match is ambiguous and must be refused → twinA must NOT grab B's rows. (A's rows
        // remain on the donor; only an exact-displayId reattach would restore them.)
        let twinARenumbered = Monitor(
            id: Monitor.ID(displayId: twinA.displayId &+ 100),
            displayId: twinA.displayId &+ 100,
            frame: twinA.frame,
            visibleFrame: twinA.visibleFrame,
            hasNotch: false,
            name: "Twin"
        )
        manager.applyMonitorConfigurationChange([primary, twinARenumbered])

        let aStack = rowIds(manager, on: twinARenumbered.id)
        // The ambiguous name match must be REFUSED entirely: the reappearing twin grabs
        // NEITHER twin's remembered rows (pre-fix, dictionary order decided which one it
        // wrongly stole — so we assert neither A's nor B's rows land here).
        XCTAssertFalse(aStack.contains(bRows[0]), "Reattached twin must NOT steal the other twin's rows")
        XCTAssertFalse(aStack.contains(aRows[0]), "Ambiguous name match is refused — not even its own rows by name")
        // Both twins' rows must still exist somewhere (no loss) and not duplicated.
        let everywhere = rawRowIds(manager, on: primary.id)
            + rawRowIds(manager, on: twinARenumbered.id)
        XCTAssertTrue(everywhere.contains(bRows[0]), "B's row is preserved, not lost")
        XCTAssertTrue(everywhere.contains(aRows[0]), "A's row is preserved, not lost")
        XCTAssertEqual(Set(everywhere).count, everywhere.count, "No duplicated row id")
        XCTAssertTrue(bufferInvariantHolds(manager, on: primary.id))
        XCTAssertTrue(bufferInvariantHolds(manager, on: twinARenumbered.id))
    }

    // MARK: - Findings 3/4: no-survivor / full-detach must not orphan content rows

    /// Full detach to the synthetic fallback. Content rows on a monitor whose id differs from
    /// the fallback's must NOT be orphaned under the dead id: they must live on the live
    /// fallback stack, with no window lost and the invariant intact.
    func testFullDetachToFallbackKeepsContentRows() {
        let (manager, primary, secondary) = makeTwoMonitorManager()
        // Put content on BOTH monitors. The secondary's id differs from the fallback's id
        // (fallback shares the main/primary displayId in this environment), so a leak under the
        // secondary id is detectable.
        let primaryContent = populateContentRows(manager, on: primary.id, count: 1)
        let secondaryContent = populateContentRows(manager, on: secondary.id, count: 2)
        let totalWindowsBefore = totalWindowCount(manager)

        // Full detach: empty monitor set → fallback monitor adopted (shares the main id).
        manager.applyMonitorConfigurationChange([])
        manager.normalizeAllRowStacks()

        // The detached secondary id (distinct from fallback) must hold NO rows.
        XCTAssertNotEqual(secondary.id, Monitor.ID.fallback, "Precondition: secondary id differs from fallback")
        XCTAssertTrue(rawRowIds(manager, on: secondary.id).isEmpty, "No rows orphaned under the detached secondary id")

        // Every content row still exists, lives on exactly one LIVE monitor's stack, keeps its window.
        let liveMonitorIds = manager.monitors.map(\.id)
        for rowId in primaryContent + secondaryContent {
            XCTAssertNotNil(manager.descriptor(for: rowId), "Content row \(rowId) not destroyed")
            let homes = liveMonitorIds.filter { rawRowIds(manager, on: $0).contains(rowId) }
            XCTAssertEqual(homes.count, 1, "Content row \(rowId) lives on exactly one live monitor")
            XCTAssertEqual(manager.entries(in: rowId).count, 1, "Content row keeps its window")
        }
        XCTAssertEqual(totalWindowCount(manager), totalWindowsBefore, "No window lost on full detach")
        for monitor in manager.monitors {
            XCTAssertTrue(bufferInvariantHolds(manager, on: monitor.id))
        }
    }

    // MARK: - Finding 4: detaching the visible/interaction monitor keeps the user on a live one

    func testDetachVisibleMonitorResolvesInteractionToLiveMonitor() {
        let (manager, primary, secondary) = makeTwoMonitorManager()
        let secondaryContent = populateContentRows(manager, on: secondary.id, count: 1)
        let visibleWindowId = manager.entries(in: secondaryContent[0]).first?.windowId
        XCTAssertNotNil(visibleWindowId)

        // Make the secondary the interaction monitor and show its content row.
        _ = manager.setActiveWorkspace(secondaryContent[0], on: secondary.id)
        let totalWindowsBefore = totalWindowCount(manager)

        // Detach the secondary (the interaction monitor).
        manager.applyMonitorConfigurationChange([primary])

        // Interaction + visible state must resolve to a LIVE monitor.
        if let interaction = manager.interactionMonitorId {
            XCTAssertNotNil(manager.monitor(byId: interaction), "Interaction monitor is live after detach")
            XCTAssertNotEqual(interaction, secondary.id, "Interaction no longer points at the dead monitor")
        }
        // The visible row's window survives on the survivor.
        XCTAssertTrue(rowIds(manager, on: primary.id).contains(secondaryContent[0]), "Visible row migrated to survivor")
        XCTAssertEqual(manager.entries(in: secondaryContent[0]).count, 1, "Visible row's window survived")
        XCTAssertEqual(totalWindowCount(manager), totalWindowsBefore, "No window lost")
        XCTAssertTrue(rawRowIds(manager, on: secondary.id).isEmpty, "No row stranded under the dead id")
        XCTAssertTrue(bufferInvariantHolds(manager, on: primary.id))
    }

    // MARK: - Reattach with a since-closed row

    func testReattachSkipsSinceClosedRowGracefully() {
        let (manager, primary, secondary) = makeTwoMonitorManager()
        let secondaryContent = populateContentRows(manager, on: secondary.id, count: 2)
        let survivor = secondaryContent[0]
        let doomed = secondaryContent[1]

        // Find the window that lives in `doomed` so we can close it after detach.
        guard let doomedWindowId = manager.entries(in: doomed).first?.windowId else {
            return XCTFail("doomed row should have a window")
        }

        manager.applyMonitorConfigurationChange([primary])

        // Close every window in the `doomed` row → it becomes empty and normalization on the
        // donor reaps it, so it no longer exists at reattach time.
        _ = manager.removeWindow(pid: getpid(), windowId: doomedWindowId)
        manager.normalizeAllRowStacks()

        // Reattach — must not crash, and the surviving row comes back.
        manager.applyMonitorConfigurationChange([primary, secondary])

        let secondaryStack = rowIds(manager, on: secondary.id)
        XCTAssertTrue(secondaryStack.contains(survivor), "Still-existing remembered row restored")
        XCTAssertFalse(secondaryStack.contains(doomed), "Since-closed row is skipped, not resurrected")
        XCTAssertNil(manager.descriptor(for: doomed), "The closed row's descriptor is gone")
        XCTAssertTrue(bufferInvariantHolds(manager, on: secondary.id))
        XCTAssertTrue(bufferInvariantHolds(manager, on: primary.id))
    }

    // MARK: - Single-monitor inertness

    func testSingleMonitorReconfigureLosesNothing() {
        let manager = makeManager()
        let mon = manager.monitors.first!
        let content = populateContentRows(manager, on: mon.id, count: 2)
        let before = rowIds(manager, on: mon.id)

        // "Reconfigure" the same monitor (same id) — e.g. resolution change. Same OutputId.
        let reconfigured = Monitor(
            id: mon.id,
            displayId: mon.displayId,
            frame: CGRect(x: 0, y: 0, width: 3840, height: 2160),
            visibleFrame: CGRect(x: 0, y: 0, width: 3840, height: 2160),
            hasNotch: mon.hasNotch,
            name: mon.name
        )
        manager.applyMonitorConfigurationChange([reconfigured])
        manager.normalizeAllRowStacks()

        let after = rowIds(manager, on: mon.id)
        XCTAssertEqual(before, after, "Single-monitor reconfigure does not reshuffle the stack")
        for rowId in content {
            XCTAssertEqual(manager.entries(in: rowId).count, 1, "No window lost on single-monitor churn")
        }
        XCTAssertTrue(bufferInvariantHolds(manager, on: mon.id))
    }

    func testSingleMonitorChurnDoesNotPopulateReattachCache() {
        let manager = makeManager()
        let mon = manager.monitors.first!
        _ = populateContentRows(manager, on: mon.id, count: 1)

        // Repeated identical topology events must be inert (no migration, no loss).
        for _ in 0 ..< 3 {
            manager.applyMonitorConfigurationChange([mon])
            manager.normalizeAllRowStacks()
        }

        let ids = rowIds(manager, on: mon.id)
        XCTAssertEqual(ids.count, 3, "Stack stays [topBuffer, content, bottomBuffer]")
        XCTAssertEqual(manager.entries(in: ids[1]).count, 1)
        XCTAssertTrue(bufferInvariantHolds(manager, on: mon.id))
    }
}
