import CoreGraphics

struct WorkspaceBarGeometry: Equatable {
    let effectivePosition: WorkspaceBarPosition
    let menuBarHeight: CGFloat
    let barHeight: CGFloat
    let reservedTopInset: CGFloat

    static func resolve(
        monitor: Monitor,
        resolved: ResolvedBarSettings,
        isVisible: Bool,
        menuBarHeight: CGFloat? = nil
    ) -> WorkspaceBarGeometry {
        let resolvedMenuBarHeight = menuBarHeight ?? self.menuBarHeight(for: monitor)
        let effectivePosition = effectivePosition(for: monitor, resolved: resolved)
        let barHeight = max(0, CGFloat(resolved.height))
        let reservedTopInset = isVisible && resolved.reserveLayoutSpace ? barHeight : 0

        return WorkspaceBarGeometry(
            effectivePosition: effectivePosition,
            menuBarHeight: resolvedMenuBarHeight,
            barHeight: barHeight,
            reservedTopInset: reservedTopInset
        )
    }

    func frame(
        fittingWidth: CGFloat,
        monitor: Monitor,
        resolved: ResolvedBarSettings
    ) -> CGRect {
        // Clamp dimensions to valid, positive values.
        // With dynamic rows the projection can momentarily be empty, which causes
        // fittingWidth to be 0 or NaN; a zero-height bar is also possible when
        // `resolved.height` is 0.  An invalid content size would cause AppKit to
        // throw during the hosting-view constraint pass, so we enforce a minimum.
        let safeWidth = max(fittingWidth.isFinite ? fittingWidth : 0, 1)
        let safeHeight = max(barHeight.isFinite ? barHeight : 0, 1)

        if effectivePosition.isVertical {
            return verticalFrame(
                fittingHeight: safeWidth, // fittingWidth carries the vertical dimension
                monitor: monitor,
                resolved: resolved,
                safeBarWidth: safeHeight // barHeight is reused as the side-bar's width
            )
        }

        let width = max(safeWidth, 300)
        var x = monitor.frame.midX - width / 2
        var y = effectivePosition == .belowMenuBar ? monitor.visibleFrame.maxY - safeHeight : monitor.visibleFrame.maxY

        x += CGFloat(resolved.xOffset)
        y += CGFloat(resolved.yOffset)

        return CGRect(x: x, y: y, width: width, height: safeHeight)
    }

    // MARK: - Vertical (side-edge) geometry

    /// Compute the frame for a vertical indicator panel docked to the left or right edge.
    ///
    /// The panel spans the full visible height of the monitor and is `barWidth` wide.
    /// `fittingHeight` is the measured height of the VStack content; the panel height
    /// is the full visible area so it can always show all rows without clipping.
    private func verticalFrame(
        fittingHeight: CGFloat,
        monitor: Monitor,
        resolved: ResolvedBarSettings,
        safeBarWidth: CGFloat
    ) -> CGRect {
        // Enforce a minimum panel width so AppKit never gets a zero-size window. Kept compact
        // (icon-sized) since the vertical indicator shows per-row app icons, not text.
        let panelWidth = max(safeBarWidth, 34)
        let panelHeight = max(monitor.visibleFrame.height, 1)

        var x: CGFloat
        switch effectivePosition {
        case .left:
            x = monitor.visibleFrame.minX
        case .right:
            x = monitor.visibleFrame.maxX - panelWidth
        default:
            x = monitor.visibleFrame.minX
        }
        let y = monitor.visibleFrame.minY

        x += CGFloat(resolved.xOffset)
        let adjustedY = y + CGFloat(resolved.yOffset)

        return CGRect(x: x, y: adjustedY, width: panelWidth, height: panelHeight)
    }

    static func effectivePosition(
        for monitor: Monitor,
        resolved: ResolvedBarSettings
    ) -> WorkspaceBarPosition {
        if monitor.hasNotch,
           resolved.notchAware,
           resolved.position == .overlappingMenuBar
        {
            return .belowMenuBar
        }
        return resolved.position
    }

    static func menuBarHeight(for monitor: Monitor) -> CGFloat {
        let height = monitor.frame.maxY - monitor.visibleFrame.maxY
        return height > 0 ? height : 28
    }
}
