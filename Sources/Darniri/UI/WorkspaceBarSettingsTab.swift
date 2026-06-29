import AppKit
import SwiftUI

struct WorkspaceBarSettingsTab: View {
    @Bindable var settings: SettingsStore
    @Bindable var controller: WMController

    var body: some View {
        Form {
            Section("Workspace Bar") {
                Toggle("Enable Workspace Bar", isOn: $settings.workspaceBarEnabled)
                    .onChange(of: settings.workspaceBarEnabled) { _, newValue in
                        controller.setWorkspaceBarEnabled(newValue)
                    }

                if settings.workspaceBarEnabled {
                    Picker("Position", selection: $settings.workspaceBarPosition) {
                        ForEach(WorkspaceBarPosition.allCases) { position in
                            Text(position.displayName).tag(position)
                        }
                    }
                    .onChange(of: settings.workspaceBarPosition) { _, _ in
                        controller.updateWorkspaceBarSettings()
                    }

                    Toggle("Show Workspace Labels", isOn: $settings.workspaceBarShowLabels)
                        .onChange(of: settings.workspaceBarShowLabels) { _, _ in
                            controller.updateWorkspaceBarSettings()
                        }

                    Toggle("Hide Empty Workspaces", isOn: $settings.workspaceBarHideEmptyWorkspaces)
                        .onChange(of: settings.workspaceBarHideEmptyWorkspaces) { _, _ in
                            controller.updateWorkspaceBarSettings()
                        }

                    SettingsSliderRow(
                        label: "Bar Height",
                        value: $settings.workspaceBarHeight,
                        range: 20 ... 40,
                        step: 2,
                        valueText: "\(Int(settings.workspaceBarHeight)) px"
                    )
                    .onChange(of: settings.workspaceBarHeight) { _, _ in
                        controller.updateWorkspaceBarSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
