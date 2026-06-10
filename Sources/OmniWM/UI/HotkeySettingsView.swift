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

enum HotkeyPresetConfirmation: String, Identifiable, Equatable {
    case capsLockModifier

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .capsLockModifier:
            "Apply Caps Lock Modifier?"
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .capsLockModifier:
            "Apply Caps Lock Modifier"
        }
    }

    @MainActor func preview(settings: SettingsStore) -> HotkeyPresetPreview {
        switch self {
        case .capsLockModifier:
            let capsLockHyperTrigger = HyperKeyTrigger.key(UInt32(kVK_CapsLock))
            let plan = HotkeyCenter.registrationPlan(
                for: settings.hotkeyBindings,
                hyperTrigger: capsLockHyperTrigger
            )
            let blockingCommands = plan.failures.compactMap { command, reason in
                reason == HotkeyRegistrationFailureReason.hyperTriggerConflict ? command.displayName : nil
            }
            return HotkeyPresetPreview(
                summary: "Changes the OmniWM modifier to Caps Lock.",
                affectedCommands: [],
                unassignedCommands: [],
                blockingCommands: blockingCommands
            )
        }
    }
}

struct HotkeyPresetPreview: Equatable {
    let summary: String
    let affectedCommands: [String]
    let unassignedCommands: [String]
    let blockingCommands: [String]

    var message: String {
        var sentences = [summary]
        if !affectedCommands.isEmpty {
            sentences.append("Affected commands: \(Self.compactList(affectedCommands)).")
        }
        if !unassignedCommands.isEmpty {
            sentences.append("Will unassign conflicts: \(Self.compactList(unassignedCommands)).")
        }
        if !blockingCommands.isEmpty {
            sentences.append("Clear conflicts first: \(Self.compactList(blockingCommands)).")
        }
        return sentences.joined(separator: " ")
    }

    private static func compactList(_ values: [String], limit: Int = 6) -> String {
        let uniqueValues = values.reduce(into: [String]()) { result, value in
            if !result.contains(value) {
                result.append(value)
            }
        }
        guard uniqueValues.count > limit else {
            return uniqueValues.joined(separator: ", ")
        }
        let shownValues = uniqueValues.prefix(limit).joined(separator: ", ")
        return "\(shownValues), and \(uniqueValues.count - limit) more"
    }
}

enum HotkeySettingsDisplayModel {
    static func isVisible(bindingId: String, showsAdvancedHotkeys: Bool) -> Bool {
        switch ActionCatalog.visibility(for: bindingId) ?? .normal {
        case .normal:
            true
        case .advanced:
            showsAdvancedHotkeys
        case .hidden:
            false
        }
    }

    static func matchesSearch(_ query: String, binding: HotkeyBinding) -> Bool {
        let normalizedQuery = ActionCatalog.normalizedSearchTerm(query)
        guard !normalizedQuery.isEmpty else { return true }
        let actionTerms = ActionCatalog.spec(for: binding.id)?.searchTerms ?? [
            binding.command.displayName,
            binding.command.layoutCompatibility.rawValue
        ]
        let searchTerms = actionTerms + [
            displayString(for: binding.binding),
            humanReadableString(for: binding.binding)
        ]
        return searchTerms.contains {
            ActionCatalog.normalizedSearchTerm($0).contains(normalizedQuery)
        }
    }

