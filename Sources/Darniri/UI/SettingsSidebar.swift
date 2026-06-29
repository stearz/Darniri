import SwiftUI

struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    var showsMonitors = true

    var body: some View {
        List(selection: $selection) {
            ForEach(SettingsSectionGroup.allCases) { group in
                let sections = group.sections.filter { showsMonitors || $0 != .monitors }
                if !sections.isEmpty {
                    Section(group.rawValue) {
                        ForEach(sections) { section in
                            Label(section.displayName, systemImage: section.icon)
                                .tag(section)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Settings")
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
    }
}
