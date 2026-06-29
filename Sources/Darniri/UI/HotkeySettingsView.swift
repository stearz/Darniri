import SwiftUI

private enum HotkeyRecordingTarget: Equatable {
    case hyperTrigger
}

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
    @State private var recordingTarget: HotkeyRecordingTarget?
    @State private var confirmsResetToDefaults = false
    @State private var inputMonitoringStatus = HotkeyInputMonitoringStatus(
        granted: HotkeyCenter.eventTapAccessGranted()
    )

    var body: some View {
        SettingsPage(
            subtitle: "Configure the Darniri modifier and choose how directional navigation maps to your keyboard."
        ) {
            Section("Controls") {
                LabeledContent("Darniri Modifier") {
                    HStack(spacing: 8) {
                        if recordingTarget == .hyperTrigger {
                            HyperTriggerRecorderView(
                                accessibilityLabel: "Recording Darniri modifier",
                                onCapture: handleHyperTriggerCaptured,
                                onCancel: cancelRecording
                            )
                            .frame(minWidth: 180, idealWidth: 210, minHeight: 34)
                        } else {
                            Button {
                                startHyperTriggerRecording()
                            } label: {
                                Text(settings.hyperTrigger.displayString)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .frame(minWidth: 112, alignment: .center)
                            }
                            .buttonStyle(.bordered)
                            .help("Change Darniri modifier. Current Darniri modifier: \(settings.hyperTrigger.humanReadableString)")
                            .accessibilityLabel("Change Darniri modifier")
                            .accessibilityValue(settings.hyperTrigger.humanReadableString)
                        }
                    }
                }

                LabeledContent("Keymap") {
                    Picker("Keymap", selection: Binding(
                        get: { settings.hotkeyKeymap },
                        set: { controller.setHotkeyKeymap($0) }
                    )) { ForEach(HotkeyKeymap.allCases) { Text($0.displayName).tag($0) } }
                    .labelsHidden().pickerStyle(.segmented).frame(maxWidth: 240)
                }
                SettingsCaption("Arrows uses the arrow keys for focus/move/column navigation; Vim uses h/j/k/l. Rebind individual shortcuts by editing the configuration file.")

                LabeledContent("Hold Threshold") {
                    Stepper(value: $settings.hyperKeyHoldThresholdMilliseconds, in: 0 ... 1500, step: 50) {
                        Text("\(settings.hyperKeyHoldThresholdMilliseconds) ms")
                            .monospacedDigit()
                    }
                    .onChange(of: settings.hyperKeyHoldThresholdMilliseconds) { _, _ in
                        controller.updateHotkeyBindings(settings.hotkeyBindings)
                    }
                }
                SettingsCaption("How long to hold the Hyper key before it activates. 0 ms = immediate (no tap-through to native key).")

                LabeledContent("Input Monitoring") {
                    HStack(spacing: 10) {
                        Text(inputMonitoringStatus.displayText)
                            .foregroundStyle(inputMonitoringStatus == .granted ? Color.secondary : Color.orange)
                        Button("Request Permission") {
                            refreshInputMonitoringStatus(requestIfNeeded: true)
                        }
                    }
                }

                LabeledContent("Defaults") {
                    Button("Reset to Defaults", role: .destructive) {
                        confirmsResetToDefaults = true
                    }
                }
            }
        }
        .onAppear {
            inputMonitoringStatus = HotkeyInputMonitoringStatus(
                granted: HotkeyCenter.eventTapAccessGranted()
            )
        }
        .onChange(of: recordingTarget) { _, _ in
            syncHotkeyRecordingState()
        }
        .onDisappear {
            guard isRecordingOrDrafting else { return }
            cancelRecording()
            controller.setHotkeysEnabled(settings.hotkeysEnabled)
        }
        .confirmationDialog("Reset all hotkeys?", isPresented: $confirmsResetToDefaults) {
            Button("Reset Hotkeys", role: .destructive) {
                settings.resetHotkeysToDefaults()
                // Re-register through the active keymap so a reset under the Vim
                // keymap still yields hjkl (and the active navigation modifier).
                controller.setHotkeyKeymap(settings.hotkeyKeymap)
                cancelRecording()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All hotkey bindings will be restored to Darniri defaults.")
        }
    }

    private var isRecordingOrDrafting: Bool {
        recordingTarget != nil
    }

    private func startHyperTriggerRecording() {
        recordingTarget = .hyperTrigger
    }

    private func handleHyperTriggerCaptured(_ newTrigger: HyperKeyTrigger) {
        settings.hyperTrigger = newTrigger
        controller.updateHotkeyBindings(settings.hotkeyBindings)
        cancelRecording()
    }

    private func cancelRecording() {
        recordingTarget = nil
        syncHotkeyRecordingState()
    }

    @discardableResult
    private func refreshInputMonitoringStatus(requestIfNeeded: Bool) -> Bool {
        let preflightGranted = HotkeyCenter.eventTapAccessGranted()
        let requestGranted: Bool
        if preflightGranted || !requestIfNeeded {
            requestGranted = false
        } else {
            requestGranted = HotkeyCenter.requestEventTapAccess()
        }
        let status = HotkeySettingsDisplayModel.inputMonitoringStatus(
            preflightGranted: preflightGranted,
            requestIfNeeded: requestIfNeeded,
            requestGranted: requestGranted
        )
        inputMonitoringStatus = status
        controller.updateHotkeyBindings(settings.hotkeyBindings, force: true)
        return status == .granted
    }

    private func syncHotkeyRecordingState() {
        controller.setHotkeysEnabled(isRecordingOrDrafting ? false : settings.hotkeysEnabled)
    }
}
