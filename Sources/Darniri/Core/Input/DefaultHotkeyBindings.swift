import Carbon

enum DefaultHotkeyBindings {
    static func all() -> [HotkeyBinding] {
        ActionCatalog.defaultHotkeyBindings()
    }

    static func all(modifier: NavigationModifier) -> [HotkeyBinding] {
        ActionCatalog.defaultHotkeyBindings(modifier: modifier)
    }
}
