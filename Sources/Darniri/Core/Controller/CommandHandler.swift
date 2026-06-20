import AppKit
import Foundation

@MainActor
final class CommandHandler {
    weak var controller: WMController?
    var nativeFullscreenStateProvider: ((AXWindowRef) -> Bool)?
    var nativeFullscreenSetter: ((AXWindowRef, Bool) -> Bool)?
    var frontmostAppPidProvider: (() -> pid_t?)?
    var frontmostFocusedWindowTokenProvider: (() -> WindowToken?)?

    init(controller: WMController) {
        self.controller = controller
    }

    @discardableResult
    func handleHotkeyCommand(_ command: HotkeyCommand) -> ExternalCommandResult {
        guard let controller else { return .notFound }
        guard controller.isEnabled else { return .ignoredDisabled }
        if case let .focus(direction) = command,
           controller.navigateOverviewSelection(direction)
        {
            return .executed
        }
        return performCommand(command)
    }

    @discardableResult
    func handleCommand(_ command: HotkeyCommand) -> ExternalCommandResult {
        performCommand(command)
    }

    @discardableResult
    func performCommand(_ command: HotkeyCommand) -> ExternalCommandResult {
        guard let controller else { return .notFound }
        guard controller.isEnabled else { return .ignoredDisabled }
        // When the overview is open, layout commands (focus/move/column) act on the overview's
        // selected window rather than being ignored. These arrive as global hotkeys, so they
        // never reach the overview's own keyDown — route them here.
        if controller.handleOverviewLayoutCommand(command) {
            return .executed
        }
        guard !Self.shouldIgnoreCommand(command, isOverviewOpen: controller.isOverviewOpen()) else {
            return .ignoredOverview
        }

        switch command {
        case let .focus(direction):
            layoutHandler(as: LayoutFocusable.self)?.focusNeighbor(direction: direction)
        case .focusPrevious:
            focusPreviousInNiri()
        case let .move(direction):
            moveWindow(direction: direction)
        case .moveWindowDown:
            controller.niriLayoutHandler.moveWindow(direction: .down)
        case .moveWindowUp:
            controller.niriLayoutHandler.moveWindow(direction: .up)
        case .moveWindowDownOrToWorkspaceDown:
            controller.niriLayoutHandler.moveWindowOrToAdjacentWorkspace(direction: .down)
        case .moveWindowUpOrToWorkspaceUp:
            controller.niriLayoutHandler.moveWindowOrToAdjacentWorkspace(direction: .up)
        case .consumeOrExpelWindowLeft:
            controller.niriLayoutHandler.consumeOrExpelWindow(direction: .left)
        case .consumeOrExpelWindowRight:
            controller.niriLayoutHandler.consumeOrExpelWindow(direction: .right)
        case .consumeWindowIntoColumn:
            controller.niriLayoutHandler.consumeWindowIntoColumn()
        case .expelWindowFromColumn:
            controller.niriLayoutHandler.expelWindowFromColumn()
        case let .moveToWorkspace(index):
            controller.workspaceNavigationHandler.moveFocusedWindow(toWorkspaceIndex: index)
        case .moveWindowToWorkspaceUp:
            controller.workspaceNavigationHandler.moveWindowToAdjacentWorkspace(direction: .up)
        case .moveWindowToWorkspaceDown:
            controller.workspaceNavigationHandler.moveWindowToAdjacentWorkspace(direction: .down)
        case let .moveColumnToWorkspace(index):
            controller.workspaceNavigationHandler.moveColumnToWorkspaceByIndex(index: index)
        case .moveColumnToWorkspaceUp:
            controller.workspaceNavigationHandler.moveColumnToAdjacentWorkspace(direction: .up)
        case .moveColumnToWorkspaceDown:
            controller.workspaceNavigationHandler.moveColumnToAdjacentWorkspace(direction: .down)
        case let .switchWorkspace(index):
            controller.workspaceNavigationHandler.switchWorkspace(index: index)
        case .switchWorkspaceNext:
            // Dynamic-row model: vertical row switch does NOT wrap (Niri behavior — you
            // stop at the empty buffer at the top/bottom).
            controller.workspaceNavigationHandler.switchWorkspaceRelative(isNext: true, wrapAround: false)
        case .switchWorkspacePrevious:
            controller.workspaceNavigationHandler.switchWorkspaceRelative(isNext: false, wrapAround: false)
        case .focusMonitorPrevious:
            controller.workspaceNavigationHandler.focusMonitorCyclic(previous: true)
        case .focusMonitorNext:
            controller.workspaceNavigationHandler.focusMonitorCyclic(previous: false)
        case .focusMonitorLast:
            controller.workspaceNavigationHandler.focusLastMonitor()
        case .toggleFullscreen:
            toggleFullscreen()
        case .toggleNativeFullscreen:
            toggleNativeFullscreenForFocused()
        case let .moveColumn(direction):
            moveColumnInNiri(direction: direction)
        case .moveColumnToFirst:
            moveColumnToFirstInNiri()
        case .moveColumnToLast:
            moveColumnToLastInNiri()
        case let .moveColumnToIndex(index):
            moveColumnToIndexInNiri(index: index)
        case .toggleColumnTabbed:
            toggleColumnTabbedInNiri()
        case .focusDownOrLeft:
            focusDownOrLeftInNiri()
        case .focusUpOrRight:
            focusUpOrRightInNiri()
        case let .focusWindowInColumn(index):
            focusWindowInColumnInNiri(index: index)
        case .focusWindowTop:
            focusWindowTopInNiri()
        case .focusWindowBottom:
            focusWindowBottomInNiri()
        case .focusWindowDownOrTop:
            focusWindowDownOrTopInNiri()
        case .focusWindowUpOrBottom:
            focusWindowUpOrBottomInNiri()
        case .focusWindowOrWorkspaceDown:
            focusWindowOrWorkspaceInNiri(direction: .down)
        case .focusWindowOrWorkspaceUp:
            focusWindowOrWorkspaceInNiri(direction: .up)
        case .focusColumnFirst:
            focusColumnFirstInNiri()
        case .focusColumnLast:
            focusColumnLastInNiri()
        case let .focusColumn(index):
            focusColumnInNiri(index: index)
        case .centerColumn:
            controller.niriLayoutHandler.centerColumn()
        case .centerVisibleColumns:
            controller.niriLayoutHandler.centerVisibleColumns()
        case .cycleColumnWidthForward:
            layoutHandler(as: LayoutSizable.self)?.cycleSize(forward: true)
        case .cycleColumnWidthBackward:
            layoutHandler(as: LayoutSizable.self)?.cycleSize(forward: false)
        case .cycleWindowWidthForward:
            controller.niriLayoutHandler.cycleWindowWidth(forward: true)
        case .cycleWindowWidthBackward:
            controller.niriLayoutHandler.cycleWindowWidth(forward: false)
        case .cycleWindowHeightForward:
            controller.niriLayoutHandler.cycleWindowHeight(forward: true)
        case .cycleWindowHeightBackward:
            controller.niriLayoutHandler.cycleWindowHeight(forward: false)
        case .toggleColumnFullWidth:
            controller.niriLayoutHandler.toggleColumnFullWidth()
        case .expandColumnToAvailableWidth:
            controller.niriLayoutHandler.expandColumnToAvailableWidth()
        case .resetWindowHeight:
            controller.niriLayoutHandler.resetWindowHeight()
        case let .setColumnWidth(change):
            controller.niriLayoutHandler.setColumnWidth(change)
        case let .setWindowWidth(change):
            controller.niriLayoutHandler.setWindowWidth(change)
        case let .setWindowHeight(change):
            controller.niriLayoutHandler.setWindowHeight(change)
        case let .swapWorkspaceWithMonitor(direction):
            controller.workspaceNavigationHandler.swapCurrentWorkspaceWithMonitor(direction: direction)
        case .balanceSizes:
            layoutHandler(as: LayoutSizable.self)?.balanceSizes()
        case .workspaceBackAndForth:
            controller.workspaceNavigationHandler.workspaceBackAndForth()
        case let .focusWorkspaceAnywhere(index):
            controller.workspaceNavigationHandler.focusWorkspaceAnywhere(index: index)
        case let .moveWindowToWorkspaceOnMonitor(wsIdx, monDir):
            controller.workspaceNavigationHandler.moveWindowToWorkspaceOnMonitor(
                workspaceIndex: wsIdx,
                monitorDirection: monDir
            )
        case .openCommandPalette:
            controller.openCommandPalette()
        case .raiseAllFloatingWindows:
            controller.raiseAllFloatingWindows()
        case .rescueOffscreenWindows:
            _ = controller.rescueOffscreenWindows()
        case .toggleFocusedWindowFloating:
            return controller.toggleFocusedWindowFloating()
        case .assignFocusedWindowToScratchpad:
            return controller.assignFocusedWindowToScratchpad()
        case .toggleScratchpadWindow:
            return controller.toggleScratchpadWindow()
        case .toggleWorkspaceBarVisibility:
            controller.toggleWorkspaceBarVisibility()
        case .toggleOverview:
            controller.toggleOverview()
        }

        return .executed
    }

