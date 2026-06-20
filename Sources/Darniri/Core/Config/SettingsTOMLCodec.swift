import Foundation
import TOML

// Only file in Darniri that imports TOML — keep this boundary so swift-toml stays swappable.
enum SettingsTOMLCodec {
    static func encode(_ export: SettingsExport) throws -> Data {
        let canonical = CanonicalTOMLConfig(export: export)
        let encoder = TOMLEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let body = try encoder.encode(canonical)
        var data = Data(documentationHeader.utf8)
        data.append(body)
        return data
    }

    /// Prepended to every written config file. Documents the schema for the
    /// file-only sections (workspaces, app rules) that no longer have a UI.
    /// Darniri regenerates the file on save, so only this header survives — any
    /// comments added elsewhere in the file are dropped on the next save.
    private static let documentationHeader = """
    # Darniri configuration
    #
    # Managed by Darniri and rewritten whenever you change a setting in the app.
    # You can also edit it by hand — changes are picked up automatically. Only this
    # header is preserved on rewrite; comments added elsewhere are removed on save.
    #
    # ---------------------------------------------------------------------------
    # [[workspaces]] — workspace slots and per-workspace monitor pinning
    # ---------------------------------------------------------------------------
    # One entry per numbered workspace slot. Direct workspace hotkeys cover 1-9;
    # add higher slots here. Only `name` is required; `id` is generated for you
    # if omitted, and everything else is optional.
    #
    #   [[workspaces]]
    #   name = "10"                   # the workspace number / slot (required)
    #   displayName = "Mail"          # optional; shown in status bar and overview
    #
    #   [workspaces.monitorAssignment]
    #   type = "main"                 # "main", "secondary", or "specificDisplay"
    #   # For "specificDisplay", add an `output` table identifying the monitor.
    #
    # ---------------------------------------------------------------------------
    # [[appRules]] — per-app window rules, including pinning apps to a workspace
    # ---------------------------------------------------------------------------
    # Matched by bundle identifier. Only `bundleId` is required; `id` is generated
    # for you if omitted, and every other field is optional.
    #
    #   [[appRules]]
    #   bundleId = "com.apple.MobileSMS"
    #   assignToWorkspace = "3"       # pin this app to workspace slot "3"
    #   layout = "float"              # "auto", "tile", or "float"
    #   minWidth = 660.0              # minimum window size, in points
    #   minHeight = 320.0
    #   # Optional matchers to narrow the rule:
    #   appNameSubstring = "Messages"
    #   titleSubstring = "Inbox"
    #   titleRegex = "^Inbox"
    #   axRole = "AXWindow"
    #   axSubrole = "AXStandardWindow"
    # ---------------------------------------------------------------------------

    """

    static func decode(_ data: Data) throws -> SettingsExport {
        do {
            let canonical = try TOMLDecoder().decode(CanonicalTOMLConfig.self, from: data)
            return canonical.toSettingsExport()
        } catch DecodingError.keyNotFound(_, _) {
            let decoder = TOMLDecoder()
            decoder.userInfo[.settingsTOMLRecoverMissingKeys] = true
            let canonical = try decoder.decode(CanonicalTOMLConfig.self, from: data)
            return canonical.toSettingsExport()
        }
    }
}
