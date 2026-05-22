import SwiftUI

enum HotkeyCaptureResult {
    case applied
    case conflict(ConflictAlert)
}

@MainActor enum HotkeyBindingEditor {
    static func capture(
        _ newBinding: KeyBinding,
        for actionId: String,
        settings: SettingsStore
    ) -> HotkeyCaptureResult {
        let conflicts = settings.findConflicts(for: newBinding, excluding: actionId)
        guard conflicts.isEmpty else {
            return .conflict(
                ConflictAlert(
                    targetActionId: actionId,
                    newBinding: newBinding,
                    conflictingCommands: conflicts.map(\.command.displayName)
                )
            )
        }

        settings.updateBinding(for: actionId, newBinding: newBinding)
        return .applied
    }

    static func applyConflictResolution(_ alert: ConflictAlert, settings: SettingsStore) {
        let conflicts = settings.findConflicts(for: alert.newBinding, excluding: alert.targetActionId)
        for conflict in conflicts {
            settings.clearBinding(for: conflict.id)
        }
        settings.updateBinding(for: alert.targetActionId, newBinding: alert.newBinding)
    }
}

struct HotkeySettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: WMController
    @State private var recordingActionId: String?
    @State private var conflictAlert: ConflictAlert?
    @State private var searchText: String = ""
    @State private var confirmsResetToDefaults = false

    var body: some View {
        SettingsPage(
            subtitle: "Search commands, edit shortcuts, and review registration problems without leaving the settings window."
        ) {
            Section("Controls") {
                LabeledContent("Search") {
                    HStack(spacing: 8) {
                        TextField("Command, shortcut, or scope", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Search hotkeys")

                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Label("Clear search", systemImage: "xmark.circle.fill")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .help("Clear search")
                            .accessibilityLabel("Clear hotkey search")
                        }
                    }
                }

                LabeledContent("Defaults") {
                    Button("Reset to Defaults", role: .destructive) {
                        confirmsResetToDefaults = true
                    }
                }
            }

            if !hasSearchMatches {
                Section("Shortcuts") {
                    Text("No matching hotkeys.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(HotkeyCategory.allCases, id: \.self) { category in
                let actions = actionsForCategory(category)
                if !actions.isEmpty {
                    Section(category.rawValue) {
                        ForEach(actions) { binding in
                            HotkeyBindingRow(
                                binding: binding,
                                recordingActionId: $recordingActionId,
                                failureReason: controller.hotkeyRegistrationFailures[binding.command],
                                onStartRecording: startRecording,
                                onBindingCaptured: handleBindingCaptured,
                                onClearBinding: clearBinding,
                                onResetBindings: resetBindings
                            )
                        }
                    }
                }
            }
        }
        .onChange(of: recordingActionId) { _, newValue in
            syncHotkeyRecordingState(newValue)
        }
        .onDisappear {
            guard recordingActionId != nil else { return }
            controller.setHotkeysEnabled(settings.hotkeysEnabled)
        }
        .alert(item: $conflictAlert) { alert in
            Alert(
                title: Text("Hotkey Conflict"),
                message: Text(alert.message),
                primaryButton: .destructive(Text("Replace")) {
                    HotkeyBindingEditor.applyConflictResolution(alert, settings: settings)
                    controller.updateHotkeyBindings(settings.hotkeyBindings)
                    recordingActionId = nil
                },
                secondaryButton: .cancel {
                    recordingActionId = nil
                }
            )
        }
        .confirmationDialog("Reset all hotkeys?", isPresented: $confirmsResetToDefaults) {
            Button("Reset Hotkeys", role: .destructive) {
                settings.resetHotkeysToDefaults()
                controller.updateHotkeyBindings(settings.hotkeyBindings)
                recordingActionId = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All hotkey bindings will be restored to OmniWM defaults.")
        }
    }

    private var hasSearchMatches: Bool {
        settings.hotkeyBindings.contains {
            ActionCatalog.matchesSearch(searchText, binding: $0)
        }
    }

    private func actionsForCategory(_ category: HotkeyCategory) -> [HotkeyBinding] {
        settings.hotkeyBindings.filter { binding in
            binding.category == category && ActionCatalog.matchesSearch(searchText, binding: binding)
        }
    }

    private func startRecording(for actionId: String) {
        recordingActionId = actionId
    }

    private func handleBindingCaptured(actionId: String, newBinding: KeyBinding) {
        switch HotkeyBindingEditor.capture(newBinding, for: actionId, settings: settings) {
        case .applied:
            controller.updateHotkeyBindings(settings.hotkeyBindings)
            recordingActionId = nil
        case let .conflict(alert):
            conflictAlert = alert
            recordingActionId = nil
        }
    }

    private func clearBinding(actionId: String) {
        settings.clearBinding(for: actionId)
        controller.updateHotkeyBindings(settings.hotkeyBindings)
        recordingActionId = nil
    }

    private func resetBindings(actionId: String) {
        settings.resetBindings(for: actionId)
        controller.updateHotkeyBindings(settings.hotkeyBindings)
        recordingActionId = nil
    }

    private func syncHotkeyRecordingState(_ actionId: String?) {
        controller.setHotkeysEnabled(actionId == nil ? settings.hotkeysEnabled : false)
    }
}

struct ConflictAlert: Identifiable {
    let targetActionId: String
    let newBinding: KeyBinding
    let conflictingCommands: [String]

    var id: String {
        [
            targetActionId,
            String(newBinding.keyCode),
            String(newBinding.modifiers),
            conflictingCommands.joined(separator: "|")
        ].joined(separator: ":")
    }

    var message: String {
        if conflictingCommands.count == 1 {
            return "This key combination is already used by \"\(conflictingCommands[0])\". Do you want to replace it?"
        } else {
            let commandList = conflictingCommands.joined(separator: ", ")
            return "This key combination is used by: \(commandList). Do you want to replace all?"
        }
    }
}

struct HotkeyBindingRow: View {
    let binding: HotkeyBinding
    @Binding var recordingActionId: String?
    let failureReason: HotkeyRegistrationFailureReason?
    let onStartRecording: (String) -> Void
    let onBindingCaptured: (String, KeyBinding) -> Void
    let onClearBinding: (String) -> Void
    let onResetBindings: (String) -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if let failureReason {
                    Label("Registration issue", systemImage: "exclamationmark.triangle.fill")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.orange)
                        .help(failureMessage(for: failureReason))
                        .accessibilityLabel("Registration issue")
                        .accessibilityValue(failureMessage(for: failureReason))
                }

                HotkeyBindingControl(
                    binding: binding.binding,
                    commandName: binding.command.displayName,
                    isRecording: recordingActionId == binding.id,
                    onStartRecording: {
                        onStartRecording(binding.id)
                    },
                    onCaptured: { newBinding in
                        onBindingCaptured(binding.id, newBinding)
                    },
                    onCancel: {
                        recordingActionId = nil
                    },
                    onRemove: {
                        onClearBinding(binding.id)
                    }
                )

                ResetIconButton(title: "Reset \(binding.command.displayName) to default") {
                    recordingActionId = nil
                    onResetBindings(binding.id)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(binding.command.displayName)
                    .font(.body)

                HStack(spacing: 6) {
                    HotkeyScopeText(compatibility: binding.command.layoutCompatibility)

                    if let failureReason {
                        Text(failureMessage(for: failureReason))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts = [
            "Shortcut \(binding.binding.humanReadableString)",
            "Scope \(binding.command.layoutCompatibility.rawValue)"
        ]
        if let failureReason {
            parts.append(failureMessage(for: failureReason))
        }
        return parts.joined(separator: ", ")
    }

    private func failureMessage(for reason: HotkeyRegistrationFailureReason) -> String {
        switch reason {
        case .duplicateBinding:
            return "Failed to register: this key combination is already assigned to another OmniWM command"
        case .systemReserved:
            return "Failed to register: this key combination may be reserved by the system"
        }
    }
}

private struct HotkeyScopeText: View {
    let compatibility: LayoutCompatibility

    var body: some View {
        Text("Scope: \(compatibility.rawValue)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.10), in: Capsule())
    }
}

private struct HotkeyBindingControl: View {
    let binding: KeyBinding
    let commandName: String
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onCaptured: (KeyBinding) -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isRecording {
                KeyRecorderView(
                    accessibilityLabel: "Recording hotkey for \(commandName)",
                    onCapture: onCaptured,
                    onCancel: onCancel
                )
                .frame(minWidth: 180, idealWidth: 210, minHeight: 34)
                .accessibilityHint("Press Escape to cancel recording")
            } else {
                Button {
                    onStartRecording()
                } label: {
                    Text(binding.displayString)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .frame(minWidth: 112, alignment: .center)
                }
                .buttonStyle(.bordered)
                .help("Change hotkey for \(commandName). Current shortcut: \(binding.humanReadableString)")
                .accessibilityLabel("Change hotkey for \(commandName)")
                .accessibilityValue(binding.humanReadableString)

                if !binding.isUnassigned {
                    Button {
                        onRemove()
                    } label: {
                        Label("Clear hotkey for \(commandName)", systemImage: "xmark.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear this hotkey")
                    .accessibilityLabel("Clear hotkey for \(commandName)")
                }
            }
        }
    }
}
