import AppKit
import Foundation

@MainActor
enum WorkspaceBarDataSource {
    private struct WorkspaceSnapshot {
        let workspace: WorkspaceDescriptor
        let tiledEntries: [WindowModel.Entry]
        let floatingEntries: [WindowModel.Entry]
        let hasBarOccupancy: Bool
    }

    static func workspaceBarItems(
        for monitor: Monitor,
        options: WorkspaceBarProjectionOptions,
        workspaceManager: WorkspaceManager,
        appInfoCache: AppInfoCache,
        niriEngine: NiriLayoutEngine?,
        focusedToken: WindowToken?,
        settings: SettingsStore
    ) -> [WorkspaceBarItem] {
        workspaceItems(
            for: monitor,
            options: options,
            workspaceManager: workspaceManager,
            appInfoCache: appInfoCache,
            niriEngine: niriEngine,
            focusedToken: focusedToken,
            settings: settings
        )
    }

    static func workspaceBarProjection(
        for monitor: Monitor,
        options: WorkspaceBarProjectionOptions,
        workspaceManager: WorkspaceManager,
        appInfoCache: AppInfoCache,
        niriEngine: NiriLayoutEngine?,
        focusedToken: WindowToken?,
        settings: SettingsStore
    ) -> WorkspaceBarProjection {
        WorkspaceBarProjection(
            items: workspaceItems(
                for: monitor,
                options: options,
                workspaceManager: workspaceManager,
                appInfoCache: appInfoCache,
                niriEngine: niriEngine,
                focusedToken: focusedToken,
                settings: settings
            ),
            scratchpad: scratchpadItem(
                workspaceManager: workspaceManager,
                appInfoCache: appInfoCache,
                focusedToken: focusedToken,
                settings: settings
            )
        )
    }