    static func shouldIgnoreCommand(_ command: HotkeyCommand, isOverviewOpen: Bool) -> Bool {
        isOverviewOpen && command != .toggleOverview
    }

    // MARK: - Overview-accessible internal dispatch helpers

    /// Executes a focus-previous action without the overview-open guard.
    /// Called by `OverviewController` when dispatching layout commands for the selected thumbnail.
    func handleFocusPreviousForOverview() {
        focusPreviousInNiri()
    }

    /// Executes a focusWindowOrWorkspace action (up or down) without the overview-open guard.
    func handleFocusWindowOrWorkspaceForOverview(direction: Direction) {
        focusWindowOrWorkspaceInNiri(direction: direction)
    }

    /// Executes a combined-navigation (focusWindowTop, focusWindowBottom, etc.) action
    /// without the overview-open guard.
    func handleCombinedNavigationForOverview(
        _ navigationAction: (
            NiriLayoutEngine,
            NiriNode,
            WorkspaceDescriptor.ID,
            MotionSnapshot,
            inout ViewportState,
            CGRect,
            CGFloat
        ) -> NiriNode?
    ) {
        executeCombinedNavigation(navigationAction)
    }

    /// Executes a moveColumn action without the overview-open guard.
    func handleMoveColumnForOverview(direction: Direction) {
        moveColumnInNiri(direction: direction)
    }

