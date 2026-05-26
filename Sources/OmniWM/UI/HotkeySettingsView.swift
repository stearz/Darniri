import Carbon
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
        capture(newBinding.isUnassigned ? .unassigned : .chord(newBinding), for: actionId, settings: settings)
    }

    static func capture(
        _ newTrigger: HotkeyTrigger,
        for actionId: String,
        settings: SettingsStore
    ) -> HotkeyCaptureResult {
        let conflicts = settings.findConflicts(for: newTrigger, excluding: actionId)
        guard conflicts.isEmpty else {
            return .conflict(
                ConflictAlert(
                    targetActionId: actionId,
                    newTrigger: newTrigger,
                    conflictingCommands: conflicts.map(\.command.displayName)
                )
            )
        }

        settings.updateTrigger(for: actionId, newTrigger: newTrigger)
        return .applied
    }

    static func applyConflictResolution(_ alert: ConflictAlert, settings: SettingsStore) {
        let conflicts = settings.findConflicts(for: alert.newTrigger, excluding: alert.targetActionId)
        for conflict in conflicts {
            settings.clearBinding(for: conflict.id)
        }
        settings.updateTrigger(for: alert.targetActionId, newTrigger: alert.newTrigger)
    }
}

private enum HotkeyRecordingTarget: Equatable {
    case chord(String)
    case sequenceStep(String)
    case hyperTrigger
    case leader
}

