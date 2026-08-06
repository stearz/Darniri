import CoreGraphics
@testable import Darniri
import XCTest

/// Unit coverage for the defensive size-clamping added to `WorkspaceBarGeometry.frame(fittingWidth:monitor:resolved:)`.
/// These cases arise with dynamic rows when the projection is momentarily empty (fittingWidth == 0)
/// or the configured bar height is 0, which would previously produce zero/negative window
/// content sizes and cause AppKit to throw during the hosting-view constraint pass.
final class WorkspaceBarGeometryTests: XCTestCase {

    // MARK: - Fixtures

    private var monitor: Monitor {
        Monitor(
            id: .fallback,
            displayId: CGMainDisplayID(),
            frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1417),
            hasNotch: false,
            name: "Test"
        )
    }

    private func makeResolved(
        height: Double = 32,
        position: WorkspaceBarPosition = .overlappingMenuBar,
        reserveLayoutSpace: Bool = false,
        notchAware: Bool = true,
        xOffset: Double = 0,
        yOffset: Double = 0
    ) -> ResolvedBarSettings {
        ResolvedBarSettings(
            enabled: true,
            showLabels: false,
            showFloatingWindows: false,
            deduplicateAppIcons: false,
            hideEmptyWorkspaces: false,
            reserveLayoutSpace: reserveLayoutSpace,
            notchAware: notchAware,
            position: position,
            windowLevel: .floating,
            height: height,
            backgroundOpacity: 0.1,
            xOffset: xOffset,
            yOffset: yOffset,
            accentColor: nil,
            textColor: nil
        )
    }

    // MARK: - Normal cases

    func testNormalFrameHasPositiveDimensions() {
        let resolved = makeResolved(height: 32)
        let geometry = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: true)
        let frame = geometry.frame(fittingWidth: 400, monitor: monitor, resolved: resolved)

        XCTAssertGreaterThan(frame.width, 0, "Frame width must be positive")
        XCTAssertGreaterThan(frame.height, 0, "Frame height must be positive")
    }

    func testMinimumWidthIsEnforced() {
        let resolved = makeResolved(height: 32)
        let geometry = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: true)
        let frame = geometry.frame(fittingWidth: 100, monitor: monitor, resolved: resolved)

        // Minimum enforced width is 300 by the original code.
        XCTAssertGreaterThanOrEqual(frame.width, 300)
    }

    // MARK: - Degenerate / defensive cases

    func testZeroFittingWidthProducesPositiveWidth() {
        // Occurs when the projection is empty (no workspaces visible).
        let resolved = makeResolved(height: 32)
        let geometry = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: true)
        let frame = geometry.frame(fittingWidth: 0, monitor: monitor, resolved: resolved)

        XCTAssertGreaterThan(frame.width, 0, "Zero fittingWidth must still produce a positive frame width")
        XCTAssertGreaterThan(frame.height, 0)
    }

    func testZeroBarHeightProducesPositiveHeight() {
        // Occurs when resolved.height == 0.
        let resolved = makeResolved(height: 0)
        let geometry = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: true)
        let frame = geometry.frame(fittingWidth: 300, monitor: monitor, resolved: resolved)

        XCTAssertGreaterThan(frame.height, 0, "Zero barHeight must still produce a positive frame height")
        XCTAssertGreaterThan(frame.width, 0)
    }

    func testNaNFittingWidthProducesPositiveDimensions() {
        // Defensive guard against a degenerate SwiftUI measurement result.
        let resolved = makeResolved(height: 32)
        let geometry = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: true)
        let frame = geometry.frame(fittingWidth: .nan, monitor: monitor, resolved: resolved)

        XCTAssert(frame.width.isFinite && frame.width > 0, "NaN fittingWidth must produce a finite positive width")
        XCTAssert(frame.height.isFinite && frame.height > 0, "Frame height must be finite and positive")
    }

    func testBothZeroDimensionsProducePositiveFrame() {
        // Worst-case: both fittingWidth and barHeight are zero.
        let resolved = makeResolved(height: 0)
        let geometry = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: true)
        let frame = geometry.frame(fittingWidth: 0, monitor: monitor, resolved: resolved)

        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
    }

    // MARK: - Position

    func testBelowMenuBarPositionPlacesFrameCorrectly() {
        let resolved = makeResolved(height: 32, position: .belowMenuBar)
        let geometry = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: true)
        let frame = geometry.frame(fittingWidth: 400, monitor: monitor, resolved: resolved)

        // For belowMenuBar, y should be at the top of the visible frame minus barHeight.
        let expectedY = monitor.visibleFrame.maxY - frame.height
        XCTAssertEqual(frame.origin.y, expectedY, accuracy: 0.5)
    }

    // MARK: - Reserved layout space

    /// A left-docked bar must reserve space on the *left* edge. Reserving on the top
    /// (the old behaviour) left windows spanning the full width, so the panel covered
    /// their traffic-light buttons and swallowed clicks at the screen edge.
    func testLeftBarReservesSpaceOnLeftEdge() {
        let resolved = makeResolved(height: 40, position: .left, reserveLayoutSpace: true)
        let insets = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: true).reservedInsets

        XCTAssertEqual(insets.left, 40, accuracy: 0.5)
        XCTAssertEqual(insets.top, 0)
        XCTAssertEqual(insets.right, 0)
    }

    func testRightBarReservesSpaceOnRightEdge() {
        let resolved = makeResolved(height: 40, position: .right, reserveLayoutSpace: true)
        let insets = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: true).reservedInsets

        XCTAssertEqual(insets.right, 40, accuracy: 0.5)
        XCTAssertEqual(insets.top, 0)
        XCTAssertEqual(insets.left, 0)
    }

    /// The reserved strut must match the panel's real on-screen width, which is clamped
    /// to a minimum. Otherwise a small configured height under-reserves and the panel
    /// still overlaps windows.
    func testVerticalReservationMatchesClampedPanelWidth() {
        let resolved = makeResolved(height: 10, position: .left, reserveLayoutSpace: true)
        let geometry = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: true)
        let frame = geometry.frame(fittingWidth: 200, monitor: monitor, resolved: resolved)

        XCTAssertEqual(geometry.reservedInsets.left, frame.width, accuracy: 0.5)
        XCTAssertEqual(frame.width, WorkspaceBarGeometry.minimumVerticalPanelWidth, accuracy: 0.5)
    }

    /// `overlappingMenuBar` draws inside the menu-bar strip, which is already outside the
    /// visible frame, so it must not shrink the window layout.
    func testOverlappingMenuBarReservesNothing() {
        let resolved = makeResolved(height: 24, position: .overlappingMenuBar, reserveLayoutSpace: true)
        let insets = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: true).reservedInsets

        XCTAssertEqual(insets, .zero)
    }

    func testBelowMenuBarReservesTopInset() {
        let resolved = makeResolved(height: 24, position: .belowMenuBar, reserveLayoutSpace: true)
        let insets = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: true).reservedInsets

        XCTAssertEqual(insets.top, 24, accuracy: 0.5)
        XCTAssertEqual(insets.left, 0)
        XCTAssertEqual(insets.right, 0)
    }

    func testHiddenBarReservesNothing() {
        let resolved = makeResolved(height: 40, position: .left, reserveLayoutSpace: true)
        let insets = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: false).reservedInsets

        XCTAssertEqual(insets, .zero)
    }

    func testReserveDisabledReservesNothing() {
        let resolved = makeResolved(height: 40, position: .left, reserveLayoutSpace: false)
        let insets = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: true).reservedInsets

        XCTAssertEqual(insets, .zero)
    }

    func testOverlappingMenuBarPositionPlacesFrameAboveVisibleArea() {
        let resolved = makeResolved(height: 32, position: .overlappingMenuBar)
        let geometry = WorkspaceBarGeometry.resolve(monitor: monitor, resolved: resolved, isVisible: true)
        let frame = geometry.frame(fittingWidth: 400, monitor: monitor, resolved: resolved)

        // For overlappingMenuBar, y == visibleFrame.maxY (within the menu bar inset area).
        XCTAssertEqual(frame.origin.y, monitor.visibleFrame.maxY, accuracy: 0.5)
    }
}
