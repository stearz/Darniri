import Foundation

enum FocusPolicyLeaseOwner: String, Equatable {
    case nativeMenu = "native_menu"
    case windowCloseFocusRecovery = "window_close_focus_recovery"
    case nativeAppSwitch = "native_app_switch"
    case ruleCreatedFloatingWindow = "rule_created_floating_window"
}

struct FocusPolicyLease: Equatable {
    let owner: FocusPolicyLeaseOwner
    let reason: String
    let expiresAt: Date?
}

enum FocusPolicyRequest: Equatable {
    case managedAppActivation(source: ActivationEventSource)
}

struct FocusPolicyDecision: Equatable {
    let allowsFocusChange: Bool
    let reason: String?

    static let allow = FocusPolicyDecision(allowsFocusChange: true, reason: nil)

    static func deny(reason: String) -> FocusPolicyDecision {
        FocusPolicyDecision(allowsFocusChange: false, reason: reason)
    }
}

@MainActor
final class FocusPolicyEngine {
    private static let effectiveLeasePriority: [FocusPolicyLeaseOwner] = [
        .nativeMenu,
        .windowCloseFocusRecovery,
        .nativeAppSwitch,
        .ruleCreatedFloatingWindow
    ]

    private let nowProvider: () -> Date
    private var leasesByOwner: [FocusPolicyLeaseOwner: FocusPolicyLease] = [:]
    private var activeLeaseStorage: FocusPolicyLease?
    var activeLease: FocusPolicyLease? {
        pruneExpiredLeasesIfNeeded()
        return activeLeaseStorage
    }

    var onLeaseChanged: ((FocusPolicyLease?) -> Void)?

    init(nowProvider: @escaping () -> Date = Date.init) {
        self.nowProvider = nowProvider
    }

    func beginLease(
        owner: FocusPolicyLeaseOwner,
        reason: String,
        duration: TimeInterval? = 0.35,
        notify: Bool = true
    ) {
        pruneExpiredLeasesIfNeeded(notify: notify)
        let expiresAt = duration.map { nowProvider().addingTimeInterval($0) }
        let lease = FocusPolicyLease(
            owner: owner,
            reason: reason,
            expiresAt: expiresAt
        )
        leasesByOwner[owner] = lease
        reconcileActiveLease(notify: notify)
    }

    func endLease(owner: FocusPolicyLeaseOwner, notify: Bool = true) {
        guard leasesByOwner.removeValue(forKey: owner) != nil else { return }
        pruneExpiredLeasesIfNeeded(notify: notify)
        reconcileActiveLease(notify: notify)
    }

    func evaluate(_ request: FocusPolicyRequest) -> FocusPolicyDecision {
        pruneExpiredLeasesIfNeeded()

        switch request {
        case let .managedAppActivation(source):
            if let menuLease = leasesByOwner[.nativeMenu], !source.isAuthoritative {
                return .deny(reason: menuLease.reason)
            }
            return .allow
        }
    }

    private func pruneExpiredLeasesIfNeeded(notify: Bool = true) {
        let now = nowProvider()
        let expiredOwners = leasesByOwner.compactMap { owner, lease -> FocusPolicyLeaseOwner? in
            guard let expiresAt = lease.expiresAt, expiresAt <= now else {
                return nil
            }
            return owner
        }

        guard !expiredOwners.isEmpty else { return }
        for owner in expiredOwners {
            leasesByOwner.removeValue(forKey: owner)
        }
        reconcileActiveLease(notify: notify && expiredOwners.contains(where: shouldNotifyExpiredLeaseChange))
    }

    private func shouldNotifyExpiredLeaseChange(owner: FocusPolicyLeaseOwner) -> Bool {
        owner != .windowCloseFocusRecovery
    }

    private func reconcileActiveLease(notify: Bool) {
        let nextLease = effectiveLease()
        guard nextLease != activeLeaseStorage else { return }
        activeLeaseStorage = nextLease
        if notify {
            onLeaseChanged?(nextLease)
        }
    }

    private func effectiveLease() -> FocusPolicyLease? {
        for owner in Self.effectiveLeasePriority {
            if let lease = leasesByOwner[owner] {
                return lease
            }
        }
        return nil
    }

}
