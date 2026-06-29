import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: WMController
    @State private var selectedSection: SettingsSection = .general
    // The Monitors tab is only meaningful with more than one display, so it is
    // hidden on single-monitor setups and revealed live when one is connected.
    @State private var showsMonitors = Monitor.current().count > 1

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(selection: $selectedSection, showsMonitors: showsMonitors)
        } detail: {
            SettingsDetailView(
                section: selectedSection,
                settings: settings,
                controller: controller
            )
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            showsMonitors = Monitor.current().count > 1
            if !showsMonitors, selectedSection == .monitors {
                selectedSection = .general
            }
        }
    }
}

struct GeneralSettingsTab: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: WMController

    private var outerGapsAreUniform: Bool {
        let value = settings.outerGapLeft
        return settings.outerGapRight == value
            && settings.outerGapTop == value
            && settings.outerGapBottom == value
    }

    /// Drives all four outer margins from a single control. Reads the top margin
    /// as the representative value; writing applies the value to every side.
    private var uniformOuterGap: Binding<Double> {
        Binding(
            get: { settings.outerGapTop },
            set: { newValue in
                settings.outerGapLeft = newValue
                settings.outerGapRight = newValue
                settings.outerGapTop = newValue
                settings.outerGapBottom = newValue
                syncOuterGaps()
            }
        )
    }

    var body: some View {
        let animationsEnabled = Binding(
            get: { controller.motionPolicy.animationsEnabled },
            set: { controller.setAnimationsEnabled($0) }
        )

        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: settings.appearanceMode) { _, _ in
                    controller.applyCurrentAppearanceMode()
                }

                SettingsCaption("Controls the appearance of menus and workspace bar")

                Toggle("Enable Animations", isOn: animationsEnabled)
                SettingsCaption("Turns Darniri-authored animations on or off live without relaunching.")
            }

            Section("Layout") {
                SettingsSliderRow(
                    label: "Inner Gaps",
                    value: $settings.gapSize,
                    range: 0 ... 32,
                    step: 1,
                    valueText: "\(Int(settings.gapSize)) px",
                    valueWidth: 64
                )
                .onChange(of: settings.gapSize) { _, newValue in
                    controller.setGapSize(newValue)
                }

                SettingsSliderRow(
                    label: "Outer Margins",
                    value: uniformOuterGap,
                    range: 0 ... 64,
                    step: 1,
                    valueText: outerGapsAreUniform ? "\(Int(settings.outerGapTop)) px" : "Mixed",
                    valueWidth: 64
                )

                SettingsCaption("Applies to all screen edges. Set a different margin per side by editing the configuration file.")
            }

            Section("Mouse Resize") {
                Picker("Right Mouse Resize Modifier", selection: $settings.mouseResizeModifierKey) {
                    ForEach(MouseResizeModifierKey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                }

                SettingsCaption("Hold this modifier combo + right mouse drag to resize tiled windows")
            }

            Section("Advanced") {
                Button("Open Configuration File") {
                    _ = try? SettingsFileWorkflow.perform(.open, settings: settings)
                }

                SettingsCaption("Advanced options not shown here — such as per-side outer margins, per-monitor workspace pinning, and app rules — can be set by editing the configuration file directly. Changes are picked up automatically.")
            }
        }
        .formStyle(.grouped)
    }

    private func syncOuterGaps() {
        controller.setOuterGaps(
            left: settings.outerGapLeft,
            right: settings.outerGapRight,
            top: settings.outerGapTop,
            bottom: settings.outerGapBottom
        )
    }
}

struct NiriSettingsTab: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: WMController

    var body: some View {
        Form {
            Section("Niri Layout") {
                SettingsSliderRow(
                    label: "Visible Columns",
                    value: Binding(
                        get: { Double(settings.niriMaxVisibleColumns) },
                        set: { settings.niriMaxVisibleColumns = Int($0) }
                    ),
                    range: 1 ... 5,
                    step: 1,
                    valueText: "\(settings.niriMaxVisibleColumns)",
                    valueWidth: 32
                )
                .onChange(of: settings.niriMaxVisibleColumns) { _, newValue in
                    controller.updateNiriConfig(maxVisibleColumns: newValue)
                }

                Picker("Center Focused Column", selection: $settings.niriCenterFocusedColumn) {
                    ForEach(CenterFocusedColumn.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .onChange(of: settings.niriCenterFocusedColumn) { _, newValue in
                    controller.updateNiriConfig(centerFocusedColumn: newValue)
                }
            }
        }
        .formStyle(.grouped)
    }
}
