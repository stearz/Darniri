@testable import Darniri
import Foundation
import ServiceManagement
import XCTest

@MainActor
final class LoginItemManagerTests: XCTestCase {
    @MainActor private final class Fixture {
        let suite = "DarniriLoginTests-\(UUID().uuidString)"
        let defaults: UserDefaults
        var status = SMAppService.Status.notRegistered
        var registerCount = 0
        var unregisterCount = 0
        var registrationFails = false

        init() {
            defaults = UserDefaults(suiteName: suite)!
        }

        func manager(supported: Bool = true) -> LoginItemManager {
            LoginItemManager(
                isSupported: supported,
                defaults: defaults,
                statusProvider: { self.status },
                register: {
                    self.registerCount += 1
                    if self.registrationFails { throw CocoaError(.fileWriteNoPermission) }
                    self.status = .enabled
                },
                unregister: {
                    self.unregisterCount += 1
                    self.status = .notRegistered
                }
            )
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
        }
    }

    func testDefaultRegistersOnceAndDoesNotUndoSystemOptOut() {
        let f = Fixture()
        defer { f.cleanup() }
        f.manager().applyDefaultIfNeeded()
        XCTAssertEqual(f.registerCount, 1)
        f.status = .notRegistered
        f.manager().applyDefaultIfNeeded()
        XCTAssertEqual(f.registerCount, 1)
    }

    func testExplicitOptOutPersistsAcrossAppLaunches() {
        let f = Fixture()
        defer { f.cleanup() }
        let manager = f.manager()
        manager.applyDefaultIfNeeded()
        manager.setEnabled(false)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(f.unregisterCount, 1)
        f.manager().applyDefaultIfNeeded()
        XCTAssertEqual(f.registerCount, 1)
    }

    func testExplicitOptOutBeforeFirstRegistrationIsRespected() {
        let f = Fixture()
        defer { f.cleanup() }
        f.manager().setEnabled(false)
        f.manager().applyDefaultIfNeeded()
        XCTAssertEqual(f.registerCount, 0)
    }

    func testApprovalRequiredIsPreservedAndCanBeDisabled() {
        let f = Fixture()
        defer { f.cleanup() }
        f.status = .requiresApproval
        let manager = f.manager()
        manager.applyDefaultIfNeeded()
        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(manager.status, .requiresApproval)
        XCTAssertEqual(f.registerCount, 0)
        manager.setEnabled(false)
        XCTAssertEqual(f.unregisterCount, 1)
        XCTAssertFalse(manager.isEnabled)
    }

    func testRegistrationFailureReportsErrorAndCanBeRetried() {
        let f = Fixture()
        defer { f.cleanup() }
        f.registrationFails = true
        let manager = f.manager()
        manager.applyDefaultIfNeeded()
        XCTAssertNotNil(manager.errorMessage)
        XCTAssertFalse(manager.isEnabled)
        f.registrationFails = false
        manager.applyDefaultIfNeeded()
        XCTAssertNil(manager.errorMessage)
        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(f.registerCount, 2)
    }

    func testUnsupportedExecutableNeverRegisters() {
        let f = Fixture()
        defer { f.cleanup() }
        let manager = f.manager(supported: false)
        manager.applyDefaultIfNeeded()
        manager.setEnabled(true)
        XCTAssertFalse(manager.isEnabled)
        XCTAssertEqual(manager.status, .notFound)
        XCTAssertEqual(f.registerCount, 0)
    }

    func testOnlyInstalledStableAppReceivesDefaultLoginRegistration() {
        XCTAssertTrue(LoginItemManager.isInstalledApp(URL(fileURLWithPath: "/Applications/Darniri.app")))
        XCTAssertTrue(LoginItemManager.isInstalledApp(URL(fileURLWithPath: "/Users/test/Applications/Darniri.app")))
        XCTAssertFalse(LoginItemManager.isInstalledApp(URL(fileURLWithPath: "/tmp/Darniri.app")))
        XCTAssertFalse(LoginItemManager.isInstalledApp(URL(fileURLWithPath: "/Applications/Darniri-dev.app")))
        XCTAssertFalse(LoginItemManager.isInstalledApp(URL(fileURLWithPath: "/opt/homebrew/bin/Darniri")))
    }
}
