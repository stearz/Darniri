import Carbon
@testable import Darniri
import XCTest

// MARK: - Fake implementation for testing

/// Records all setEnabled calls so tests can assert against the call log.
final class FakeSymbolicHotkeyController: SymbolicHotkeyControlling {
    struct Call: Equatable {
        let id: Int32
        let enabled: Bool
    }

    private(set) var calls: [Call] = []

    func setEnabled(_ id: Int32, _ enabled: Bool) {
        calls.append(Call(id: id, enabled: enabled))
    }

    func reset() {
        calls.removeAll()
    }
}

// MARK: - Tests

@MainActor
final class SymbolicHotkeyControllerTests: XCTestCase {

    // MARK: Managed ID set

    func testManagedIDsContainsExpectedIDs() {
        // Guard against accidental change to the managed set.
        // These IDs correspond to Mission Control, App Exposé, and Move Space shortcuts.
        let expected: Set<Int32> = [32, 33, 34, 35, 79, 80, 81, 82]
        XCTAssertEqual(Set(SymbolicHotkeyManagedIDs.all), expected)
    }

    func testManagedIDsHasEightEntries() {
        XCTAssertEqual(SymbolicHotkeyManagedIDs.all.count, 8)
    }

    // MARK: Restore-to-defaults policy

    func testRestoreReEnablesAllManagedIDs() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .control, impl: fake)

        // Activate (disables IDs), then deactivate (restores = re-enables).
        controller.activate()
        fake.reset()
        controller.deactivate()

        let enableCalls = fake.calls.filter { $0.enabled == true }
        let disableCalls = fake.calls.filter { $0.enabled == false }

        XCTAssertEqual(enableCalls.count, SymbolicHotkeyManagedIDs.all.count,
                       "deactivate() must re-enable all managed IDs")
        XCTAssertTrue(disableCalls.isEmpty,
                      "deactivate() must not disable any IDs")

        let enabledIDs = Set(enableCalls.map { $0.id })
        XCTAssertEqual(enabledIDs, Set(SymbolicHotkeyManagedIDs.all))
    }

    func testRestoreDoesNotUseSnapshotAllIDsAlwaysEnabled() {
        // Phase 0 finding: CGSIsSymbolicHotKeyEnabled is unreliable.
        // Restore must always re-enable (not restore to a captured snapshot).
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .control, impl: fake)

        controller.activate()
        fake.reset()
        controller.deactivate()

        // Every restore call must be setEnabled(id, true).
        for call in fake.calls {
            XCTAssertTrue(call.enabled,
                          "restore must always re-enable ID \(call.id), not conditionally based on a snapshot")
        }
    }

    // MARK: Modifier state machine — Control

    func testControlModifierActivateDisablesAllManagedIDs() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .control, impl: fake)

        controller.activate()

        let disabledIDs = Set(fake.calls.filter { !$0.enabled }.map { $0.id })
        XCTAssertEqual(disabledIDs, Set(SymbolicHotkeyManagedIDs.all),
                       "activate() with Control modifier must disable all managed IDs")
    }

    func testControlModifierActivateDoesNotEnableAnything() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .control, impl: fake)

        controller.activate()

        let enableCalls = fake.calls.filter { $0.enabled }
        XCTAssertTrue(enableCalls.isEmpty,
                      "activate() with Control modifier must not enable any IDs")
    }

    func testControlModifierDeactivateReEnablesAllManagedIDs() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .control, impl: fake)

        controller.activate()
        fake.reset()
        controller.deactivate()

        let enabledIDs = Set(fake.calls.filter { $0.enabled }.map { $0.id })
        XCTAssertEqual(enabledIDs, Set(SymbolicHotkeyManagedIDs.all),
                       "deactivate() must re-enable all managed IDs")
    }

    func testControlModifierActivateIsIdempotent() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .control, impl: fake)

        controller.activate()
        let callsAfterFirst = fake.calls.count
        controller.activate() // second call — should be no-op
        XCTAssertEqual(fake.calls.count, callsAfterFirst,
                       "activate() must be idempotent — second call must not produce new API calls")
    }

    func testControlModifierDeactivateIsIdempotent() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .control, impl: fake)

        controller.activate()
        controller.deactivate()
        let callsAfterFirst = fake.calls.count
        controller.deactivate() // second call — should be no-op
        XCTAssertEqual(fake.calls.count, callsAfterFirst,
                       "deactivate() must be idempotent — second call must not produce new API calls")
    }

    // MARK: Modifier state machine — Option

    func testOptionModifierActivateDoesNotTouchSymbolicHotkeys() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .option, impl: fake)

        controller.activate()

        XCTAssertTrue(fake.calls.isEmpty,
                      "activate() with Option modifier must not touch symbolic hotkeys")
    }

    func testOptionModifierDeactivateDoesNotTouchSymbolicHotkeys() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .option, impl: fake)

        controller.activate()
        controller.deactivate()

        XCTAssertTrue(fake.calls.isEmpty,
                      "deactivate() with Option modifier must not touch symbolic hotkeys")
    }

    // MARK: Modifier switching

    func testSwitchFromControlToOptionWhileActiveRestoresHotkeys() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .control, impl: fake)

        controller.activate()
        fake.reset()

        // Switch to Option — should restore (re-enable) the managed IDs.
        controller.setModifier(.option)

        let enableCalls = fake.calls.filter { $0.enabled }
        XCTAssertEqual(enableCalls.count, SymbolicHotkeyManagedIDs.all.count,
                       "switching to Option while active must restore (re-enable) all managed IDs")
    }

    func testSwitchFromControlToOptionWhileActiveDoesNotReDisable() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .control, impl: fake)

        controller.activate()
        fake.reset()

        controller.setModifier(.option)

        let disableCalls = fake.calls.filter { !$0.enabled }
        XCTAssertTrue(disableCalls.isEmpty,
                      "switching to Option must not issue any disable calls")
    }

    func testSwitchFromOptionToControlWhileActiveDisablesHotkeys() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .option, impl: fake)

        controller.activate() // no-op for option
        fake.reset()

        controller.setModifier(.control)

        let disableCalls = fake.calls.filter { !$0.enabled }
        XCTAssertEqual(disableCalls.count, SymbolicHotkeyManagedIDs.all.count,
                       "switching to Control while active must disable all managed IDs")
    }

    func testSwitchToSameModifierIsNoOp() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .control, impl: fake)

        controller.activate()
        fake.reset()

        controller.setModifier(.control) // same — no change

        XCTAssertTrue(fake.calls.isEmpty,
                      "setModifier to the same value must be a no-op")
    }

    // MARK: Default modifier

    func testDefaultModifierIsControl() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(impl: fake)

        XCTAssertEqual(controller.modifier, .control,
                       "default navigation modifier must be Control")
    }

    // MARK: Keybinding table

    func testFocusLeftRightBoundToControlArrows() throws {
        let leftSpec = try XCTUnwrap(ActionCatalog.spec(for: "focus.left"))
        let rightSpec = try XCTUnwrap(ActionCatalog.spec(for: "focus.right"))

        XCTAssertFalse(leftSpec.defaultBinding.isUnassigned)
        XCTAssertFalse(rightSpec.defaultBinding.isUnassigned)
        XCTAssertEqual(leftSpec.defaultBinding.modifiers, UInt32(controlKey))
        XCTAssertEqual(rightSpec.defaultBinding.modifiers, UInt32(controlKey))
        XCTAssertEqual(leftSpec.defaultBinding.keyCode, UInt32(kVK_LeftArrow))
        XCTAssertEqual(rightSpec.defaultBinding.keyCode, UInt32(kVK_RightArrow))
    }

    func testFocusUpDownUnassigned() throws {
        let upSpec = try XCTUnwrap(ActionCatalog.spec(for: "focus.up"))
        let downSpec = try XCTUnwrap(ActionCatalog.spec(for: "focus.down"))

        XCTAssertTrue(upSpec.defaultBinding.isUnassigned,
                      "focus.up must be unassigned (use focusWindowOrWorkspaceUp for spill)")
        XCTAssertTrue(downSpec.defaultBinding.isUnassigned,
                      "focus.down must be unassigned (use focusWindowOrWorkspaceDown for spill)")
    }

    func testSpillFocusUpDownBoundToControlArrows() throws {
        let upSpec = try XCTUnwrap(ActionCatalog.spec(for: "focusWindowOrWorkspaceUp"))
        let downSpec = try XCTUnwrap(ActionCatalog.spec(for: "focusWindowOrWorkspaceDown"))

        XCTAssertEqual(upSpec.defaultBinding.keyCode, UInt32(kVK_UpArrow))
        XCTAssertEqual(upSpec.defaultBinding.modifiers, UInt32(controlKey))
        XCTAssertEqual(downSpec.defaultBinding.keyCode, UInt32(kVK_DownArrow))
        XCTAssertEqual(downSpec.defaultBinding.modifiers, UInt32(controlKey))
    }

    func testMoveLeftRightBoundToControlShiftArrows() throws {
        let leftSpec = try XCTUnwrap(ActionCatalog.spec(for: "move.left"))
        let rightSpec = try XCTUnwrap(ActionCatalog.spec(for: "move.right"))

        XCTAssertEqual(leftSpec.defaultBinding.modifiers, UInt32(controlKey | shiftKey))
        XCTAssertEqual(leftSpec.defaultBinding.keyCode, UInt32(kVK_LeftArrow))
        XCTAssertEqual(rightSpec.defaultBinding.modifiers, UInt32(controlKey | shiftKey))
        XCTAssertEqual(rightSpec.defaultBinding.keyCode, UInt32(kVK_RightArrow))
    }

    func testMoveUpDownUnassigned() throws {
        let upSpec = try XCTUnwrap(ActionCatalog.spec(for: "move.up"))
        let downSpec = try XCTUnwrap(ActionCatalog.spec(for: "move.down"))

        XCTAssertTrue(upSpec.defaultBinding.isUnassigned,
                      "move.up must be unassigned (use moveWindowUpOrToWorkspaceUp for spill)")
        XCTAssertTrue(downSpec.defaultBinding.isUnassigned,
                      "move.down must be unassigned (use moveWindowDownOrToWorkspaceDown for spill)")
    }

    func testSpillMoveUpDownBoundToControlShiftArrows() throws {
        let upSpec = try XCTUnwrap(ActionCatalog.spec(for: "moveWindowUpOrToWorkspaceUp"))
        let downSpec = try XCTUnwrap(ActionCatalog.spec(for: "moveWindowDownOrToWorkspaceDown"))

        XCTAssertEqual(upSpec.defaultBinding.keyCode, UInt32(kVK_UpArrow))
        XCTAssertEqual(upSpec.defaultBinding.modifiers, UInt32(controlKey | shiftKey))
        XCTAssertEqual(downSpec.defaultBinding.keyCode, UInt32(kVK_DownArrow))
        XCTAssertEqual(downSpec.defaultBinding.modifiers, UInt32(controlKey | shiftKey))
    }

    func testMoveColumnLeftRightBoundToControlAltArrows() throws {
        let leftSpec = try XCTUnwrap(ActionCatalog.spec(for: "moveColumn.left"))
        let rightSpec = try XCTUnwrap(ActionCatalog.spec(for: "moveColumn.right"))

        // ActionCatalog.defaultBinding() strips optionKey and sets usesHyper=true.
        // So Ctrl+Alt+← is stored as {keyCode:←, modifiers:controlKey, usesHyper:true}.
        XCTAssertFalse(leftSpec.defaultBinding.isUnassigned)
        XCTAssertEqual(leftSpec.defaultBinding.keyCode, UInt32(kVK_LeftArrow))
        XCTAssertEqual(leftSpec.defaultBinding.modifiers, UInt32(controlKey))
        XCTAssertTrue(leftSpec.defaultBinding.usesHyper,
                      "moveColumn.left default binding must use hyper (Ctrl+Alt transformed by defaultBinding)")

        XCTAssertFalse(rightSpec.defaultBinding.isUnassigned)
        XCTAssertEqual(rightSpec.defaultBinding.keyCode, UInt32(kVK_RightArrow))
        XCTAssertEqual(rightSpec.defaultBinding.modifiers, UInt32(controlKey))
        XCTAssertTrue(rightSpec.defaultBinding.usesHyper)
    }

    func testMoveColumnToWorkspaceUpDownBoundToControlAltArrows() throws {
        let upSpec = try XCTUnwrap(ActionCatalog.spec(for: "moveColumnToWorkspaceUp"))
        let downSpec = try XCTUnwrap(ActionCatalog.spec(for: "moveColumnToWorkspaceDown"))

        // ActionCatalog.defaultBinding() strips optionKey and sets usesHyper=true.
        // So Ctrl+Alt+↑ is stored as {keyCode:↑, modifiers:controlKey, usesHyper:true}.
        XCTAssertFalse(upSpec.defaultBinding.isUnassigned)
        XCTAssertEqual(upSpec.defaultBinding.keyCode, UInt32(kVK_UpArrow))
        XCTAssertEqual(upSpec.defaultBinding.modifiers, UInt32(controlKey))
        XCTAssertTrue(upSpec.defaultBinding.usesHyper)

        XCTAssertFalse(downSpec.defaultBinding.isUnassigned)
        XCTAssertEqual(downSpec.defaultBinding.keyCode, UInt32(kVK_DownArrow))
        XCTAssertEqual(downSpec.defaultBinding.modifiers, UInt32(controlKey))
        XCTAssertTrue(downSpec.defaultBinding.usesHyper)
    }

    func testNumberedDirectJumpSpecsAbsent() {
        // Numbered jump specs must be removed from the catalog.
        for idx in 0 ..< 9 {
            XCTAssertNil(ActionCatalog.spec(for: "switchWorkspace.\(idx)"),
                         "switchWorkspace.\(idx) must not appear in catalog")
            XCTAssertNil(ActionCatalog.spec(for: "moveToWorkspace.\(idx)"),
                         "moveToWorkspace.\(idx) must not appear in catalog")
            XCTAssertNil(ActionCatalog.spec(for: "moveColumnToWorkspace.\(idx)"),
                         "moveColumnToWorkspace.\(idx) must not appear in catalog")
        }
    }

    func testNoCollisionsBetweenDefaultBindings() {
        // Verify the full default binding set has no duplicate bindings
        // (i.e. registration plan produces no duplicate failures).
        let bindings = ActionCatalog.defaultHotkeyBindings()
        let plan = HotkeyCenter.registrationPlan(for: bindings)

        let duplicates = plan.failures.filter { $0.value == .duplicateBinding }
        XCTAssertTrue(duplicates.isEmpty,
                      "Default bindings must not have any duplicate/colliding chords: \(duplicates)")
    }

    // MARK: - NavigationModifier-aware bindings

    // --- Collision coverage for both modes ---

    func testNoCollisionsBetweenDefaultBindingsControlMode() {
        // .control is the same as the static-init defaults; verify both paths agree.
        let bindings = ActionCatalog.defaultHotkeyBindings(modifier: .control)
        let plan = HotkeyCenter.registrationPlan(for: bindings)
        let duplicates = plan.failures.filter { $0.value == .duplicateBinding }
        XCTAssertTrue(duplicates.isEmpty,
                      "Control-mode bindings must not have any duplicate/colliding chords: \(duplicates)")
    }

    func testNoCollisionsBetweenDefaultBindingsOptionMode() {
        let bindings = ActionCatalog.defaultHotkeyBindings(modifier: .option)
        let plan = HotkeyCenter.registrationPlan(for: bindings)
        let duplicates = plan.failures.filter { $0.value == .duplicateBinding }
        XCTAssertTrue(duplicates.isEmpty,
                      "Option-mode bindings must not have any duplicate/colliding chords: \(duplicates)")
    }

    // --- Control-mode output must be byte-identical to static defaults ---

    func testControlModeBindingsIdenticalToStaticDefaults() {
        let staticDefaults = ActionCatalog.defaultHotkeyBindings()
        let controlDefaults = ActionCatalog.defaultHotkeyBindings(modifier: .control)
        XCTAssertEqual(controlDefaults.count, staticDefaults.count,
                       "Control-mode must produce the same number of bindings as static defaults")
        for (controlBinding, staticBinding) in zip(controlDefaults, staticDefaults) {
            XCTAssertEqual(controlBinding.id, staticBinding.id)
            XCTAssertEqual(controlBinding.binding, staticBinding.binding,
                           "Binding for '\(controlBinding.id)' must be byte-identical in control mode and static defaults")
        }
    }

    // --- Control mode: navigation bindings use plain Carbon (no usesHyper for arrows) ---

    func testControlModeNavigationFocusBindingsUseCarbon() throws {
        let controlDefaults = ActionCatalog.defaultHotkeyBindings(modifier: .control)
        let byID = Dictionary(uniqueKeysWithValues: controlDefaults.map { ($0.id, $0) })

        let focusLeft = try XCTUnwrap(byID["focus.left"])
        let focusRight = try XCTUnwrap(byID["focus.right"])
        let focusUp = try XCTUnwrap(byID["focusWindowOrWorkspaceUp"])
        let focusDown = try XCTUnwrap(byID["focusWindowOrWorkspaceDown"])

        for (id, binding) in [
            ("focus.left", focusLeft.binding),
            ("focus.right", focusRight.binding),
            ("focusWindowOrWorkspaceUp", focusUp.binding),
            ("focusWindowOrWorkspaceDown", focusDown.binding)
        ] {
            guard case let .chord(kb) = binding else {
                XCTFail("\(id) must have a chord binding in control mode"); continue
            }
            XCTAssertFalse(kb.usesHyper,
                           "\(id) must NOT use Hyper in control mode (plain Carbon)")
            XCTAssertEqual(kb.modifiers, UInt32(controlKey),
                           "\(id) must carry controlKey modifier in control mode")
        }
    }

    func testControlModeMoveBindingsUseCarbon() throws {
        let controlDefaults = ActionCatalog.defaultHotkeyBindings(modifier: .control)
        let byID = Dictionary(uniqueKeysWithValues: controlDefaults.map { ($0.id, $0) })

        let moveLeft = try XCTUnwrap(byID["move.left"])
        let moveRight = try XCTUnwrap(byID["move.right"])
        let moveUp = try XCTUnwrap(byID["moveWindowUpOrToWorkspaceUp"])
        let moveDown = try XCTUnwrap(byID["moveWindowDownOrToWorkspaceDown"])

        for (id, binding) in [
            ("move.left", moveLeft.binding),
            ("move.right", moveRight.binding),
            ("moveWindowUpOrToWorkspaceUp", moveUp.binding),
            ("moveWindowDownOrToWorkspaceDown", moveDown.binding)
        ] {
            guard case let .chord(kb) = binding else {
                XCTFail("\(id) must have a chord binding in control mode"); continue
            }
            XCTAssertFalse(kb.usesHyper,
                           "\(id) must NOT use Hyper in control mode (plain Carbon)")
            XCTAssertEqual(kb.modifiers, UInt32(controlKey | shiftKey),
                           "\(id) must carry controlKey|shiftKey in control mode")
        }
    }

    // --- Option mode: navigation bindings must go through Hyper mechanism ---

    func testOptionModeFocusBindingsUseHyper() throws {
        let optionDefaults = ActionCatalog.defaultHotkeyBindings(modifier: .option)
        let byID = Dictionary(uniqueKeysWithValues: optionDefaults.map { ($0.id, $0) })

        let pairs: [(String, UInt32)] = [
            ("focus.left",                     UInt32(kVK_LeftArrow)),
            ("focus.right",                    UInt32(kVK_RightArrow)),
            ("focusWindowOrWorkspaceUp",        UInt32(kVK_UpArrow)),
            ("focusWindowOrWorkspaceDown",      UInt32(kVK_DownArrow))
        ]
        for (id, expectedKeyCode) in pairs {
            let hotkeyBinding = try XCTUnwrap(byID[id], "missing binding for \(id)")
            guard case let .chord(kb) = hotkeyBinding.binding else {
                XCTFail("\(id) must have a chord binding in option mode"); continue
            }
            XCTAssertTrue(kb.usesHyper,
                          "\(id) must use Hyper in option mode (optionKey stripped by defaultBinding())")
            XCTAssertEqual(kb.keyCode, expectedKeyCode,
                           "\(id) must have expected keyCode")
            // After stripping optionKey, modifiers should be 0 for plain Opt+Arrow
            XCTAssertEqual(kb.modifiers, 0,
                           "\(id) should have no residual modifiers after optionKey strip")
        }
    }

    func testOptionModeMoveBindingsUseHyper() throws {
        let optionDefaults = ActionCatalog.defaultHotkeyBindings(modifier: .option)
        let byID = Dictionary(uniqueKeysWithValues: optionDefaults.map { ($0.id, $0) })

        let pairs: [(String, UInt32)] = [
            ("move.left",                            UInt32(kVK_LeftArrow)),
            ("move.right",                           UInt32(kVK_RightArrow)),
            ("moveWindowUpOrToWorkspaceUp",           UInt32(kVK_UpArrow)),
            ("moveWindowDownOrToWorkspaceDown",       UInt32(kVK_DownArrow))
        ]
        for (id, expectedKeyCode) in pairs {
            let hotkeyBinding = try XCTUnwrap(byID[id], "missing binding for \(id)")
            guard case let .chord(kb) = hotkeyBinding.binding else {
                XCTFail("\(id) must have a chord binding in option mode"); continue
            }
            XCTAssertTrue(kb.usesHyper,
                          "\(id) must use Hyper in option mode (optionKey stripped by defaultBinding())")
            XCTAssertEqual(kb.keyCode, expectedKeyCode)
            // After stripping optionKey from Opt+Shift, only shiftKey should remain
            XCTAssertEqual(kb.modifiers, UInt32(shiftKey),
                           "\(id) should have shiftKey remaining after optionKey strip")
        }
    }

    func testOptionModeMoveColumnBindingsUseHyper() throws {
        let optionDefaults = ActionCatalog.defaultHotkeyBindings(modifier: .option)
        let byID = Dictionary(uniqueKeysWithValues: optionDefaults.map { ($0.id, $0) })

        let pairs: [(String, UInt32)] = [
            ("moveColumn.left",          UInt32(kVK_LeftArrow)),
            ("moveColumn.right",         UInt32(kVK_RightArrow)),
            ("moveColumnToWorkspaceUp",   UInt32(kVK_UpArrow)),
            ("moveColumnToWorkspaceDown", UInt32(kVK_DownArrow))
        ]
        for (id, expectedKeyCode) in pairs {
            let hotkeyBinding = try XCTUnwrap(byID[id], "missing binding for \(id)")
            guard case let .chord(kb) = hotkeyBinding.binding else {
                XCTFail("\(id) must have a chord binding in option mode"); continue
            }
            XCTAssertTrue(kb.usesHyper,
                          "\(id) must use Hyper in option mode")
            XCTAssertEqual(kb.keyCode, expectedKeyCode)
            // Raw: Opt+Ctrl+Arrow. After strip: controlKey remains.
            XCTAssertEqual(kb.modifiers, UInt32(controlKey),
                           "\(id) should have controlKey remaining after optionKey strip (was Opt+Ctrl)")
        }
    }

    // --- State machine: .option does NOT disable symbolic hotkeys, .control does ---

    func testOptionModifierDoesNotDisableSymbolicHotkeys() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .option, impl: fake)
        controller.activate()
        XCTAssertTrue(fake.calls.isEmpty,
                      ".option modifier must not issue any symbolic hotkey API calls on activate()")
    }

    func testControlModifierDisablesSymbolicHotkeys() {
        let fake = FakeSymbolicHotkeyController()
        let controller = SymbolicHotkeyController(modifier: .control, impl: fake)
        controller.activate()
        let disableCalls = fake.calls.filter { !$0.enabled }
        XCTAssertEqual(disableCalls.count, SymbolicHotkeyManagedIDs.all.count,
                       ".control modifier must disable all managed symbolic hotkeys on activate()")
    }

    // --- Option bindings in spec catalog use expected key codes ---

    func testOptionModeNavigationKeyCodesMatchExpectedArrows() throws {
        let optionDefaults = ActionCatalog.defaultHotkeyBindings(modifier: .option)
        let byID = Dictionary(uniqueKeysWithValues: optionDefaults.map { ($0.id, $0) })

        func keyCode(for id: String) throws -> UInt32 {
            let b = try XCTUnwrap(byID[id], "missing \(id)")
            guard case let .chord(kb) = b.binding else {
                XCTFail("\(id) has no chord"); return 0
            }
            return kb.keyCode
        }

        XCTAssertEqual(try keyCode(for: "focus.left"),  UInt32(kVK_LeftArrow))
        XCTAssertEqual(try keyCode(for: "focus.right"), UInt32(kVK_RightArrow))
        XCTAssertEqual(try keyCode(for: "focusWindowOrWorkspaceUp"),   UInt32(kVK_UpArrow))
        XCTAssertEqual(try keyCode(for: "focusWindowOrWorkspaceDown"), UInt32(kVK_DownArrow))
        XCTAssertEqual(try keyCode(for: "move.left"),   UInt32(kVK_LeftArrow))
        XCTAssertEqual(try keyCode(for: "move.right"),  UInt32(kVK_RightArrow))
        XCTAssertEqual(try keyCode(for: "moveWindowUpOrToWorkspaceUp"),          UInt32(kVK_UpArrow))
        XCTAssertEqual(try keyCode(for: "moveWindowDownOrToWorkspaceDown"),       UInt32(kVK_DownArrow))
        XCTAssertEqual(try keyCode(for: "moveColumn.left"),          UInt32(kVK_LeftArrow))
        XCTAssertEqual(try keyCode(for: "moveColumn.right"),         UInt32(kVK_RightArrow))
        XCTAssertEqual(try keyCode(for: "moveColumnToWorkspaceUp"),   UInt32(kVK_UpArrow))
        XCTAssertEqual(try keyCode(for: "moveColumnToWorkspaceDown"), UInt32(kVK_DownArrow))
    }

    // --- Non-navigation bindings must be unchanged between modes ---

    func testNonNavigationBindingsUnchangedBetweenModes() {
        let controlDefaults = ActionCatalog.defaultHotkeyBindings(modifier: .control)
        let optionDefaults = ActionCatalog.defaultHotkeyBindings(modifier: .option)

        let controlByID = Dictionary(uniqueKeysWithValues: controlDefaults.map { ($0.id, $0) })
        let optionByID = Dictionary(uniqueKeysWithValues: optionDefaults.map { ($0.id, $0) })

        for id in controlByID.keys where !ActionCatalog.navigationActionIDs.contains(id) {
            XCTAssertEqual(controlByID[id]?.binding, optionByID[id]?.binding,
                           "Non-navigation binding '\(id)' must be identical in both modes")
        }
    }
}
