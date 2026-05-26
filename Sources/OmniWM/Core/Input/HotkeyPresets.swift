import Carbon

enum HotkeyPreset {
    static func vimNavigation() -> [(id: String, trigger: HotkeyTrigger)] {
        let directionKeys: [(String, UInt32)] = [
            ("left", UInt32(kVK_ANSI_H)),
            ("down", UInt32(kVK_ANSI_J)),
            ("up", UInt32(kVK_ANSI_K)),
            ("right", UInt32(kVK_ANSI_L))
        ]
        var mappings: [(id: String, trigger: HotkeyTrigger)] = directionKeys.flatMap { direction, keyCode in
            [
                (
                    id: "focus.\(direction)",
                    trigger: HotkeyTrigger.sequence([.leader, .chord(KeyBinding(keyCode: keyCode, modifiers: 0))])
                ),
                (
                    id: "move.\(direction)",
                    trigger: HotkeyTrigger.sequence([
                        .leader,
                        .chord(KeyBinding(keyCode: keyCode, modifiers: UInt32(shiftKey)))
                    ])
                )
            ]
        }
        let digitCodes = [
            UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
            UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9)
        ]
        for (index, keyCode) in digitCodes.enumerated() {
            mappings.append(
                (
                    id: "switchWorkspace.\(index)",
                    trigger: .sequence([.leader, .chord(KeyBinding(keyCode: keyCode, modifiers: 0))])
                )
            )
            mappings.append(
                (
                    id: "moveToWorkspace.\(index)",
                    trigger: .sequence([
                        .leader,
                        .chord(KeyBinding(keyCode: keyCode, modifiers: UInt32(shiftKey)))
                    ])
                )
            )
        }
        mappings.append(
            (
                id: "focusPrevious",
                trigger: .sequence([.leader, .chord(KeyBinding(keyCode: UInt32(kVK_Tab), modifiers: 0))])
            )
        )
        return mappings
    }
}
