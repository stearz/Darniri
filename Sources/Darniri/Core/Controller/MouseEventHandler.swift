import AppKit
import Foundation

private let mouseRelevantModifierFlags: CGEventFlags = [
    .maskAlternate,
    .maskShift,
    .maskControl,
    .maskCommand
]

@MainActor
final class MouseEventHandler {
    enum MouseButton: Hashable {
        case left
        case right

        var pressedMask: Int {
            switch self {
            case .left: 1
            case .right: 2
            }
        }
    }

    struct State {
        enum PendingTapKind {
            case mouseMoved
            case mouseDragged(MouseButton)
        }

        struct PendingTapEvents {
            var orderedKinds: [PendingTapKind] = []
            var mouseMovedLocation: CGPoint?
            var leftMouseDraggedLocation: CGPoint?
            var rightMouseDraggedLocation: CGPoint?
            var drainScheduled = false

            var hasPendingEvents: Bool {
                !orderedKinds.isEmpty
            }

            mutating func setMouseDraggedLocation(_ location: CGPoint, for button: MouseButton) -> Bool {
                switch button {
                case .left:
                    let didCoalesce = leftMouseDraggedLocation != nil
                    leftMouseDraggedLocation = location
                    return didCoalesce
                case .right:
                    let didCoalesce = rightMouseDraggedLocation != nil
                    rightMouseDraggedLocation = location
                    return didCoalesce
                }
            }

            mutating func clear() {
                orderedKinds.removeAll(keepingCapacity: true)
                mouseMovedLocation = nil
                leftMouseDraggedLocation = nil
                rightMouseDraggedLocation = nil
                drainScheduled = false
            }
        }

        struct DebugCounters: Equatable {
            var queuedTransientEvents = 0
            var coalescedTransientEvents = 0
            var drainedTransientEvents = 0
            var drainRuns = 0
            var flushedBeforeImmediateDispatch = 0
        }

        var eventTap: CFMachPort?
        var runLoopSource: CFRunLoopSource?
        var currentHoveredEdges: ResizeEdge = []
        var isResizing: Bool = false
        var isMoving: Bool = false
        var activeInteractionButton: MouseButton?

        var dragGhostController: DragGhostController?
        var moveIsInsertMode: Bool = false

        var pendingTapEvents = PendingTapEvents()
        var debugCounters = DebugCounters()
    }

    nonisolated(unsafe) weak static var _instance: MouseEventHandler?

    weak var controller: WMController?
    var state = State()
    var pressedMouseButtonsProvider: @MainActor () -> Int = { Int(NSEvent.pressedMouseButtons) }

    init(controller: WMController) {
        self.controller = controller
    }

    func setup() {
        MouseEventHandler._instance = self

        let eventMask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = MouseEventHandler._instance?.state.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            let suppressEvent = MouseEventHandler.processTapCallback(type: type, event: event)

            return suppressEvent ? nil : Unmanaged.passUnretained(event)
        }