    static func displayString(for binding: KeyBinding) -> String {
        if binding.isUnassigned {
            return "Unassigned"
        }
        let prefix = binding.usesHyper ? "OmniWM+" : ""
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
        return binding.usesHyper ? "OmniWM modifier+\(base)" : base
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
    @State private var conflictAlert: ConflictAlert?
    @State private var noticeAlert: HotkeyNoticeAlert?
    @State private var searchText: String = ""
    @State private var showsAdvancedHotkeys = false
    @State private var confirmsResetToDefaults = false
    @State private var pendingPresetConfirmation: HotkeyPresetConfirmation?
    @State private var inputMonitoringStatus = HotkeyInputMonitoringStatus(
        granted: HotkeyCenter.eventTapAccessGranted()
    )

    var body: some View {
        SettingsPage(
            subtitle: "Search commands, edit shortcuts, and review registration problems without leaving the settings window."
        ) {
            Section("Controls") {
                LabeledContent("Advanced") {
                    Toggle("Show Advanced", isOn: $showsAdvancedHotkeys)
                        .toggleStyle(.switch)
                }

                LabeledContent("OmniWM Modifier") {
                    HStack(spacing: 8) {
                        if recordingTarget == .hyperTrigger {
                            HyperTriggerRecorderView(
                                accessibilityLabel: "Recording OmniWM modifier",
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
                            .help("Change OmniWM modifier. Current OmniWM modifier: \(settings.hyperTrigger.humanReadableString)")
                            .accessibilityLabel("Change OmniWM modifier")
                            .accessibilityValue(settings.hyperTrigger.humanReadableString)
                        }
                    }

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
                }

                LabeledContent("Presets") {
                    Menu("Apply Preset") {
                        Button("Caps Lock as OmniWM Modifier") {
                            pendingPresetConfirmation = .capsLockModifier
                        }
                    }
                }

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

            Section("Shortcuts") {
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

                if !hasSearchMatches {
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
                                hyperTrigger: settings.hyperTrigger,
                                failureReason: controller.hotkeyRegistrationFailures[binding.command],
                                onStartChordRecording: startChordRecording,
                                onChordCaptured: handleChordCaptured,
                                onCancelRecording: cancelRecording,
                                onClearBinding: clearBinding,
                                onResetBindings: resetBindings
                            )
                        }
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
        .confirmationDialog(
            pendingPresetConfirmation?.title ?? "Apply preset?",
            isPresented: Binding(
                get: { pendingPresetConfirmation != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingPresetConfirmation = nil
                    }
                }
            )
        ) {
            if let pendingPresetConfirmation {
                Button(pendingPresetConfirmation.confirmButtonTitle, role: .destructive) {
                    applyConfirmedPreset(pendingPresetConfirmation)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingPresetConfirmation = nil
            }
        } message: {
            Text(pendingPresetConfirmation?.preview(settings: settings).message ?? "")
        }
    }

    private var hasSearchMatches: Bool {
        visibleHotkeyBindings.contains {
            HotkeySettingsDisplayModel.matchesSearch(searchText, binding: $0)
        }
    }

    private var visibleHotkeyBindings: [HotkeyBinding] {
        settings.hotkeyBindings.filter(isVisible)
    }

    private func actionsForCategory(_ category: HotkeyCategory) -> [HotkeyBinding] {
        visibleHotkeyBindings.filter { binding in
            binding.category == category && HotkeySettingsDisplayModel.matchesSearch(searchText, binding: binding)
        }
    }

    private func isVisible(_ binding: HotkeyBinding) -> Bool {
        HotkeySettingsDisplayModel.isVisible(
            bindingId: binding.id,
            showsAdvancedHotkeys: showsAdvancedHotkeys
        )
    }

    private var isRecordingOrDrafting: Bool {
        recordingTarget != nil
    }

    private func startChordRecording(for actionId: String) {
        recordingTarget = .chord(actionId)
    }

    private func startHyperTriggerRecording() {
        recordingTarget = .hyperTrigger
    }

    private func handleChordCaptured(actionId: String, newBinding: KeyBinding) {
        handleTriggerCaptured(actionId: actionId, newTrigger: newBinding.isUnassigned ? .unassigned : .chord(newBinding))
    }

    private func handleHyperTriggerCaptured(_ newTrigger: HyperKeyTrigger) {
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

    private func applyConfirmedPreset(_ preset: HotkeyPresetConfirmation) {
        pendingPresetConfirmation = nil
        switch preset {
        case .capsLockModifier:
            applyCapsLockHyperPreset()
        }
    }

    private func applyCapsLockHyperPreset() {
        let eventTapAccessGranted = refreshInputMonitoringStatus(requestIfNeeded: true)
        guard eventTapAccessGranted else {
            noticeAlert = HotkeyNoticeAlert(
                title: "Input Monitoring Required",
                message: "Caps Lock as OmniWM modifier needs Input Monitoring permission. Grant permission, then apply the preset again."
            )
            cancelRecording()
            return
        }

        let capsLockHyperTrigger = HyperKeyTrigger.key(UInt32(kVK_CapsLock))
        let plan = HotkeyCenter.registrationPlan(
            for: settings.hotkeyBindings,
            hyperTrigger: capsLockHyperTrigger
        )
        let conflictingCommands = plan.failures.compactMap { command, reason in
            reason == HotkeyRegistrationFailureReason.hyperTriggerConflict ? command.displayName : nil
        }
        guard conflictingCommands.isEmpty else {
            noticeAlert = HotkeyNoticeAlert(
                title: "Caps Lock Conflict",
                message: "Caps Lock is already used by \(conflictingCommands.joined(separator: ", ")). Clear those hotkeys or choose a different OmniWM modifier before applying this preset."
            )
            cancelRecording()
            return
        }

        settings.applyCapsLockHyperPreset()
        controller.updateHotkeyBindings(settings.hotkeyBindings)
        noticeAlert = HotkeyNoticeAlert(
            title: "Caps Lock OmniWM Modifier Enabled",
            message: "Caps Lock is now OmniWM's local shortcut modifier. OmniWM does not globally remap Caps Lock."
        )
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
    let hyperTrigger: HyperKeyTrigger
    let failureReason: HotkeyRegistrationFailureReason?
    let onStartChordRecording: (String) -> Void
    let onChordCaptured: (String, KeyBinding) -> Void
    let onCancelRecording: () -> Void
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
                    hyperTrigger: hyperTrigger,
                    onStartChordRecording: {
                        onStartChordRecording(binding.id)
                    },
                    onCaptured: { newBinding in
                        onChordCaptured(binding.id, newBinding)
                    },
                    onCancel: {
                        onCancelRecording()
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
            "Shortcut \(HotkeySettingsDisplayModel.humanReadableString(for: binding.binding))",
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
        case .hyperTriggerConflict:
            return "Failed to register: this hotkey uses the same physical key as the configured OmniWM modifier"
        case .unsupportedHyperModifiers:
            return "Failed to register: OmniWM modifier cannot reuse its trigger modifier in the same binding"
        case .eventTapUnavailable:
            return "Failed to register: OmniWM modifier capture is unavailable"
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
    let hyperTrigger: HyperKeyTrigger
    let onStartChordRecording: () -> Void
    let onCaptured: (KeyBinding) -> Void
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
            } else {
                HStack(spacing: 6) {
                    Button {
                        onStartChordRecording()
                    } label: {
                        Text(displayString)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .frame(minWidth: 112, alignment: .center)
                    }
                    .buttonStyle(.bordered)
                    .help("Change hotkey for \(commandName). Current shortcut: \(humanReadableString)")
                    .accessibilityLabel("Change hotkey for \(commandName)")
                    .accessibilityValue(humanReadableString)
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

    private var displayString: String {
        HotkeySettingsDisplayModel.displayString(for: binding)
    }

    private var humanReadableString: String {
        HotkeySettingsDisplayModel.humanReadableString(for: binding)
    }
}
