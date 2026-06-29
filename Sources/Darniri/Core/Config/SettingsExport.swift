import Foundation

// MARK: - SettingsExport

struct SettingsColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
}

struct SettingsExport: Equatable {
    var hotkeysEnabled: Bool
    var focusFollowsWindowToMonitor: Bool
    var mouseWarpMonitorOrder: [String]
    var mouseWarpAxis: String?
    var mouseWarpMargin: Int
    var gapSize: Double
    var outerGapLeft: Double
    var outerGapRight: Double
    var outerGapTop: Double
    var outerGapBottom: Double

    var niriMaxVisibleColumns: Int
    var niriInfiniteLoop: Bool
    var niriCenterFocusedColumn: String
    var niriAlwaysCenterSingleColumn: Bool
    var niriSingleWindowAspectRatio: String
    var niriColumnWidthPresets: [Double]?
    var niriDefaultColumnWidth: Double?

    var workspaceConfigurations: [WorkspaceConfiguration]

    var bordersEnabled: Bool
    var borderWidth: Double
    var borderColorRed: Double
    var borderColorGreen: Double
    var borderColorBlue: Double
    var borderColorAlpha: Double

    var hotkeyBindings: [HotkeyBinding]
    var hyperTrigger: HyperKeyTrigger
    var hyperKeyHoldThresholdMilliseconds: Int

    var workspaceBarEnabled: Bool
    var workspaceBarShowLabels: Bool
    var workspaceBarShowFloatingWindows: Bool
    var workspaceBarWindowLevel: String
    var workspaceBarPosition: String
    var workspaceBarNotchAware: Bool
    var workspaceBarDeduplicateAppIcons: Bool
    var workspaceBarHideEmptyWorkspaces: Bool
    var workspaceBarReserveLayoutSpace: Bool
    var workspaceBarHeight: Double
    var workspaceBarBackgroundOpacity: Double
    var workspaceBarXOffset: Double
    var workspaceBarYOffset: Double
    var workspaceBarAccentColor: SettingsColor?
    var workspaceBarTextColor: SettingsColor?
    var monitorBarSettings: [MonitorBarSettings]

    var appRules: [AppRule]
    var monitorOrientationSettings: [MonitorOrientationSettings]
    var monitorNiriSettings: [MonitorNiriSettings]

    var mouseResizeModifierKey: String
    var animationsEnabled: Bool

    var appearanceMode: String

    /// The modifier key used for Darniri's focus/move hotkeys (see `NavigationModifier`).
    /// Stored as raw string so the type stays in the Input module.
    var navigationModifier: String

    /// The keymap used for directional navigation hotkeys (see `HotkeyKeymap`).
    /// Stored as raw string so the type stays in the Input module.
    var hotkeyKeymap: String
}

// MARK: - Defaults & Diffing

extension SettingsExport {
    static func defaults() -> SettingsExport {
        SettingsExport(
            hotkeysEnabled: true,
            focusFollowsWindowToMonitor: false,
            mouseWarpMonitorOrder: [],
            mouseWarpAxis: MouseWarpAxis.horizontal.rawValue,
            mouseWarpMargin: 1,
            gapSize: 16,
            outerGapLeft: 0,
            outerGapRight: 0,
            outerGapTop: 0,
            outerGapBottom: 0,
            niriMaxVisibleColumns: 2,
            niriInfiniteLoop: false,
            niriCenterFocusedColumn: CenterFocusedColumn.always.rawValue,
            niriAlwaysCenterSingleColumn: false,
            niriSingleWindowAspectRatio: SingleWindowAspectRatio.none.rawValue,
            niriColumnWidthPresets: BuiltInSettingsDefaults.niriColumnWidthPresets,
            niriDefaultColumnWidth: 0.5,
            workspaceConfigurations: BuiltInSettingsDefaults.workspaceConfigurations,
            bordersEnabled: true,
            borderWidth: 2.0,
            borderColorRed: 0.084585202284378935,
            borderColorGreen: 1.0,
            borderColorBlue: 0.97930003794467602,
            borderColorAlpha: 1.0,
            hotkeyBindings: HotkeyBindingRegistry.defaults(),
            hyperTrigger: .default,
            hyperKeyHoldThresholdMilliseconds: 150,
            workspaceBarEnabled: false,
            workspaceBarShowLabels: true,
            workspaceBarShowFloatingWindows: false,
            workspaceBarWindowLevel: WorkspaceBarWindowLevel.popup.rawValue,
            workspaceBarPosition: WorkspaceBarPosition.overlappingMenuBar.rawValue,
            workspaceBarNotchAware: true,
            workspaceBarDeduplicateAppIcons: false,
            workspaceBarHideEmptyWorkspaces: true,
            workspaceBarReserveLayoutSpace: false,
            workspaceBarHeight: 24.0,
            workspaceBarBackgroundOpacity: 0.1,
            workspaceBarXOffset: 0.0,
            workspaceBarYOffset: 0.0,
            workspaceBarAccentColor: nil,
            workspaceBarTextColor: nil,
            monitorBarSettings: [],
            appRules: BuiltInSettingsDefaults.appRules,
            monitorOrientationSettings: [],
            monitorNiriSettings: [],
            mouseResizeModifierKey: MouseResizeModifierKey.option.rawValue,
            animationsEnabled: true,
            appearanceMode: AppearanceMode.dark.rawValue,
            navigationModifier: NavigationModifier.control.rawValue,
            hotkeyKeymap: HotkeyKeymap.arrows.rawValue
        )
    }
}
