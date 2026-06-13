import Foundation

enum DarniriFocusNotificationKey {
    static let oldWorkspaceId = "oldWorkspaceId"
    static let newWorkspaceId = "newWorkspaceId"
    static let oldWorkspaceName = "oldWorkspaceName"
    static let newWorkspaceName = "newWorkspaceName"
    static let oldMonitorIndex = "oldMonitorIndex"
    static let newMonitorIndex = "newMonitorIndex"
    static let oldMonitorName = "oldMonitorName"
    static let newMonitorName = "newMonitorName"
    static let oldWindowId = "oldWindowId"
    static let newWindowId = "newWindowId"
    static let oldWindowToken = "oldWindowToken"
    static let newWindowToken = "newWindowToken"
    static let oldHandleId = "oldHandleId"
    static let newHandleId = "newHandleId"
}

extension Notification.Name {
    static let darniriFocusChanged = Notification.Name("Darniri.FocusChanged")
    static let darniriFocusedWorkspaceChanged = Notification.Name("Darniri.FocusedWorkspaceChanged")
    static let darniriFocusedMonitorChanged = Notification.Name("Darniri.FocusedMonitorChanged")
}

@MainActor
final class FocusNotificationDispatcher {
    struct ChangeSet: Equatable {
        let focusChanged: Bool
        let workspaceChanged: Bool
        let monitorChanged: Bool
    }

    weak var controller: WMController?

    private var lastNotifiedWorkspaceId: WorkspaceDescriptor.ID?
    private var lastNotifiedMonitorId: Monitor.ID?
    private var lastNotifiedFocusedToken: WindowToken?
    private var lastNotifiedFocusedWindowId: Int?

    init(controller: WMController) {
        self.controller = controller
    }

    @discardableResult
    func notifyFocusChangesIfNeeded() -> ChangeSet {
        guard let controller else {
            return ChangeSet(focusChanged: false, workspaceChanged: false, monitorChanged: false)
        }
        var focusChanged = false

        let currentMonitorId = controller.workspaceManager.interactionMonitorId ?? controller.monitorForInteraction()?
            .id
        let currentWorkspaceId = controller.workspaceManager.focusedToken
            .flatMap { controller.workspaceManager.workspace(for: $0) }
            ?? currentMonitorId.flatMap { controller.workspaceManager.currentActiveWorkspace(on: $0)?.id }

        let currentToken = controller.workspaceManager.focusedToken
        let currentWindowId = currentToken
            .flatMap { controller.workspaceManager.entry(for: $0)?.windowId }

        if currentToken != lastNotifiedFocusedToken || currentWindowId != lastNotifiedFocusedWindowId {
            var info: [AnyHashable: Any] = [:]
            if let oldToken = lastNotifiedFocusedToken {
                info[DarniriFocusNotificationKey.oldWindowToken] = oldToken
                info[DarniriFocusNotificationKey.oldHandleId] = oldToken
            }
            if let newToken = currentToken {
                info[DarniriFocusNotificationKey.newWindowToken] = newToken
                info[DarniriFocusNotificationKey.newHandleId] = newToken
            }
            if let oldWindowId = lastNotifiedFocusedWindowId {
                info[DarniriFocusNotificationKey.oldWindowId] = oldWindowId
            }
            if let newWindowId = currentWindowId { info[DarniriFocusNotificationKey.newWindowId] = newWindowId }

            NotificationCenter.default.post(
                name: .darniriFocusChanged,
                object: controller,
                userInfo: info.isEmpty ? nil : info
            )
            lastNotifiedFocusedToken = currentToken
            lastNotifiedFocusedWindowId = currentWindowId
            focusChanged = true
        }

        var workspaceInfo: [AnyHashable: Any] = [:]
        if let oldId = lastNotifiedWorkspaceId {
            workspaceInfo[DarniriFocusNotificationKey.oldWorkspaceId] = oldId
            if let name = controller.workspaceManager.descriptor(for: oldId)?
                .name { workspaceInfo[DarniriFocusNotificationKey.oldWorkspaceName] = name }
        }
        if let newId = currentWorkspaceId {
            workspaceInfo[DarniriFocusNotificationKey.newWorkspaceId] = newId
            if let name = controller.workspaceManager.descriptor(for: newId)?
                .name { workspaceInfo[DarniriFocusNotificationKey.newWorkspaceName] = name }
        }
        let workspaceChanged = postNotificationIfChanged(
            name: .darniriFocusedWorkspaceChanged,
            current: currentWorkspaceId,
            last: &lastNotifiedWorkspaceId,
            info: workspaceInfo,
            sender: controller
        )

        var monitorInfo: [AnyHashable: Any] = [:]
        if let oldId = lastNotifiedMonitorId {
            monitorInfo[DarniriFocusNotificationKey.oldMonitorIndex] = oldId.displayId
            if let name = controller.workspaceManager.monitor(byId: oldId)?
                .name { monitorInfo[DarniriFocusNotificationKey.oldMonitorName] = name }
        }
        if let newId = currentMonitorId {
            monitorInfo[DarniriFocusNotificationKey.newMonitorIndex] = newId.displayId
            if let name = controller.workspaceManager.monitor(byId: newId)?
                .name { monitorInfo[DarniriFocusNotificationKey.newMonitorName] = name }
        }
        let monitorChanged = postNotificationIfChanged(
            name: .darniriFocusedMonitorChanged,
            current: currentMonitorId,
            last: &lastNotifiedMonitorId,
            info: monitorInfo,
            sender: controller
        )

        return ChangeSet(
            focusChanged: focusChanged,
            workspaceChanged: workspaceChanged,
            monitorChanged: monitorChanged
        )
    }

    private func postNotificationIfChanged<T: Equatable>(
        name: Notification.Name,
        current: T?,
        last: inout T?,
        info: [AnyHashable: Any],
        sender: AnyObject
    ) -> Bool {
        guard current != last else { return false }
        NotificationCenter.default.post(
            name: name,
            object: sender,
            userInfo: info.isEmpty ? nil : info
        )
        last = current
        return true
    }
}
