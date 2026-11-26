import Carbon
@testable import Darniri
import XCTest

final class CompactShortcutDefaultsTests: XCTestCase {
    func testDefaultsAreSmallDirectAndConflictFree() {
        let bindings = HotkeyBindingRegistry.defaults()
        XCTAssertEqual(bindings.count, 15)
        XCTAssertFalse(bindings.contains { $0.binding.isUnassigned })
        XCTAssertFalse(bindings.contains { $0.binding.chordBinding?.usesHyper == true })
        XCTAssertFalse(bindings.contains { $0.binding.chordBinding?.keyCode == UInt32(kVK_ANSI_P) })
        let plan = HotkeyCenter.registrationPlan(for: bindings)
        XCTAssertTrue(plan.failures.isEmpty)
        XCTAssertTrue(plan.virtualHyperRegistrations.isEmpty)
        XCTAssertEqual(plan.registrations.count, 15)
        XCTAssertEqual(BuiltInSettingsDefaults.niriColumnWidthPresets, [0.25, 0.5, 0.75, 1])
    }

    func testLegacyConfigurationShrinksToCoreBindings() throws {
        var config = SettingsExport.defaults()
        config.hotkeyBindings = ActionCatalog.legacySpecs().map {
            HotkeyBinding(id: $0.id, command: $0.command, binding: $0.defaultBinding)
        }
        let data = try SettingsTOMLCodec.encode(config)
        let decoded = try SettingsTOMLCodec.decode(data)
        XCTAssertEqual(decoded.hotkeyBindings, HotkeyBindingRegistry.defaults())
        let saved = String(decoding: try SettingsTOMLCodec.encode(decoded), as: UTF8.self)
        XCTAssertFalse(saved.contains("focusDownOrLeft"))
        XCTAssertFalse(saved.contains("Unassigned"))
        let grow = try XCTUnwrap(decoded.hotkeyBindings.first { $0.id == "cycleColumnWidthForward" })
        XCTAssertEqual(grow.binding.chordBinding?.modifiers, UInt32(controlKey))
    }

    func testMigrationKeepsCustomAndDisabledBindings() throws {
        var bindings = ActionCatalog.legacySpecs().map {
            HotkeyBinding(id: $0.id, command: $0.command, binding: $0.defaultBinding)
        }
        let custom = KeyBinding(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(controlKey | cmdKey))
        bindings[try XCTUnwrap(bindings.firstIndex { $0.id == "focusDownOrLeft" })].binding = .chord(custom)
        bindings[try XCTUnwrap(bindings.firstIndex { $0.id == "focus.left" })].binding = .unassigned
        let migrated = HotkeyBindingRegistry.migrateLegacyDefaultWorkspaceBindings(bindings)
        XCTAssertEqual(migrated.count, 16)
        XCTAssertEqual(migrated.first { $0.id == "focusDownOrLeft" }?.binding, .chord(custom))
        XCTAssertEqual(migrated.first { $0.id == "focus.left" }?.binding, .unassigned)
        let persisted = migrated.map { PersistedHotkeyBinding(id: $0.id, trigger: $0.binding) }
        XCTAssertEqual(HotkeyBindingRegistry.canonicalize(persisted).count, 16)
    }
}
