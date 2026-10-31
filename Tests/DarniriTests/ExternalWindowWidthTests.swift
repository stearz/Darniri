@testable import Darniri
import XCTest

@MainActor
final class ExternalWindowWidthTests: XCTestCase {
    private let workspaceId = WorkspaceDescriptor.ID()
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    private func layout(_ engine: NiriLayoutEngine) -> [WindowToken: CGRect] {
        engine.calculateLayout(
            state: ViewportState(),
            workspaceId: workspaceId,
            monitorFrame: screen,
            gaps: (horizontal: 12, vertical: 12)
        )
    }

    func testExternalWidthSurvivesRelayoutAndMovesNeighbor() throws {
        let engine = NiriLayoutEngine()
        let first = engine.addWindow(token: WindowToken(pid: 1, windowId: 1), to: workspaceId, afterSelection: nil)
        let second = engine.addWindow(token: WindowToken(pid: 1, windowId: 2), to: workspaceId, afterSelection: nil)
        _ = layout(engine)

        for width: CGFloat in [900, 400, 750] {
            XCTAssertTrue(engine.adoptWindowWidth(width, for: first, in: workspaceId))
            XCTAssertFalse(engine.adoptWindowWidth(width, for: first, in: workspaceId))
            let frames = layout(engine)
            let firstFrame = try XCTUnwrap(frames[first.token])
            let secondFrame = try XCTUnwrap(frames[second.token])
            XCTAssertEqual(firstFrame.width, width, accuracy: 0.5)
            XCTAssertEqual(secondFrame.minX - firstFrame.maxX, 12, accuracy: 0.5)
            XCTAssertEqual(layout(engine)[first.token]?.width, width)
        }
    }

    func testStackedWindowsShareExternallyChangedWidth() throws {
        let engine = NiriLayoutEngine()
        let first = engine.addWindow(token: WindowToken(pid: 1, windowId: 1), to: workspaceId, afterSelection: nil)
        let column = try XCTUnwrap(engine.findColumn(containing: first, in: workspaceId))
        let stacked = NiriWindow(token: WindowToken(pid: 1, windowId: 2))
        column.appendChild(stacked)
        _ = layout(engine)

        XCTAssertTrue(engine.adoptWindowWidth(800, for: first, in: workspaceId))
        let frames = layout(engine)
        XCTAssertEqual(frames[first.token]?.width, 800)
        XCTAssertEqual(frames[stacked.token]?.width, 800)
    }

    func testTabbedColumnIncludesIndicatorInExternalWidth() throws {
        let engine = NiriLayoutEngine()
        engine.renderStyle.tabIndicatorWidth = 24
        let first = engine.addWindow(token: WindowToken(pid: 1, windowId: 1), to: workspaceId, afterSelection: nil)
        let column = try XCTUnwrap(engine.findColumn(containing: first, in: workspaceId))
        column.displayMode = .tabbed
        _ = layout(engine)

        XCTAssertTrue(engine.adoptWindowWidth(800, for: first, in: workspaceId))
        XCTAssertEqual(column.cachedWidth, 824)
        XCTAssertEqual(layout(engine)[first.token]?.width, 800)
    }

    func testLoneWindowAcceptsExternalWidthBeyondDisplayAndBypassesAspectRatio() throws {
        let engine = NiriLayoutEngine()
        engine.singleWindowAspectRatio = .square
        let first = engine.addWindow(token: WindowToken(pid: 1, windowId: 1), to: workspaceId, afterSelection: nil)
        _ = layout(engine)

        for width: CGFloat in [500, 1600] {
            XCTAssertTrue(engine.adoptWindowWidth(width, for: first, in: workspaceId))
            let frame = try XCTUnwrap(layout(engine)[first.token])
            XCTAssertEqual(frame.width, width)
            XCTAssertEqual(frame.midX, screen.midX)
            XCTAssertEqual(frame.height, screen.height)
        }
    }

    func testExternalWidthRejectsInvalidValuesAndDoesNotChangeHeightOrFullscreen() throws {
        let engine = NiriLayoutEngine()
        let first = engine.addWindow(token: WindowToken(pid: 1, windowId: 1), to: workspaceId, afterSelection: nil)
        let initialFrame = try XCTUnwrap(layout(engine)[first.token])
        for width: CGFloat in [.nan, .infinity, 0, -1, initialFrame.width + 0.5] {
            XCTAssertFalse(engine.adoptWindowWidth(width, for: first, in: workspaceId))
        }
        first.sizingMode = .fullscreen
        XCTAssertFalse(engine.adoptWindowWidth(800, for: first, in: workspaceId))
        first.sizingMode = .normal
        XCTAssertTrue(engine.adoptWindowWidth(800, for: first, in: workspaceId))
        XCTAssertEqual(layout(engine)[first.token]?.height, initialFrame.height)
    }
}