struct HotkeySettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: WMController
    @State private var recordingTarget: HotkeyRecordingTarget?
    @State private var sequenceDraftActionId: String?
    @State private var sequenceDraftSteps: [HotkeySequenceStep] = []
    @State private var conflictAlert: ConflictAlert?
    @State private var leaderConflictAlert: LeaderConflictAlert?
    @State private var noticeAlert: HotkeyNoticeAlert?
    @State private var searchText: String = ""
    @State private var showsAdvancedHotkeys = false
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

                if showsSequenceControls {
                    LabeledContent("Leader Key") {
                        HStack(spacing: 8) {
                            if recordingTarget == .leader {
                                KeyRecorderView(
                                    accessibilityLabel: "Recording leader key",
                                    hyperTrigger: settings.hyperTrigger,
                                    onCapture: handleLeaderCaptured,
                                    onCancel: cancelRecording
                                )
                                .frame(minWidth: 180, idealWidth: 210, minHeight: 34)
                            } else {
                                Button {
                                    startLeaderRecording()
                                } label: {
                                    Text(settings.effectiveLeaderKey.displayString)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                        .frame(minWidth: 112, alignment: .center)
                                }
                                .buttonStyle(.bordered)
                                .help("Change leader key. Current leader: \(settings.effectiveLeaderKey.humanReadableString)")
                                .accessibilityLabel("Change leader key")
                                .accessibilityValue(settings.effectiveLeaderKey.humanReadableString)
                            }
                        }
                    }

                    LabeledContent("Sequence Timeout") {
                        Stepper(value: $settings.sequenceTimeoutMilliseconds, in: 100 ... 3000, step: 100) {
                            Text("\(settings.sequenceTimeoutMilliseconds) ms")
                                .monospacedDigit()
                        }
                        .onChange(of: settings.sequenceTimeoutMilliseconds) { _, _ in
                            controller.updateHotkeyBindings(settings.hotkeyBindings)
                        }
                    }
                }

                LabeledContent("Hyper Key") {
                    HStack(spacing: 8) {
                        if recordingTarget == .hyperTrigger {
                            HyperTriggerRecorderView(
                                accessibilityLabel: "Recording Hyper key",
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
                            .help("Change Hyper key. Current Hyper key: \(settings.hyperTrigger.humanReadableString)")
                            .accessibilityLabel("Change Hyper key")
                            .accessibilityValue(settings.hyperTrigger.humanReadableString)
                        }
                    }
                }

                LabeledContent("Presets") {
                    Menu("Apply Preset") {
                        Button("Caps Lock as OmniWM Hyper Trigger") {
                            applyCapsLockHyperPreset()
                        }
                        Button("Vim Navigation") {
                            applyVimNavigationPreset()
                        }
                    }
                }

                LabeledContent("Input Monitoring") {
                    Button("Request Permission") {
                        HotkeyCenter.requestSequenceEventAccess()
                        controller.updateHotkeyBindings(settings.hotkeyBindings, force: true)
                    }
                }

                LabeledContent("Defaults") {
                    Button("Reset to Defaults", role: .destructive) {
                        confirmsResetToDefaults = true
                    }
                }

                LabeledContent("Advanced") {
                    Toggle("Show Advanced", isOn: $showsAdvancedHotkeys)
                        .toggleStyle(.switch)
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
                                recordingTarget: $recordingTarget,
                                sequenceDraftActionId: sequenceDraftActionId,
                                sequenceDraftSteps: sequenceDraftSteps,
                                hyperTrigger: settings.hyperTrigger,
                                failureReason: controller.hotkeyRegistrationFailures[binding.command],
                                onStartChordRecording: startChordRecording,
                                onStartSequenceRecording: startSequenceRecording,
                                onChordCaptured: handleChordCaptured,
                                onSequenceStepCaptured: handleSequenceStepCaptured,
                                onAddSequenceStep: addSequenceStep,
                                onApplySequence: applySequenceDraft,
                                onCancelSequence: cancelRecording,
                                onClearBinding: clearBinding,
                                onResetBindings: resetBindings
                            )
                        }
                    }
                }
            }
        }
        .onChange(of: recordingTarget) { _, _ in
            syncHotkeyRecordingState()
        }
        .onDisappear {
            guard isRecordingOrDrafting else { return }
            cancelRecording()
            controller.setHotkeysEnabled(settings.hotkeysEnabled)
        }
        .alert(item: $conflictAlert) { alert in
            Alert(
                title: Text("Hotkey Conflict"),
                message: Text(alert.message),
                primaryButton: .destructive(Text("Replace")) {
                    HotkeyBindingEditor.applyConflictResolution(alert, settings: settings)
                    controller.updateHotkeyBindings(settings.hotkeyBindings)
                    cancelRecording()
                },
                secondaryButton: .cancel {
                    cancelRecording()
                }
            )
        }
        .alert(item: $leaderConflictAlert) { alert in
            Alert(
                title: Text("Leader Key Conflict"),
                message: Text(alert.message),
                primaryButton: .destructive(Text("Replace")) {
                    for actionId in alert.conflictingActionIds {
                        settings.clearBinding(for: actionId)
                    }
                    settings.leaderKey = alert.newLeaderKey
                    controller.updateHotkeyBindings(settings.hotkeyBindings)
                    cancelRecording()
                },
                secondaryButton: .cancel {
                    cancelRecording()
                }
            )
        }
        .alert(item: $noticeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) {
                    cancelRecording()
                }
            )
        }
        .confirmationDialog("Reset all hotkeys?", isPresented: $confirmsResetToDefaults) {
            Button("Reset Hotkeys", role: .destructive) {
                settings.resetHotkeysToDefaults()
                controller.updateHotkeyBindings(settings.hotkeyBindings)
                cancelRecording()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All hotkey bindings will be restored to OmniWM defaults.")
        }
    }

    private var hasSearchMatches: Bool {
        visibleHotkeyBindings.contains {
            ActionCatalog.matchesSearch(searchText, binding: $0)
        }
    }

    private var visibleHotkeyBindings: [HotkeyBinding] {
        settings.hotkeyBindings.filter(isVisible)
    }

    private var showsSequenceControls: Bool {
        showsAdvancedHotkeys || isRecordingOrDrafting || settings.hotkeyBindings.contains { binding in
            guard case .sequence = binding.binding else { return false }
            return true
        }
    }

    private func actionsForCategory(_ category: HotkeyCategory) -> [HotkeyBinding] {
        visibleHotkeyBindings.filter { binding in
            binding.category == category && ActionCatalog.matchesSearch(searchText, binding: binding)
        }
    }

    private func isVisible(_ binding: HotkeyBinding) -> Bool {
        switch ActionCatalog.visibility(for: binding.id) ?? .normal {
        case .normal:
            return true
        case .advanced:
            return showsAdvancedHotkeys
        case .hidden:
            return false
        }
    }

    private var isRecordingOrDrafting: Bool {
        recordingTarget != nil || sequenceDraftActionId != nil
    }

    private func startChordRecording(for actionId: String) {
        sequenceDraftActionId = nil
        sequenceDraftSteps = []
        recordingTarget = .chord(actionId)
    }

    private func startLeaderRecording() {
        sequenceDraftActionId = nil
        sequenceDraftSteps = []
        recordingTarget = .leader
    }

    private func startHyperTriggerRecording() {
        sequenceDraftActionId = nil
        sequenceDraftSteps = []
        recordingTarget = .hyperTrigger
    }

    private func startSequenceRecording(for actionId: String) {
        sequenceDraftActionId = actionId
        sequenceDraftSteps = [.leader]
        recordingTarget = .sequenceStep(actionId)
    }

    private func addSequenceStep(actionId: String) {
        recordingTarget = .sequenceStep(actionId)
    }

    private func handleChordCaptured(actionId: String, newBinding: KeyBinding) {
        handleTriggerCaptured(actionId: actionId, newTrigger: newBinding.isUnassigned ? .unassigned : .chord(newBinding))
    }

    private func handleSequenceStepCaptured(actionId: String, newBinding: KeyBinding) {
        guard sequenceDraftActionId == actionId else { return }
        sequenceDraftSteps.append(.chord(newBinding))
        recordingTarget = nil
        syncHotkeyRecordingState()
    }

    private func applySequenceDraft(actionId: String) {
        guard sequenceDraftActionId == actionId, sequenceDraftSteps.count >= 2 else { return }
        handleTriggerCaptured(actionId: actionId, newTrigger: .sequence(sequenceDraftSteps))
    }

    private func handleLeaderCaptured(_ newBinding: KeyBinding) {
        let resolvedLeader = newBinding.isUnassigned ? KeyBinding.defaultLeader : newBinding
        if settings.leaderKey(resolvedLeader, conflictsWith: settings.hyperTrigger) {
            noticeAlert = HotkeyNoticeAlert(
                title: "Leader Key Conflict",
                message: "The leader key cannot use the same physical key as the configured Hyper key. Use a Hyper chord with a different final key, or choose a different Hyper key."
            )
            cancelRecording()
            return
        }
        let conflicts = settings.findLeaderRootConflicts(for: newBinding)
        guard conflicts.isEmpty else {
            leaderConflictAlert = LeaderConflictAlert(
                newLeaderKey: resolvedLeader,
                conflictingActionIds: conflicts.map(\.id),
                conflictingCommands: conflicts.map(\.command.displayName)
            )
            cancelRecording()
            return
        }
        settings.leaderKey = newBinding
        controller.updateHotkeyBindings(settings.hotkeyBindings)
        cancelRecording()
    }

    private func handleHyperTriggerCaptured(_ newTrigger: HyperKeyTrigger) {
        if settings.leaderKey(settings.effectiveLeaderKey, conflictsWith: newTrigger) {
            noticeAlert = HotkeyNoticeAlert(
                title: "Hyper Key Conflict",
                message: "The Hyper key cannot use the same physical key as the leader key. Keep the leader on a different Hyper chord, or choose a different Hyper key."
            )
            cancelRecording()
            return
        }
        settings.hyperTrigger = newTrigger
        controller.updateHotkeyBindings(settings.hotkeyBindings)
        cancelRecording()
    }

    private func handleTriggerCaptured(actionId: String, newTrigger: HotkeyTrigger) {
        switch HotkeyBindingEditor.capture(newTrigger, for: actionId, settings: settings) {
        case .applied:
            controller.updateHotkeyBindings(settings.hotkeyBindings)
            cancelRecording()
        case let .conflict(alert):
            conflictAlert = alert
            cancelRecording()
        }
    }

    private func clearBinding(actionId: String) {
        settings.clearBinding(for: actionId)
        controller.updateHotkeyBindings(settings.hotkeyBindings)
        cancelRecording()
    }

    private func resetBindings(actionId: String) {
        settings.resetBindings(for: actionId)
        controller.updateHotkeyBindings(settings.hotkeyBindings)
        cancelRecording()
    }

    private func cancelRecording() {
        recordingTarget = nil
        sequenceDraftActionId = nil
        sequenceDraftSteps = []
        syncHotkeyRecordingState()
    }

    private func applyCapsLockHyperPreset() {
        let sequenceAccessGranted = HotkeyCenter.sequenceEventAccessGranted() ||
            HotkeyCenter.requestSequenceEventAccess()
        guard sequenceAccessGranted else {
            noticeAlert = HotkeyNoticeAlert(
                title: "Input Monitoring Required",
                message: "Caps Lock as OmniWM Hyper trigger needs Input Monitoring permission. Grant permission, then apply the preset again."
            )
            cancelRecording()
            return
        }

        let capsLockHyperTrigger = HyperKeyTrigger.key(UInt32(kVK_CapsLock))
        let plan = HotkeyCenter.registrationPlan(
            for: settings.hotkeyBindings,
            hyperTrigger: capsLockHyperTrigger,
            leaderKey: KeyBinding.defaultLeader,
            sequenceEventAccessGranted: true
        )
        let conflictingCommands = plan.failures.compactMap { command, reason in
            reason == HotkeyRegistrationFailureReason.hyperLeaderConflict ? command.displayName : nil
        }
        guard conflictingCommands.isEmpty else {
            noticeAlert = HotkeyNoticeAlert(
                title: "Caps Lock Conflict",
                message: "Caps Lock is already used by \(conflictingCommands.joined(separator: ", ")). Clear those hotkeys or choose a different Hyper key before applying this preset."
            )
            cancelRecording()
            return
        }

        settings.applyCapsLockHyperPreset()
        controller.updateHotkeyBindings(settings.hotkeyBindings)
        noticeAlert = HotkeyNoticeAlert(
            title: "Caps Lock Hyper Trigger Enabled",
            message: "Caps Lock is now OmniWM's local Hyper trigger. OmniWM does not globally remap Caps Lock."
        )
        cancelRecording()
    }

    private func applyVimNavigationPreset() {
        let mappings = HotkeyPreset.vimNavigation()
        let proposedBindings = settings.hotkeyBindings(applyingPreset: mappings)
        let presetCommands = Set(mappings.compactMap { HotkeyBindingRegistry.command(for: $0.id) })
        let sequenceAccessGranted = HotkeyCenter.sequenceEventAccessGranted()
        let plan = HotkeyCenter.registrationPlan(
            for: proposedBindings,
            hyperTrigger: settings.hyperTrigger,
            leaderKey: settings.effectiveLeaderKey,
            sequenceEventAccessGranted: sequenceAccessGranted
        )
        let presetFailures = plan.failures.filter { presetCommands.contains($0.key) }

        guard presetFailures.isEmpty else {
            if presetFailures.values.contains(.inputMonitoringDenied) {
                noticeAlert = HotkeyNoticeAlert(
                    title: "Input Monitoring Required",
                    message: "Vim Navigation uses leader-key sequences, which need Input Monitoring. Grant permission, then apply the preset again."
                )
                HotkeyCenter.requestSequenceEventAccess()
            } else {
                noticeAlert = HotkeyNoticeAlert(
                    title: "Preset Conflict",
                    message: "Vim Navigation cannot be applied with the current Hyper and leader keys. Keep the leader on a different Hyper chord, then try again."
                )
            }
            cancelRecording()
            return
        }

        settings.hotkeyBindings = proposedBindings
        controller.updateHotkeyBindings(settings.hotkeyBindings)
        cancelRecording()
    }

    private func syncHotkeyRecordingState() {
        controller.setHotkeysEnabled(isRecordingOrDrafting ? false : settings.hotkeysEnabled)
    }
}

