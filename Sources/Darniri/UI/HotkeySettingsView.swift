import SwiftUI

enum HotkeyInputMonitoringStatus: Equatable {
    case granted
    case denied

    init(granted: Bool) {
        self = granted ? .granted : .denied
    }

    var displayText: String {
        switch self {
        case .granted:
            "Granted"
        case .denied:
            "Denied"
        }
    }
}

enum HotkeySettingsDisplayModel {
    static func displayString(for binding: KeyBinding) -> String {
        if binding.isUnassigned {
            return "Unassigned"
        }
        let prefix = binding.usesHyper ? "Darniri+" : ""
        return prefix + KeySymbolMapper.displayString(keyCode: binding.keyCode, modifiers: binding.modifiers)
    }

    static func displayString(for trigger: HotkeyTrigger) -> String {
        switch trigger {
        case .unassigned:
            return "Unassigned"
        case let .chord(binding):
            return displayString(for: binding)
        }
    }

    static func humanReadableString(for binding: KeyBinding) -> String {
        if binding.isUnassigned {
            return "Unassigned"
        }
        let base = KeySymbolMapper.humanReadableString(
            keyCode: binding.keyCode,
            modifiers: binding.modifiers
        )
        return binding.usesHyper ? "Darniri modifier+\(base)" : base
    }

    static func humanReadableString(for trigger: HotkeyTrigger) -> String {
        switch trigger {
        case .unassigned:
            return "Unassigned"
        case let .chord(binding):
            return humanReadableString(for: binding)
        }
    }

    static func inputMonitoringStatus(
        preflightGranted: Bool,
        requestIfNeeded: Bool,
        requestGranted: Bool
    ) -> HotkeyInputMonitoringStatus {
        HotkeyInputMonitoringStatus(granted: preflightGranted || (requestIfNeeded && requestGranted))
    }
}

struct HotkeySettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: WMController
    @State private var confirmsResetToDefaults = false

    private var effectiveBindings: [HotkeyBinding] {
        controller.effectiveBindings(
            for: settings.hotkeyBindings,
            modifier: settings.navigationModifier,
            keymap: settings.hotkeyKeymap
        )
    }

    var body: some View {
        SettingsPage(subtitle: "Control moves focus. Add Shift to move a window or Option to move a whole column.") {
            Section("Shortcuts") {
                ForEach(effectiveBindings) { binding in
                    LabeledContent(binding.command.displayName) {
                        Text(HotkeySettingsDisplayModel.displayString(for: binding.binding))
                            .font(.system(.body, design: .monospaced))
                    }
                }
                SettingsCaption(
                    "Up and Down move within a column first. Press again at the edge to move to the row above or below."
                )
                SettingsCaption(
                    "Widths follow the presets in Layout settings. Windows in one column share their width. App minimum sizes still apply."
                )
                SettingsCaption("Edit individual shortcuts in the configuration file.")
            }
            Section("Defaults") {
                Button("Reset Shortcuts", role: .destructive) {
                    confirmsResetToDefaults = true
                }
            }
        }
        .confirmationDialog("Reset all shortcuts?", isPresented: $confirmsResetToDefaults) {
            Button("Reset Shortcuts", role: .destructive) {
                settings.navigationModifier = .control
                settings.hotkeyKeymap = .arrows
                settings.resetHotkeysToDefaults()
                controller.setHotkeyKeymap(.arrows)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore Control + arrows, window and column movement, width shortcuts, and the command palette.")
        }
    }
}