    private static func workspaceItems(
        for monitor: Monitor,
        options: WorkspaceBarProjectionOptions,
        workspaceManager: WorkspaceManager,
        appInfoCache: AppInfoCache,
        niriEngine: NiriLayoutEngine?,
        focusedToken: WindowToken?,
        settings _: SettingsStore // kept in signature for API symmetry; labels now positional
    ) -> [WorkspaceBarItem] {
        // Derive order from the dynamic row stack.
        // Use the interaction monitor when available (the monitor that last received
        // input), falling back to the supplied monitor.  This ensures the bar always
        // reflects the active monitor's row stack even when the bar itself is on a
        // secondary display.
        let targetMonitorId: Monitor.ID
        if let interactionMonitorId = workspaceManager.interactionMonitorId {
            targetMonitorId = interactionMonitorId
        } else {
            targetMonitorId = monitor.id
        }

        // Pull the ordered row IDs directly from `rowOrderByMonitor` (top→bottom).
        let orderedIds = workspaceManager.rowOrder(on: targetMonitorId)

        // Build a snapshot for each row in stack order.
        var allSnapshots: [(snapshot: WorkspaceSnapshot, rowIndex: Int)] = []
        for (zeroBasedIndex, wsId) in orderedIds.enumerated() {
            guard let workspace = workspaceManager.descriptor(for: wsId) else { continue }
            let projectedEntries = workspaceManager.barVisibleEntries(
                in: workspace.id,
                showFloatingWindows: options.showFloatingWindows
            )
            let snap = WorkspaceSnapshot(
                workspace: workspace,
                tiledEntries: projectedEntries.filter { $0.mode == .tiling },
                floatingEntries: projectedEntries.filter { $0.mode == .floating },
                hasBarOccupancy: workspaceManager.hasBarVisibleOccupancy(
                    in: workspace.id,
                    showFloatingWindows: options.showFloatingWindows
                )
            )
            allSnapshots.append((snap, zeroBasedIndex + 1)) // 1-based rowIndex
        }

        // Identify buffer positions: the first and last rows are buffers when empty.
        // Guard: need at least 2 rows for there to be a buffer at each end.
        let topIsBuffer: Bool = {
            guard let first = allSnapshots.first else { return false }
            return !first.snapshot.hasBarOccupancy
        }()
        let bottomIsBuffer: Bool = {
            guard allSnapshots.count > 1, let last = allSnapshots.last else { return false }
            return !last.snapshot.hasBarOccupancy
        }()

        // Apply hideEmptyWorkspaces: hide every empty row, including the faint
        // top/bottom buffer rows. When the option is off, buffer rows are still
        // shown faintly so the user perceives "there's room above/below".
        let filteredSnapshots: [(snapshot: WorkspaceSnapshot, rowIndex: Int, isBuffer: Bool)]
        filteredSnapshots = allSnapshots.enumerated().compactMap { enumIndex, pair in
            let isTopBuffer = topIsBuffer && enumIndex == 0
            let isBottomBuffer = bottomIsBuffer && enumIndex == allSnapshots.count - 1
            let isBuf = isTopBuffer || isBottomBuffer

            if options.hideEmptyWorkspaces, !pair.snapshot.hasBarOccupancy {
                return nil
            }
            return (pair.snapshot, pair.rowIndex, isBuf)
        }

        let activeWorkspaceId = workspaceManager.activeWorkspace(on: targetMonitorId)?.id

        return filteredSnapshots.map { snapshot, rowIndex, isBuffer in
            let orderedTiledEntries = WorkspaceEntryOrdering.orderedEntries(
                snapshot.tiledEntries,
                in: snapshot.workspace.id,
                engine: niriEngine
            )
            let orderedFloatingEntries = WorkspaceEntryOrdering.orderedEntries(
                snapshot.floatingEntries,
                in: snapshot.workspace.id,
                engine: niriEngine
            )
            let useLayoutOrder = niriEngine.map { !$0.columns(in: snapshot.workspace.id).isEmpty } ?? false
            let tiledWindows = createWindowItems(
                entries: orderedTiledEntries,
                deduplicate: options.deduplicateAppIcons,
                useLayoutOrder: useLayoutOrder,
                appInfoCache: appInfoCache,
                focusedToken: focusedToken
            )
            let floatingWindows = createWindowItems(
                entries: orderedFloatingEntries,
                deduplicate: options.deduplicateAppIcons,
                useLayoutOrder: useLayoutOrder,
                appInfoCache: appInfoCache,
                focusedToken: focusedToken
            )

            // Labels are positional (row index) — rows are anonymous.
            // We keep `rawName` for diagnostics / legacy lookup but always display
            // the 1-based index so the label is predictable and user-meaningful.
            return WorkspaceBarItem(
                id: snapshot.workspace.id,
                name: "\(rowIndex)",
                rawName: snapshot.workspace.name,
                isFocused: snapshot.workspace.id == activeWorkspaceId,
                rowIndex: rowIndex,
                isBuffer: isBuffer,
                tiledWindows: tiledWindows,
                floatingWindows: floatingWindows
            )
        }
    }

    private static func scratchpadItem(
        workspaceManager: WorkspaceManager,
        appInfoCache: AppInfoCache,
        focusedToken: WindowToken?,
        settings: SettingsStore
    ) -> WorkspaceBarScratchpadItem? {
        guard let scratchpadToken = workspaceManager.scratchpadToken(),
              let entry = workspaceManager.entry(for: scratchpadToken),
              let window = createWindowItems(
                  entries: [entry],
                  deduplicate: false,
                  useLayoutOrder: false,
                  appInfoCache: appInfoCache,
                  focusedToken: focusedToken
              ).first
        else {
            return nil
        }

        let descriptor = workspaceManager.descriptor(for: entry.workspaceId)
        let rawWorkspaceName = descriptor?.name ?? ""
        return WorkspaceBarScratchpadItem(
            window: window,
            isVisible: workspaceManager.hiddenState(for: scratchpadToken) == nil,
            workspaceId: entry.workspaceId,
            workspaceName: settings.displayName(for: rawWorkspaceName),
            rawWorkspaceName: rawWorkspaceName
        )
    }

    private static func createWindowItems(
        entries: [WindowModel.Entry],
        deduplicate: Bool,
        useLayoutOrder: Bool,
        appInfoCache: AppInfoCache,
        focusedToken: WindowToken?
    ) -> [WorkspaceBarWindowItem] {
        if deduplicate {
            return createDedupedWindowItems(
                entries: entries,
                useLayoutOrder: useLayoutOrder,
                appInfoCache: appInfoCache,
                focusedToken: focusedToken
            )
        }

        return createIndividualWindowItems(
            entries: entries,
            appInfoCache: appInfoCache,
            focusedToken: focusedToken
        )
    }