    private func layoutHandler<T>(as capability: T.Type) -> T? {
        guard let controller else { return nil }
        return controller.layoutRefreshController.niriHandler as? T
    }

    private func focusPreviousInNiri() {
        guard let controller else { return }
        guard let engine = controller.niriEngine else { return }
        guard let wsId = controller.activeWorkspace()?.id else { return }
        guard let monitor = controller.workspaceManager.monitor(for: wsId) else { return }
        var state = controller.workspaceManager.niriViewportState(for: wsId)
        let motion = controller.motionPolicy.snapshot()
        let workingFrame = controller.insetWorkingFrame(for: monitor)
        let gaps = CGFloat(controller.workspaceManager.gaps)

        if let currentId = state.selectedNodeId {
            engine.updateFocusTimestamp(for: currentId)
        }

        if let currentId = state.selectedNodeId {
            engine.activateWindow(currentId)
        }

        guard let previousWindow = engine.focusPrevious(
            currentNodeId: state.selectedNodeId,
            in: wsId,
            motion: motion,
            state: &state,
            workingFrame: workingFrame,
            gaps: gaps,
            limitToWorkspace: true
        ) else {
            return
        }

        controller.niriLayoutHandler.activateNode(
            previousWindow, in: wsId, state: &state,
            options: .init(
                ensureVisible: false,
                updateTimestamp: false,
                layoutRefresh: false,
                axFocus: false,
                startAnimation: false
            )
        )
        _ = controller.workspaceManager.applySessionPatch(
            .init(
                workspaceId: wsId,
                viewportState: state,
                rememberedFocusToken: nil,
                runtimeRevision: controller.workspaceManager.runtimeRevision(for: wsId)
            )
        )
        controller.niriLayoutHandler.requestSelectedWindowFocusAfterLayout(in: wsId)

        if state.viewOffsetPixels.isAnimating {
            controller.layoutRefreshController.startScrollAnimation(for: wsId)
        }
    }

