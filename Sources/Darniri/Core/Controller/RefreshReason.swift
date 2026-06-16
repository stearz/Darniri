import Foundation

enum RelayoutSchedulingPolicy: Equatable, Sendable {
    case plain
    case debounced(nanoseconds: UInt64, dropWhileBusy: Bool)

    var debounceInterval: UInt64 {
        switch self {
        case .plain:
            0
        case let .debounced(nanoseconds, _):
            nanoseconds
        }
    }

    var shouldDropWhileBusy: Bool {
        switch self {
        case .plain:
            false
        case let .debounced(_, dropWhileBusy):
            dropWhileBusy
        }
    }
}

enum RefreshRequestRoute: Equatable, Sendable {
    case fullRescan
    case relayout
    case immediateRelayout
    case visibilityRefresh
    case windowRemoval
}

enum RefreshReason: String, Sendable {
    case startup
    case appLaunched
    case unlock
    case activeSpaceChanged
    case monitorConfigurationChanged
    case appRulesChanged
    case workspaceConfigChanged
    case layoutConfigChanged
    case monitorSettingsChanged
    case gapsChanged
    case workspaceTransition
    case appActivationTransition
    case workspaceLayoutToggled
    case appTerminated
    case windowRuleReevaluation
    case layoutCommand
    case interactiveGesture
    case axWindowCreated
    case axWindowChanged
    case staleLayoutPlan
    case staleFullRescan
    case windowDestroyed
    case appHidden
    case appUnhidden
    case overviewMutation

    var requestRoute: RefreshRequestRoute {
        switch self {
        case .startup,
             .appLaunched,
             .unlock,
             .activeSpaceChanged,
             .monitorConfigurationChanged,
             .appRulesChanged,
             .workspaceConfigChanged,
             .appTerminated,
             .staleFullRescan:
            .fullRescan
        case .layoutConfigChanged,
             .monitorSettingsChanged,
             .gapsChanged,
             .workspaceLayoutToggled,
             .windowRuleReevaluation,
             .axWindowCreated,
             .axWindowChanged,
             .staleLayoutPlan:
            .relayout
        case .workspaceTransition,
             .appActivationTransition,
             .layoutCommand,
             .interactiveGesture,
             .overviewMutation:
            .immediateRelayout
        case .appHidden,
             .appUnhidden:
            .visibilityRefresh
        case .windowDestroyed:
            .windowRemoval
        }
    }

    /// Whether a refresh with this reason can change a monitor's row CONTENTS (windows
    /// added/removed/moved between rows, a row switch that changes the visible row, or a
    /// topology change). Only these reasons need the dynamic-row normalization pass; pure
    /// relayout / visibility / scroll-animation refreshes leave row membership untouched
    /// and must NOT re-run the per-row emptiness queries on every frame.
    ///
    /// When in doubt this errs toward `true`: correctness of the empty-buffer invariant
    /// beats sparing a normalization pass.
    var mayChangeRowContents: Bool {
        switch self {
        // Full rescans + window lifecycle: adopt/drop windows, re-evaluate rules that can
        // move windows between rows, switch the visible row → contents change.
        case .startup,
             .appLaunched,
             .unlock,
             .activeSpaceChanged,
             .monitorConfigurationChanged,
             .appRulesChanged,
             .workspaceConfigChanged,
             .appTerminated,
             .staleFullRescan,
             .workspaceTransition,
             .appActivationTransition,
             .layoutCommand,
             .windowRuleReevaluation,
             .axWindowCreated,
             .axWindowChanged,
             .windowDestroyed,
             .overviewMutation:
            true
        // Pure relayout: gaps/layout style/monitor settings/layout-type toggle only
        // re-position windows within their existing rows.
        case .layoutConfigChanged,
             .monitorSettingsChanged,
             .gapsChanged,
             .workspaceLayoutToggled,
             // Retry of an already-scheduled relayout — no new content delta.
             .staleLayoutPlan,
             // Scroll/drag animation frames — the hot path; membership is unchanged.
             .interactiveGesture,
             // Visibility-only: a hidden/unhidden window still belongs to its row.
             .appHidden,
             .appUnhidden:
            false
        }
    }

    var relayoutSchedulingPolicy: RelayoutSchedulingPolicy {
        switch self {
        case .startup,
             .appLaunched,
             .unlock,
             .activeSpaceChanged,
             .monitorConfigurationChanged,
             .appRulesChanged,
             .workspaceConfigChanged,
             .layoutConfigChanged,
             .monitorSettingsChanged,
             .gapsChanged,
             .workspaceTransition,
             .appActivationTransition,
             .workspaceLayoutToggled,
             .appTerminated,
             .staleFullRescan,
             .windowRuleReevaluation,
             .layoutCommand,
             .interactiveGesture,
             .appHidden,
             .appUnhidden,
             .overviewMutation:
            .plain
        case .axWindowCreated:
            .debounced(nanoseconds: 4_000_000, dropWhileBusy: false)
        case .axWindowChanged:
            .debounced(nanoseconds: 8_000_000, dropWhileBusy: true)
        case .staleLayoutPlan:
            .plain
        case .windowDestroyed:
            .plain
        }
    }
}