    private static func createDedupedWindowItems(
        entries: [WindowModel.Entry],
        useLayoutOrder: Bool,
        appInfoCache: AppInfoCache,
        focusedToken: WindowToken?
    ) -> [WorkspaceBarWindowItem] {
        if useLayoutOrder {
            var groupedByApp: [String: [WindowModel.Entry]] = [:]
            var orderedAppNames: [String] = []

            for entry in entries {
                let appName = appInfoCache.name(for: entry.handle.pid) ?? "Unknown"

                if groupedByApp[appName] == nil {
                    groupedByApp[appName] = []
                    orderedAppNames.append(appName)
                }

                groupedByApp[appName]?.append(entry)
            }

            return orderedAppNames.compactMap { appName -> WorkspaceBarWindowItem? in
                guard let appEntries = groupedByApp[appName], let firstEntry = appEntries.first else { return nil }
                let appInfo = appInfoCache.info(for: firstEntry.handle.pid)
                let anyFocused = appEntries.contains { $0.handle.id == focusedToken }

                let windowInfos = appEntries.map { entry -> WorkspaceBarWindowInfo in
                    WorkspaceBarWindowInfo(
                        id: entry.handle.id,
                        windowId: entry.windowId,
                        title: windowTitle(for: entry) ?? appName,
                        isFocused: entry.handle.id == focusedToken
                    )
                }

                return WorkspaceBarWindowItem(
                    id: firstEntry.handle.id,
                    windowId: firstEntry.windowId,
                    appName: appName,
                    icon: appInfo?.icon,
                    isFocused: anyFocused,
                    windowCount: appEntries.count,
                    allWindows: windowInfos
                )
            }
        }

        let groupedByApp = Dictionary(grouping: entries) { entry -> String in
            appInfoCache.name(for: entry.handle.pid) ?? "Unknown"
        }

        return groupedByApp.map { appName, appEntries -> WorkspaceBarWindowItem in
            let firstEntry = appEntries.first!
            let appInfo = appInfoCache.info(for: firstEntry.handle.pid)
            let anyFocused = appEntries.contains { $0.handle.id == focusedToken }

            let windowInfos = appEntries.map { entry -> WorkspaceBarWindowInfo in
                WorkspaceBarWindowInfo(
                    id: entry.handle.id,
                    windowId: entry.windowId,
                    title: windowTitle(for: entry) ?? appName,
                    isFocused: entry.handle.id == focusedToken
                )
            }

            return WorkspaceBarWindowItem(
                id: firstEntry.handle.id,
                windowId: firstEntry.windowId,
                appName: appName,
                icon: appInfo?.icon,
                isFocused: anyFocused,
                windowCount: appEntries.count,
                allWindows: windowInfos
            )
        }.sorted { $0.appName < $1.appName }
    }

    private static func createIndividualWindowItems(
        entries: [WindowModel.Entry],
        appInfoCache: AppInfoCache,
        focusedToken: WindowToken?
    ) -> [WorkspaceBarWindowItem] {
        entries.map { entry in
            let appInfo = appInfoCache.info(for: entry.handle.pid)
            let appName = appInfo?.name ?? "Unknown"
            let title = windowTitle(for: entry) ?? appName

            return WorkspaceBarWindowItem(
                id: entry.handle.id,
                windowId: entry.windowId,
                appName: appName,
                icon: appInfo?.icon,
                isFocused: entry.handle.id == focusedToken,
                windowCount: 1,
                allWindows: [
                    WorkspaceBarWindowInfo(
                        id: entry.handle.id,
                        windowId: entry.windowId,
                        title: title,
                        isFocused: entry.handle.id == focusedToken
                    )
                ]
            )
        }
    }

    private static func windowTitle(for entry: WindowModel.Entry) -> String? {
        guard let title = AXWindowService.titlePreferFast(windowId: UInt32(entry.windowId)),
              !title.isEmpty else { return nil }
        return title
    }
}