    private func focusDownOrLeftInNiri() {
        executeCombinedNavigation { engine, currentNode, wsId, motion, state, workingFrame, gaps in
            engine.focusDownOrLeft(
                currentSelection: currentNode,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
    }

    private func focusUpOrRightInNiri() {
        executeCombinedNavigation { engine, currentNode, wsId, motion, state, workingFrame, gaps in
            engine.focusUpOrRight(
                currentSelection: currentNode,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
    }

    private func focusWindowInColumnInNiri(index: Int) {
        executeCombinedNavigation { engine, currentNode, wsId, motion, state, workingFrame, gaps in
            engine.focusWindowInColumn(
                index,
                currentSelection: currentNode,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
    }

    private func focusWindowTopInNiri() {
        executeCombinedNavigation { engine, currentNode, wsId, motion, state, workingFrame, gaps in
            engine.focusWindowTop(
                currentSelection: currentNode,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
    }

    private func focusWindowBottomInNiri() {
        executeCombinedNavigation { engine, currentNode, wsId, motion, state, workingFrame, gaps in
            engine.focusWindowBottom(
                currentSelection: currentNode,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
    }

    private func focusWindowDownOrTopInNiri() {
        executeCombinedNavigation { engine, currentNode, wsId, motion, state, workingFrame, gaps in
            engine.focusWindowDownOrTop(
                currentSelection: currentNode,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
    }

    private func focusWindowUpOrBottomInNiri() {
        executeCombinedNavigation { engine, currentNode, wsId, motion, state, workingFrame, gaps in
            engine.focusWindowUpOrBottom(
                currentSelection: currentNode,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
    }

    private func focusWindowOrWorkspaceInNiri(direction: Direction) {
        guard direction == .down || direction == .up else { return }
        executeCombinedNavigation(onNoTarget: { [weak self] in
            // Only cross into the adjacent workspace if it actually has windows.
            // If there is no next window and the neighbour is a blank/spare row,
            // stay put on the currently focused window.
            self?.controller?.workspaceNavigationHandler.switchWorkspaceRelative(
                isNext: direction == .down,
                wrapAround: false,
                requireOccupied: true
            )
        }) { engine, currentNode, wsId, motion, state, workingFrame, gaps in
            engine.focusTarget(
                direction: direction,
                currentSelection: currentNode,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
    }

    private func focusColumnFirstInNiri() {
        executeCombinedNavigation { engine, currentNode, wsId, motion, state, workingFrame, gaps in
            engine.focusColumnFirst(
                currentSelection: currentNode,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
    }

    private func focusColumnLastInNiri() {
        executeCombinedNavigation { engine, currentNode, wsId, motion, state, workingFrame, gaps in
            engine.focusColumnLast(
                currentSelection: currentNode,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
    }

    private func focusColumnInNiri(index: Int) {
        executeCombinedNavigation { engine, currentNode, wsId, motion, state, workingFrame, gaps in
            engine.focusColumn(
                index,
                currentSelection: currentNode,
                in: wsId,
                motion: motion,
                state: &state,
                workingFrame: workingFrame,
                gaps: gaps
            )
        }
    }

    private func executeCombinedNavigation(
        onNoTarget: (() -> Void)? = nil,
        _ navigationAction: (
            NiriLayoutEngine,
            NiriNode,
            WorkspaceDescriptor.ID,
            MotionSnapshot,
            inout ViewportState,
            CGRect,
            CGFloat
        )
            -> NiriNode?
    ) {
        guard let controller else { return }
        guard let engine = controller.niriEngine else { return }
        guard let wsId = controller.activeWorkspace()?.id else { return }
        guard let monitor = controller.workspaceManager.monitor(for: wsId) else { return }

        var state = controller.workspaceManager.niriViewportState(for: wsId)
        let currentNode: NiriNode
        if let currentId = state.selectedNodeId,
           let node = engine.findNode(by: currentId)
        {
            currentNode = node
        } else if let lastFocused = controller.workspaceManager.lastFocusedToken(in: wsId),
                  let node = engine.findNode(for: lastFocused)
        {
            state.selectedNodeId = node.id
            currentNode = node
        } else if let selectedId = engine.validateSelection(state.selectedNodeId, in: wsId),
                  let node = engine.findNode(by: selectedId)
        {
            state.selectedNodeId = selectedId
            currentNode = node
        } else {
            onNoTarget?()
            return
        }

        let gap = CGFloat(controller.workspaceManager.gaps)
        let workingFrame = controller.insetWorkingFrame(for: monitor)
        let motion = controller.motionPolicy.snapshot()
        guard let newNode = navigationAction(engine, currentNode, wsId, motion, &state, workingFrame, gap) else {
            onNoTarget?()
            return
        }
        controller.niriLayoutHandler.activateNode(
            newNode, in: wsId, state: &state,
            options: .init(
                activateWindow: false,
                ensureVisible: false,
                layoutRefresh: false,
                axFocus: false
            )
        )
        _ = controller.workspaceManager.applySessionPatch(
            .init(
                workspaceId: wsId,
                viewportState: state,
                rememberedFocusToken: nil,
                runtimeRevision: controller.workspaceManager.runtimeRevision(for: wsId)
            )
        )
        controller.niriLayoutHandler.requestSelectedWindowFocusAfterLayout(in: wsId)
    }

    private func moveWindow(direction: Direction) {
        moveWindowInNiri(direction: direction)
    }

    private func toggleFullscreen() {
        controller?.niriLayoutHandler.toggleFullscreen()
    }

    private func moveWindowInNiri(direction: Direction) {
        controller?.niriLayoutHandler.moveWindow(direction: direction)
    }

    private func toggleNativeFullscreenForFocused() {
        guard let controller else { return }
        let setFullscreen = nativeFullscreenSetter ?? { axRef, fullscreen in
            AXWindowService.setNativeFullscreen(axRef, fullscreen: fullscreen)
        }
        let isFullscreen = nativeFullscreenStateProvider ?? { axRef in
            AXWindowService.isFullscreen(axRef)
        }

        if let token = controller.workspaceManager.focusedToken,
           let entry = controller.workspaceManager.entry(for: token)
        {
            let currentState = isFullscreen(entry.axRef)
            if currentState {
                _ = controller.workspaceManager.requestNativeFullscreenExit(token, initiatedByCommand: true)
                guard setFullscreen(entry.axRef, false) else {
                    _ = controller.workspaceManager.markNativeFullscreenSuspended(token)
                    return
                }
                return
            }

            _ = controller.workspaceManager.requestNativeFullscreenEnter(token, in: entry.workspaceId)
            guard setFullscreen(entry.axRef, true) else {
                _ = controller.workspaceManager.restoreNativeFullscreenRecord(for: token)
                return
            }
            return
        }

        guard controller.workspaceManager.isAppFullscreenActive
            || controller.workspaceManager.hasPendingNativeFullscreenTransition
        else {
            return
        }

        let frontmostPid = frontmostAppPidProvider?() ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontmostToken = frontmostFocusedWindowTokenProvider?()
            ?? frontmostPid.flatMap { controller.axEventHandler.focusedWindowToken(for: $0) }
        guard let token = controller.workspaceManager.nativeFullscreenCommandTarget(frontmostToken: frontmostToken),
              let entry = controller.workspaceManager.entry(for: token)
        else {
            return
        }

        _ = controller.workspaceManager.requestNativeFullscreenExit(token, initiatedByCommand: true)
        guard setFullscreen(entry.axRef, false) else {
            _ = controller.workspaceManager.markNativeFullscreenSuspended(token)
            return
        }
    }

    private func moveColumnInNiri(direction: Direction) {
        guard let controller else { return }
        controller.niriLayoutHandler.withNiriOperationContext { ctx, state in
            guard let column = ctx.engine.findColumn(containing: ctx.windowNode, in: ctx.wsId) else { return false }
            let oldFrames = ctx.engine.captureWindowFrames(in: ctx.wsId)
            guard ctx.engine.moveColumn(
                column, direction: direction, in: ctx.wsId,
                motion: ctx.motion,
                state: &state,
                workingFrame: ctx.workingFrame,
                gaps: ctx.gaps
            ) else { return false }
            return ctx.commitWithCapturedAnimation(state: state, oldFrames: oldFrames)
        }
    }

    private func moveColumnToFirstInNiri() {
        guard let controller else { return }
        controller.niriLayoutHandler.withNiriOperationContext { ctx, state in
            guard let column = ctx.engine.findColumn(containing: ctx.windowNode, in: ctx.wsId) else { return false }
            let oldFrames = ctx.engine.captureWindowFrames(in: ctx.wsId)
            guard ctx.engine.moveColumnToFirst(
                column,
                in: ctx.wsId,
                motion: ctx.motion,
                state: &state,
                workingFrame: ctx.workingFrame,
                gaps: ctx.gaps
            ) else { return false }
            return ctx.commitWithCapturedAnimation(state: state, oldFrames: oldFrames)
        }
    }

    private func moveColumnToLastInNiri() {
        guard let controller else { return }
        controller.niriLayoutHandler.withNiriOperationContext { ctx, state in
            guard let column = ctx.engine.findColumn(containing: ctx.windowNode, in: ctx.wsId) else { return false }
            let oldFrames = ctx.engine.captureWindowFrames(in: ctx.wsId)
            guard ctx.engine.moveColumnToLast(
                column,
                in: ctx.wsId,
                motion: ctx.motion,
                state: &state,
                workingFrame: ctx.workingFrame,
                gaps: ctx.gaps
            ) else { return false }
            return ctx.commitWithCapturedAnimation(state: state, oldFrames: oldFrames)
        }
    }

    private func moveColumnToIndexInNiri(index: Int) {
        guard let controller else { return }
        controller.niriLayoutHandler.withNiriOperationContext { ctx, state in
            guard let column = ctx.engine.findColumn(containing: ctx.windowNode, in: ctx.wsId) else { return false }
            let oldFrames = ctx.engine.captureWindowFrames(in: ctx.wsId)
            guard ctx.engine.moveColumnToIndex(
                column,
                index,
                in: ctx.wsId,
                motion: ctx.motion,
                state: &state,
                workingFrame: ctx.workingFrame,
                gaps: ctx.gaps
            ) else { return false }
            return ctx.commitWithCapturedAnimation(state: state, oldFrames: oldFrames)
        }
    }

    private func toggleColumnTabbedInNiri() {
        guard let controller else { return }
        controller.niriLayoutHandler.withNiriWorkspaceContext { engine, wsId, motion, state, _, _, _ in
            if engine.toggleColumnTabbed(in: wsId, state: state, motion: motion) {
                controller.layoutRefreshController.requestLayoutCommandRelayout(
                    affectedWorkspaceIds: [wsId]
                )
                if engine.hasAnyWindowAnimationsRunning(in: wsId) {
                    controller.layoutRefreshController.startScrollAnimation(for: wsId)
                }
            }
        }
    }
}