struct ConflictAlert: Identifiable {
    let targetActionId: String
    let newTrigger: HotkeyTrigger
    let conflictingCommands: [String]

    var id: String {
        [
            targetActionId,
            newTrigger.humanReadableString,
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

struct LeaderConflictAlert: Identifiable {
    let newLeaderKey: KeyBinding
    let conflictingActionIds: [String]
    let conflictingCommands: [String]

    var id: String {
        [
            newLeaderKey.humanReadableString,
            conflictingActionIds.joined(separator: "|")
        ].joined(separator: ":")
    }

    var message: String {
        if conflictingCommands.count == 1 {
            return "This leader key is already used by \"\(conflictingCommands[0])\". Do you want to replace it?"
        } else {
            return "This leader key is used by: \(conflictingCommands.joined(separator: ", ")). Do you want to replace all?"
        }
    }
}

struct HotkeyNoticeAlert: Identifiable {
    let title: String
    let message: String

    var id: String {
        title + ":" + message
    }
}

private struct HotkeyBindingRow: View {
    let binding: HotkeyBinding
    @Binding var recordingTarget: HotkeyRecordingTarget?
    let sequenceDraftActionId: String?
    let sequenceDraftSteps: [HotkeySequenceStep]
    let hyperTrigger: HyperKeyTrigger
    let failureReason: HotkeyRegistrationFailureReason?
    let onStartChordRecording: (String) -> Void
    let onStartSequenceRecording: (String) -> Void
    let onChordCaptured: (String, KeyBinding) -> Void
    let onSequenceStepCaptured: (String, KeyBinding) -> Void
    let onAddSequenceStep: (String) -> Void
    let onApplySequence: (String) -> Void
    let onCancelSequence: () -> Void
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
                    isRecordingChord: recordingTarget == .chord(binding.id),
                    isRecordingSequenceStep: recordingTarget == .sequenceStep(binding.id),
                    sequenceDraftSteps: sequenceDraftActionId == binding.id ? sequenceDraftSteps : nil,
                    hyperTrigger: hyperTrigger,
                    onStartChordRecording: {
                        onStartChordRecording(binding.id)
                    },
                    onStartSequenceRecording: {
                        onStartSequenceRecording(binding.id)
                    },
                    onCaptured: { newBinding in
                        onChordCaptured(binding.id, newBinding)
                    },
                    onSequenceStepCaptured: { newBinding in
                        onSequenceStepCaptured(binding.id, newBinding)
                    },
                    onAddSequenceStep: {
                        onAddSequenceStep(binding.id)
                    },
                    onApplySequence: {
                        onApplySequence(binding.id)
                    },
                    onCancel: {
                        onCancelSequence()
                    },
                    onRemove: {
                        onClearBinding(binding.id)
                    }
                )

                ResetIconButton(title: "Reset \(binding.command.displayName) to default") {
                    recordingTarget = nil
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
        case .duplicateSequence:
            return "Failed to register: this sequence is already assigned to another OmniWM command"
        case .prefixAmbiguity:
            return "Failed to register: this sequence is a prefix of another OmniWM sequence"
        case .invalidSequenceRoot:
            return "Failed to register: sequence roots must use the leader key, modifiers, or a special key"
        case .sequenceRootConflict:
            return "Failed to register: this sequence starts with a key used by another OmniWM command"
        case .hyperLeaderConflict:
            return "Failed to register: this hotkey uses the same physical key as the configured Hyper key"
        case .unsupportedHyperModifiers:
            return "Failed to register: Hyper cannot reuse its trigger modifier in the same binding"
        case .unsupportedSequenceHyperStep:
            return "Failed to register: Hyper can only be used as the first sequence key"
        case .inputMonitoringDenied:
            return "Failed to register: sequence hotkeys require Input Monitoring permission"
        case .eventTapUnavailable:
            return "Failed to register: sequence or Hyper key capture is unavailable"
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
    let binding: HotkeyTrigger
    let commandName: String
    let isRecordingChord: Bool
    let isRecordingSequenceStep: Bool
    let sequenceDraftSteps: [HotkeySequenceStep]?
    let hyperTrigger: HyperKeyTrigger
    let onStartChordRecording: () -> Void
    let onStartSequenceRecording: () -> Void
    let onCaptured: (KeyBinding) -> Void
    let onSequenceStepCaptured: (KeyBinding) -> Void
    let onAddSequenceStep: () -> Void
    let onApplySequence: () -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isRecordingChord {
                KeyRecorderView(
                    accessibilityLabel: "Recording hotkey for \(commandName)",
                    hyperTrigger: hyperTrigger,
                    onCapture: onCaptured,
                    onCancel: onCancel
                )
                .frame(minWidth: 180, idealWidth: 210, minHeight: 34)
                .accessibilityHint("Press Escape to cancel recording")
            } else if let sequenceDraftSteps {
                HStack(spacing: 6) {
                    ForEach(Array(sequenceDraftSteps.enumerated()), id: \.offset) { _, step in
                        Text(step.displayString)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                    }

                    if isRecordingSequenceStep {
                        KeyRecorderView(
                            accessibilityLabel: "Recording sequence key for \(commandName)",
                            allowsBareKeys: true,
                            hyperTrigger: hyperTrigger,
                            onCapture: onSequenceStepCaptured,
                            onCancel: onCancel
                        )
                        .frame(minWidth: 150, idealWidth: 180, minHeight: 34)
                    } else {
                        Button {
                            onAddSequenceStep()
                        } label: {
                            Label("Add sequence key", systemImage: "plus.circle")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .help("Add sequence key")
                        .accessibilityLabel("Add sequence key for \(commandName)")

                        Button("Done") {
                            onApplySequence()
                        }
                        .disabled(sequenceDraftSteps.count < 2)
                    }

                    Button("Cancel", role: .cancel) {
                        onCancel()
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Button {
                        onStartChordRecording()
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

                    Menu {
                        Button("Record Chord") {
                            onStartChordRecording()
                        }
                        Button("Record Sequence") {
                            onStartSequenceRecording()
                        }
                    } label: {
                        Label("Hotkey options for \(commandName)", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Hotkey options")
                    .accessibilityLabel("Hotkey options for \(commandName)")
                }

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