        state.eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: nil
        )

        if let tap = state.eventTap {
            state.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let source = state.runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            }
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func cleanup() {
        if let source = state.runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            state.runLoopSource = nil
        }
        if let tap = state.eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            state.eventTap = nil
        }
        MouseEventHandler._instance = nil
        state.currentHoveredEdges = []
        state.isResizing = false
        state.activeInteractionButton = nil
        state.pendingTapEvents.clear()
    }

    func dispatchMouseMoved(at location: CGPoint) {
        guard !isInputSuppressed else {
            resetHoveredEdgesIfNeeded()
            return
        }
        handleMouseMovedFromTap(at: location)
    }

    @discardableResult
    func dispatchMouseDown(
        at location: CGPoint,
        modifiers: CGEventFlags,
        button: MouseButton = .left
    ) -> Bool {
        guard !isInputSuppressed else { return false }
        guard controller != nil else { return false }
        if shouldBlockOwnWindowInput(at: location) {
            return false
        }
        return handleMouseDownFromTap(at: location, modifiers: modifiers, button: button)
    }

    func dispatchMouseDragged(at location: CGPoint, button: MouseButton = .left) {
        guard !isInputSuppressed else { return }
        if shouldBlockOwnWindowInput(at: location) {
            cancelActiveMouseInteraction()
            return
        }
        handleMouseDraggedFromTap(at: location, button: button)
    }

    func dispatchMouseUp(at location: CGPoint, button: MouseButton = .left) {
        guard !isInputSuppressed else { return }
        if shouldBlockOwnWindowInput(at: location) {
            cancelActiveMouseInteraction()
            return
        }
        handleMouseUpFromTap(at: location, button: button)
    }

    var isInteractiveGestureActive: Bool {
        state.isMoving || state.isResizing
    }

    func mouseTapDebugSnapshot() -> State.DebugCounters {
        state.debugCounters
    }

    func handleInputSuppressionBegan() {
        dropPendingTapEvents()
    }

    func receiveTapMouseMoved(at location: CGPoint) {
        enqueuePendingMouseMoved(at: location)
    }

    @discardableResult
    func receiveTapMouseDown(
        at location: CGPoint,
        modifiers: CGEventFlags,
        button: MouseButton = .left
    ) -> Bool {
        if shouldBlockOwnWindowInput(at: location) {
            dropPendingTapEvents()
        } else {
            flushPendingTapEvents(beforeImmediateDispatch: true)
        }
        return dispatchMouseDown(at: location, modifiers: modifiers, button: button)
    }

    func receiveTapMouseDragged(at location: CGPoint, button: MouseButton = .left) {
        enqueuePendingMouseDragged(at: location, button: button)
    }

    func receiveTapMouseUp(at location: CGPoint, button: MouseButton = .left) {
        if shouldBlockOwnWindowInput(at: location) {
            dropPendingTapEvents()
        } else {
            flushPendingTapEvents(beforeImmediateDispatch: true)
        }
        dispatchMouseUp(at: location, button: button)
    }

    private var isInputSuppressed: Bool {
        guard let controller else { return true }
        return controller.isLockScreenActive || controller.isFrontmostAppLockScreen()
    }

    private func dropPendingTapEvents() {
        guard state.pendingTapEvents.hasPendingEvents else { return }
        state.pendingTapEvents.clear()
    }

    private func cancelActiveMouseInteraction() {
        guard let controller else { return }

        if state.isMoving {
            controller.niriEngine?.interactiveMoveCancel()
            state.dragGhostController?.endDrag()
            state.isMoving = false
            state.moveIsInsertMode = false
            state.activeInteractionButton = nil
        }

        if state.isResizing {
            controller.niriEngine?.clearInteractiveResize()
            state.isResizing = false
            state.activeInteractionButton = nil
        }

        resetHoveredEdgesIfNeeded()
    }

    private func workspaceIdForPointer(at location: CGPoint) -> WorkspaceDescriptor.ID? {
        guard let controller else { return nil }
        guard let monitor = location.monitorApproximation(in: controller.workspaceManager.monitors) else {
            return controller.activeWorkspace()?.id
        }
        return controller.workspaceManager.activeWorkspaceOrFirst(on: monitor.id)?.id
    }

    private func shouldBlockOwnWindowInput(at location: CGPoint) -> Bool {
        guard let controller else { return false }
        return controller.isPointInOwnWindow(location)
    }

    private func resetHoveredEdgesIfNeeded() {
        if !state.currentHoveredEdges.isEmpty {
            NSCursor.arrow.set()
            state.currentHoveredEdges = []
        }
    }

    private func schedulePendingTapDrainIfNeeded() {
        guard !state.pendingTapEvents.drainScheduled else { return }
        state.pendingTapEvents.drainScheduled = true

        let mainRunLoop = CFRunLoopGetMain()
        CFRunLoopPerformBlock(mainRunLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.flushPendingTapEvents()
            }
        }
        CFRunLoopWakeUp(mainRunLoop)
    }

    private func enqueuePendingMouseMoved(at location: CGPoint) {
        state.debugCounters.queuedTransientEvents += 1
        let didCoalesce = state.pendingTapEvents.mouseMovedLocation != nil
        state.pendingTapEvents.mouseMovedLocation = location
        if !didCoalesce {
            state.pendingTapEvents.orderedKinds.append(.mouseMoved)
        } else {
            state.debugCounters.coalescedTransientEvents += 1
        }
        schedulePendingTapDrainIfNeeded()
    }

    private func enqueuePendingMouseDragged(at location: CGPoint, button: MouseButton) {
        state.debugCounters.queuedTransientEvents += 1
        let didCoalesce = state.pendingTapEvents.setMouseDraggedLocation(location, for: button)
        if !didCoalesce {
            state.pendingTapEvents.orderedKinds.append(.mouseDragged(button))
        } else {
            state.debugCounters.coalescedTransientEvents += 1
        }
        schedulePendingTapDrainIfNeeded()
    }

    private func flushPendingTapEvents(beforeImmediateDispatch: Bool = false) {
        guard state.pendingTapEvents.hasPendingEvents else { return }

        if beforeImmediateDispatch {
            state.debugCounters.flushedBeforeImmediateDispatch += 1
        }

        let pendingKinds = state.pendingTapEvents.orderedKinds
        let pendingMouseMoved = state.pendingTapEvents.mouseMovedLocation
        let pendingLeftMouseDragged = state.pendingTapEvents.leftMouseDraggedLocation
        let pendingRightMouseDragged = state.pendingTapEvents.rightMouseDraggedLocation

        state.pendingTapEvents.clear()
        state.debugCounters.drainRuns += 1

        for kind in pendingKinds {
            switch kind {
            case .mouseMoved:
                if let location = pendingMouseMoved {
                    state.debugCounters.drainedTransientEvents += 1
                    dispatchMouseMoved(at: location)
                }
            case let .mouseDragged(button):
                let location = switch button {
                case .left: pendingLeftMouseDragged
                case .right: pendingRightMouseDragged
                }
                if let location {
                    state.debugCounters.drainedTransientEvents += 1
                    replayQueuedMouseDragged(at: location, button: button)
                }
            }
        }
    }

    private func replayQueuedMouseDragged(at location: CGPoint, button: MouseButton) {
        guard !isInputSuppressed else { return }
        if shouldBlockOwnWindowInput(at: location) {
            cancelActiveMouseInteraction()
            return
        }
        handleMouseDraggedFromTap(at: location, button: button, requirePressedButtonCheck: false)
    }

    private func handleMouseMovedFromTap(at location: CGPoint) {
        guard let controller else { return }
        guard controller.isEnabled else {
            resetHoveredEdgesIfNeeded()
            return
        }
        if controller.isOverviewOpen() { return }

        if shouldBlockOwnWindowInput(at: location) {
            resetHoveredEdgesIfNeeded()
            return
        }

        guard !state.isResizing else { return }
        resetHoveredEdgesIfNeeded()
    }

    private func handleMouseDownFromTap(
        at location: CGPoint,
        modifiers: CGEventFlags,
        button: MouseButton
    ) -> Bool {
        guard let controller else { return false }
        guard controller.isEnabled else { return false }
        if controller.isOverviewOpen() { return false }

        if shouldBlockOwnWindowInput(at: location) {
            return false
        }

        guard let engine = controller.niriEngine,
              let wsId = workspaceIdForPointer(at: location) ?? controller.activeWorkspace()?.id
        else {
            return false
        }

        if button == .left,
           modifiers.intersection(mouseRelevantModifierFlags).isEmpty,
           let window = engine.hitTestFocusableWindow(point: location, in: wsId)
        {
            controller.axEventHandler.noteMouseFocusIntent(token: window.token)
        }

        if button == .left, modifiers.contains(.maskAlternate) {
            if let tiledWindow = engine.hitTestTiled(point: location, in: wsId),
               let monitor = controller.workspaceManager.monitor(for: wsId)
            {
                let workingFrame = controller.insetWorkingFrame(for: monitor)
                let gaps = CGFloat(controller.workspaceManager.gaps)

                let isInsertMode = modifiers.contains(.maskShift)
                var moveStarted = false
                controller.workspaceManager.withNiriViewportState(for: wsId) { vstate in
                    if engine.interactiveMoveBegin(
                        windowId: tiledWindow.id,
                        windowHandle: tiledWindow.handle,
                        startLocation: location,
                        isInsertMode: isInsertMode,
                        in: wsId,
                        motion: controller.motionPolicy.snapshot(),
                        state: &vstate,
                        workingFrame: workingFrame,
                        gaps: gaps
                    ) {
                        moveStarted = true
                    }
                }
                if moveStarted {
                    state.moveIsInsertMode = isInsertMode
                    state.isMoving = true
                    state.activeInteractionButton = button
                    NSCursor.closedHand.set()

                    if let entry = controller.workspaceManager.entry(for: tiledWindow.handle),
                       let frame = AXWindowService.framePreferFast(entry.axRef)
                    {
                        if state.dragGhostController == nil {
                            state.dragGhostController = DragGhostController()
                        }
                        state.dragGhostController?.beginDrag(
                            windowId: entry.windowId,
                            originalFrame: frame,
                            cursorLocation: location
                        )
                    }
                    return false
                }
            }
            return false
        }

        guard button == .right,
              Self.modifierFlagsMatch(modifiers, required: controller.settings.mouseResizeModifierKey.cgEventFlag)
        else { return false }

        guard let tiledWindow = engine.hitTestTiled(point: location, in: wsId),
              let frame = tiledWindow.renderedFrame ?? tiledWindow.frame
        else { return false }

        let edges = resizeEdges(for: location, in: frame)
        let currentViewOffset = controller.workspaceManager.niriViewportState(for: wsId).viewOffsetPixels.current()
        if engine.interactiveResizeBegin(
            windowId: tiledWindow.id,
            edges: edges,
            startLocation: location,
            in: wsId,
            viewOffset: currentViewOffset
        ) {
            state.isResizing = true
            state.activeInteractionButton = button
            state.currentHoveredEdges = edges
            controller.niriLayoutHandler.cancelActiveAnimations(for: wsId)
            edges.cursor.set()
            return true
        }
        return false
    }

    private func resizeEdges(for location: CGPoint, in frame: CGRect) -> ResizeEdge {
        var edges: ResizeEdge = location.x < frame.midX ? [.left] : [.right]
        edges.insert(location.y < frame.midY ? .bottom : .top)
        return edges
    }

    private func shouldAcceptInteractionButton(_ button: MouseButton) -> Bool {
        state.activeInteractionButton == nil || state.activeInteractionButton == button
    }

    private func shouldSuppressRightMouseEvent(type: CGEventType) -> Bool {
        guard state.activeInteractionButton == .right else { return false }
        switch type {
        case .rightMouseDown,
             .rightMouseDragged,
             .rightMouseUp:
            return state.isResizing
        default:
            return false
        }
    }

    private func handleMouseDraggedFromTap(
        at location: CGPoint,
        button: MouseButton,
        requirePressedButtonCheck: Bool = true
    ) {
        guard let controller else { return }
        guard controller.isEnabled else { return }
        if controller.isOverviewOpen() { return }
        if requirePressedButtonCheck {
            guard pressedMouseButtonsProvider() & button.pressedMask != 0 else { return }
        }

        if state.isMoving {
            guard shouldAcceptInteractionButton(button) else { return }
            guard let engine = controller.niriEngine,
                  let wsId = controller.activeWorkspace()?.id
            else {
                return
            }

            let hoverTarget = engine.interactiveMoveUpdate(currentLocation: location, in: wsId)
            state.dragGhostController?.updatePosition(cursorLocation: location)

            if let hoverTarget {
                switch hoverTarget {
                case let .window(nodeId, handle, insertPosition):
                    if insertPosition == .swap {
                        if let entry = controller.workspaceManager.entry(for: handle),
                           let frame = AXWindowService.framePreferFast(entry.axRef)
                        {
                            state.dragGhostController?.showSwapTarget(frame: frame)
                        }
                    } else if let wsId = controller.activeWorkspace()?.id,
                              let dropFrame = engine.insertionDropzoneFrame(
                                  targetWindowId: nodeId,
                                  position: insertPosition,
                                  in: wsId,
                                  gaps: CGFloat(controller.workspaceManager.gaps)
                              )
                    {
                        state.dragGhostController?.showSwapTarget(frame: dropFrame)
                    }
                default:
                    state.dragGhostController?.hideSwapTarget()
                }
            } else {
                state.dragGhostController?.hideSwapTarget()
            }
            return
        }

        guard state.isResizing else { return }
        guard shouldAcceptInteractionButton(button) else { return }

        guard let engine = controller.niriEngine,
              let monitor = controller.monitorForInteraction()
        else {
            return
        }

        let gaps = LayoutGaps(
            horizontal: CGFloat(controller.workspaceManager.gaps),
            vertical: CGFloat(controller.workspaceManager.gaps),
            outer: controller.workspaceManager.outerGaps
        )
        let insetFrame = controller.insetWorkingFrame(for: monitor)
        guard let wsId = controller.activeWorkspace()?.id else { return }

        if engine.interactiveResizeUpdate(
            currentLocation: location,
            monitorFrame: insetFrame,
            gaps: gaps,
            viewportState: { mutate in
                controller.workspaceManager.withNiriViewportState(for: wsId, mutate)
            }
        ) {
            controller.layoutRefreshController.requestImmediateRelayout(reason: .interactiveGesture)
        }
    }

    private func handleMouseUpFromTap(at location: CGPoint, button: MouseButton) {
        guard let controller else { return }
        if controller.isOverviewOpen() { return }

        if state.isMoving {
            guard shouldAcceptInteractionButton(button) else { return }
            if let engine = controller.niriEngine,
               let wsId = controller.activeWorkspace()?.id,
               let monitor = controller.workspaceManager.monitor(for: wsId)
            {
                let workingFrame = controller.insetWorkingFrame(for: monitor)
                let gaps = CGFloat(controller.workspaceManager.gaps)
                var didEnd = false
                controller.workspaceManager.withNiriViewportState(for: wsId) { vstate in
                    didEnd = engine.interactiveMoveEnd(
                        at: location,
                        in: wsId,
                        motion: controller.motionPolicy.snapshot(),
                        state: &vstate,
                        workingFrame: workingFrame,
                        gaps: gaps
                    )
                }
                if didEnd {
                    controller.layoutRefreshController.requestImmediateRelayout(reason: .interactiveGesture)
                }
            }

            state.dragGhostController?.endDrag()
            state.isMoving = false
            state.moveIsInsertMode = false
            state.activeInteractionButton = nil
            NSCursor.arrow.set()
            return
        }

        guard state.isResizing else { return }
        guard shouldAcceptInteractionButton(button) else { return }

        if let engine = controller.niriEngine,
           let wsId = controller.activeWorkspace()?.id,
           let monitor = controller.workspaceManager.monitor(for: wsId)
        {
            let workingFrame = controller.insetWorkingFrame(for: monitor)
            let gaps = CGFloat(controller.workspaceManager.gaps)
            let hadInteractiveResize = engine.interactiveResize != nil

            controller.workspaceManager.withNiriViewportState(for: wsId) { vstate in
                engine.interactiveResizeEnd(
                    motion: controller.motionPolicy.snapshot(),
                    state: &vstate,
                    workingFrame: workingFrame,
                    gaps: gaps
                )
            }
            if hadInteractiveResize {
                controller.layoutRefreshController.requestImmediateRelayout(reason: .interactiveGesture)
            }
        }

        state.isResizing = false
        state.activeInteractionButton = nil
        NSCursor.arrow.set()
        state.currentHoveredEdges = []
    }

    private nonisolated static func processTapCallback(
        type: CGEventType,
        event: CGEvent,
        isMainThread: Bool = Thread.isMainThread
    ) -> Bool {
        guard isMainThread else { return false }

        let location = event.location
        let screenLocation = ScreenCoordinateSpace.toAppKit(point: location)
        let modifiers = event.flags
        var suppressEvent = false

        MainActor.assumeIsolated {
            guard let handler = MouseEventHandler._instance else { return }
            switch type {
            case .mouseMoved:
                handler.receiveTapMouseMoved(at: screenLocation)
            case .leftMouseDown:
                _ = handler.receiveTapMouseDown(at: screenLocation, modifiers: modifiers)
            case .leftMouseDragged:
                handler.receiveTapMouseDragged(at: screenLocation)
            case .leftMouseUp:
                handler.receiveTapMouseUp(at: screenLocation)
            case .rightMouseDown:
                suppressEvent = handler.receiveTapMouseDown(
                    at: screenLocation,
                    modifiers: modifiers,
                    button: .right
                )
            case .rightMouseDragged:
                suppressEvent = handler.shouldSuppressRightMouseEvent(type: type)
                handler.receiveTapMouseDragged(at: screenLocation, button: .right)
            case .rightMouseUp:
                suppressEvent = handler.shouldSuppressRightMouseEvent(type: type)
                handler.receiveTapMouseUp(at: screenLocation, button: .right)
            default:
                break
            }
        }

        return suppressEvent
    }

    nonisolated static func modifierFlagsMatch(_ modifiers: CGEventFlags, required: CGEventFlags) -> Bool {
        modifiers.intersection(mouseRelevantModifierFlags) == required
    }
}
