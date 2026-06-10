import Carbon
@testable import OmniWM
import XCTest

final class HotkeyChordTests: XCTestCase {
    func testHotkeyTriggerRejectsSequenceText() {
        XCTAssertNil(HotkeyTrigger.fromHumanReadable("Option+A, B"))
        XCTAssertNil(HotkeyTrigger.fromHumanReadable("Leader, A"))
    }

    func testHotkeyTriggerRoundTripsChordEncoding() throws {
        let trigger = HotkeyTrigger.chord(KeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey)))
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(HotkeyTrigger.self, from: data)

        XCTAssertEqual(decoded, trigger)
    }

    func testChordConflictDetectionUsesOnlyChordBindings() {
        let lhs = HotkeyTrigger.chord(KeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey)))
        let same = HotkeyTrigger.chord(KeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey)))
        let different = HotkeyTrigger.chord(KeyBinding(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(optionKey)))

        XCTAssertTrue(lhs.conflicts(with: same, hyperTrigger: .default))
        XCTAssertFalse(lhs.conflicts(with: different, hyperTrigger: .default))
        XCTAssertFalse(lhs.conflicts(with: .unassigned, hyperTrigger: .default))
    }

    func testRegistrationPlanMarksDuplicateChordBindings() {
        let binding = KeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey))
        let bindings = [
            HotkeyBinding(id: "focus.left", command: .focus(.left), binding: binding),
            HotkeyBinding(id: "focus.right", command: .focus(.right), binding: binding)
        ]

        let plan = HotkeyCenter.registrationPlan(for: bindings)

        XCTAssertEqual(plan.failures[.focus(.left)], .duplicateBinding)
        XCTAssertEqual(plan.failures[.focus(.right)], .duplicateBinding)
        XCTAssertTrue(plan.registrations.isEmpty)
        XCTAssertTrue(plan.virtualHyperRegistrations.isEmpty)
    }

    func testRegistrationPlanMarksPhysicalHyperTriggerConflict() {
        let binding = KeyBinding(keyCode: UInt32(kVK_CapsLock), modifiers: 0)
        let bindings = [
            HotkeyBinding(id: "focus.left", command: .focus(.left), binding: binding)
        ]

        let plan = HotkeyCenter.registrationPlan(
            for: bindings,
            hyperTrigger: .key(UInt32(kVK_CapsLock))
        )

        XCTAssertEqual(plan.failures[.focus(.left)], .hyperTriggerConflict)
        XCTAssertTrue(plan.registrations.isEmpty)
        XCTAssertTrue(plan.virtualHyperRegistrations.isEmpty)
    }

    func testRegistrationPlanProducesDirectAndVirtualHyperRegistrations() {
        let directBinding = KeyBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(optionKey))
        let hyperBinding = KeyBinding(keyCode: UInt32(kVK_ANSI_B), modifiers: 0, usesHyper: true)
        let bindings = [
            HotkeyBinding(id: "focus.left", command: .focus(.left), binding: directBinding),
            HotkeyBinding(id: "focus.right", command: .focus(.right), binding: hyperBinding)
        ]

        let plan = HotkeyCenter.registrationPlan(
            for: bindings,
            hyperTrigger: .key(UInt32(kVK_CapsLock))
        )

        XCTAssertEqual(
            plan.registrations,
            [HotkeyPlannedRegistration(binding: directBinding, command: .focus(.left))]
        )
        XCTAssertEqual(
            plan.virtualHyperRegistrations,
            [HotkeyPlannedRegistration(binding: hyperBinding, command: .focus(.right))]
        )
        XCTAssertTrue(plan.failures.isEmpty)
    }

    func testSettingsTOMLDoesNotEmitLeaderOrSequenceTimeout() throws {
        let data = try SettingsTOMLCodec.encode(.defaults())
        let toml = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(toml.contains("leaderKey"))
        XCTAssertFalse(toml.contains("sequenceTimeoutMilliseconds"))
    }
}
