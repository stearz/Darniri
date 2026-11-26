@testable import Darniri
import XCTest

final class FourFingerSwipeRecognizerTests: XCTestCase {
    private func contacts(_ count: Int = 4, dx: Double = 0, dy: Double = 0) -> [TrackpadContact] {
        (0 ..< count).map { TrackpadContact(id: Int32($0), x: 0.3 + Double($0) * 0.05 + dx, y: 0.4 + dy) }
    }

    func testPhysicalDirectionsIgnoreNaturalScrollPreference() {
        let cases: [(Double, Double, Direction)] = [
            (-0.15, 0, .left), (0.15, 0, .right), (0, 0.15, .up), (0, -0.15, .down)
        ]
        for (dx, dy, direction) in cases {
            var recognizer = FourFingerSwipeRecognizer()
            XCTAssertNil(recognizer.update(contacts: contacts(), timestamp: 0))
            XCTAssertEqual(recognizer.update(contacts: contacts(dx: dx, dy: dy), timestamp: 0.1), direction)
        }
    }

    func testSwipeFiresOnceUntilAllFingersLift() {
        var recognizer = FourFingerSwipeRecognizer()
        _ = recognizer.update(contacts: contacts(), timestamp: 0)
        XCTAssertEqual(recognizer.update(contacts: contacts(dx: 0.15), timestamp: 0.1), .right)
        XCTAssertNil(recognizer.update(contacts: contacts(dx: -0.2), timestamp: 0.2))
        XCTAssertNil(recognizer.update(contacts: contacts(2), timestamp: 0.3))
        XCTAssertNil(recognizer.update(contacts: contacts(), timestamp: 0.4))
        _ = recognizer.update(contacts: [], timestamp: 0.5)
        _ = recognizer.update(contacts: contacts(), timestamp: 0.6)
        XCTAssertEqual(recognizer.update(contacts: contacts(dx: -0.15), timestamp: 0.7), .left)
    }

    func testTwoAndThreeFingerScrollsNeverFire() {
        for count in 1 ... 3 {
            var recognizer = FourFingerSwipeRecognizer()
            _ = recognizer.update(contacts: contacts(count), timestamp: 0)
            XCTAssertNil(recognizer.update(contacts: contacts(count, dx: 0.3), timestamp: 0.1))
        }
    }

    func testStaggeredFingerPlacementBeforeSwipeIsAllowed() {
        var recognizer = FourFingerSwipeRecognizer()
        _ = recognizer.update(contacts: contacts(2), timestamp: 0)
        _ = recognizer.update(contacts: contacts(3), timestamp: 0.01)
        _ = recognizer.update(contacts: contacts(), timestamp: 0.02)
        XCTAssertEqual(recognizer.update(contacts: contacts(dy: 0.2), timestamp: 0.1), .up)
    }

    func testFiveFingerSequenceCannotBecomeFourFingerSwipe() {
        var recognizer = FourFingerSwipeRecognizer()
        _ = recognizer.update(contacts: contacts(5), timestamp: 0)
        _ = recognizer.update(contacts: contacts(), timestamp: 0.1)
        XCTAssertNil(recognizer.update(contacts: contacts(dx: 0.2), timestamp: 0.2))
    }

    func testLiftingOrReplacingFingerCancelsSwipe() {
        for replacement in [contacts(3), contacts().map { TrackpadContact(id: $0.id + 1, x: $0.x, y: $0.y) }] {
            var recognizer = FourFingerSwipeRecognizer()
            _ = recognizer.update(contacts: contacts(), timestamp: 0)
            _ = recognizer.update(contacts: replacement, timestamp: 0.1)
            XCTAssertNil(recognizer.update(contacts: contacts(dx: 0.2), timestamp: 0.2))
        }
    }

    func testSmallMotionAndAmbiguousDiagonalDoNotFire() {
        var recognizer = FourFingerSwipeRecognizer()
        _ = recognizer.update(contacts: contacts(), timestamp: 0)
        XCTAssertNil(recognizer.update(contacts: contacts(dx: 0.05), timestamp: 0.1))
        XCTAssertNil(recognizer.update(contacts: contacts(dx: 0.15, dy: 0.15), timestamp: 0.2))
    }

    func testStationaryFingerPreventsPinchFromBecomingSwipe() {
        var recognizer = FourFingerSwipeRecognizer()
        _ = recognizer.update(contacts: contacts(), timestamp: 0)
        var moved = contacts(dx: 0.2)
        moved[0] = contacts()[0]
        XCTAssertNil(recognizer.update(contacts: moved, timestamp: 0.1))
    }

    func testSuppressionRequiresNewGestureAfterReenable() {
        var recognizer = FourFingerSwipeRecognizer()
        _ = recognizer.update(contacts: contacts(), timestamp: 0)
        _ = recognizer.update(contacts: contacts(dx: 0.05), timestamp: 0.1, isEnabled: false)
        XCTAssertNil(recognizer.update(contacts: contacts(dx: 0.2), timestamp: 0.2))
        _ = recognizer.update(contacts: [], timestamp: 0.3)
        _ = recognizer.update(contacts: contacts(), timestamp: 0.4)
        XCTAssertEqual(recognizer.update(contacts: contacts(dx: 0.2), timestamp: 0.5), .right)
    }

    func testInterruptedStreamCannotFinishOldSwipe() {
        for timestamp in [1.0, -1.0] {
            var recognizer = FourFingerSwipeRecognizer()
            _ = recognizer.update(contacts: contacts(), timestamp: 0)
            XCTAssertNil(recognizer.update(contacts: contacts(dx: 0.2), timestamp: timestamp))
        }
    }

    func testInvalidOrDuplicateContactsCancelSafely() {
        for invalid in [
            Array(repeating: TrackpadContact(id: 1, x: 0.4, y: 0.4), count: 4),
            Array(repeating: TrackpadContact(id: 1, x: .nan, y: 0.4), count: 4)
        ] {
            var recognizer = FourFingerSwipeRecognizer()
            XCTAssertNil(recognizer.update(contacts: invalid, timestamp: 0))
            XCTAssertNil(recognizer.update(contacts: contacts(dx: 0.2), timestamp: 0.1))
        }
    }

    func testCommandsMatchDefaultArrowNavigationIncludingRowSpill() {
        XCTAssertEqual(FourFingerSwipeRecognizer.command(for: .left), .focus(.left))
        XCTAssertEqual(FourFingerSwipeRecognizer.command(for: .right), .focus(.right))
        XCTAssertEqual(FourFingerSwipeRecognizer.command(for: .up), .focusWindowOrWorkspaceUp)
        XCTAssertEqual(FourFingerSwipeRecognizer.command(for: .down), .focusWindowOrWorkspaceDown)
    }
}
