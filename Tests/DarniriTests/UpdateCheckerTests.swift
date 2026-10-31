@testable import Darniri
import Foundation
import XCTest

final class UpdateCheckerTests: XCTestCase {
    @MainActor
    func testStandaloneExecutableDoesNotRequireNotificationCenter() {
        // SwiftPM runs these tests outside an application bundle, like the
        // executable installed by Homebrew. Initialization must not ask macOS
        // for an app-only notification center or crash.
        XCTAssertNotEqual(Bundle.main.bundleURL.pathExtension, "app")
        let checker = UpdateChecker()
        checker.start()
        XCTAssertFalse(checker.isUpdateAvailable)
        checker.stop()
    }
}
