import CoreGraphics

/// Layout space the bar claims on each edge of a monitor's visible frame.
///
/// A horizontal bar reserves along the top edge; a vertical bar reserves along the
/// left or right edge. Only one edge is ever non-zero for a given bar.
struct WorkspaceBarReservedInsets: Equatable {
    var left: CGFloat = 0
    var right: CGFloat = 0
    var top: CGFloat = 0

    static let zero = WorkspaceBarReservedInsets()
}

struct WorkspaceBarGeometry: Equatable {
    /// Smallest width a vertical (side-edge) panel is ever laid out at.
    ///
    /// The vertical indicator shows icon-sized rows, so a configured bar height below
    /// this is clamped up. Reserved layout space must use the same clamped value or
    /// windows would be placed underneath the panel.
    static let minimumVerticalPanelWidth: CGFloat = 34

    let effectivePosition: WorkspaceBarPosition
    let menuBarHeight: CGFloat
    let barHeight: CGFloat
    let reservedInsets: WorkspaceBarReservedInsets

    /// Actual on-screen width of the panel when docked to a side edge.
    ///
    /// `barHeight` doubles as the side bar's width, clamped to the layout minimum.
    var verticalPanelWidth: CGFloat {
        max(barHeight.isFinite ? barHeight : 0, Self.minimumVerticalPanelWidth)
    }

    static func resolve(
        monitor: Monitor,
        resolved: ResolvedBarSettings,
        isVisible: Bool,
        menuBarHeight: CGFloat? = nil
    ) -> WorkspaceBarGeometry {
        let resolvedMenuBarHeight = menuBarHeight ?? self.menuBarHeight(for: monitor)
        let effectivePosition = effectivePosition(for: monitor, resolved: resolved)
        let barHeight = max(0, CGFloat(resolved.height))
        let verticalWidth = max(barHeight, minimumVerticalPanelWidth)

        // Reserve on the edge the bar actually occupies. Reserving the vertical bar's
        // width along the top would leave windows overlapping the side panel, which
        // covers their traffic-light buttons and swallows clicks near the screen edge.
        //
        // `overlappingMenuBar` is deliberately exempt: it is drawn from `visibleFrame.maxY`
        // upwards, i.e. entirely inside the menu-bar strip that is already excluded from
        // the visible frame, so it never covers a window and reserving would only shrink
        // the layout for nothing.
        let reservedInsets: WorkspaceBarReservedInsets
        if isVisible, resolved.reserveLayoutSpace {
            switch effectivePosition {
            case .left: reservedInsets = .init(left: verticalWidth)
            case .right: reservedInsets = .init(right: verticalWidth)
            case .belowMenuBar: reservedInsets = .init(top: barHeight)
            case .overlappingMenuBar: reservedInsets = .zero
            }
        } else {
            reservedInsets = .zero
        }

        return WorkspaceBarGeometry(
            effectivePosition: effectivePosition,
            menuBarHeight: resolvedMenuBarHeight,
            barHeight: barHeight,
            reservedInsets: reservedInsets
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
                resolved: resolved
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
        resolved: ResolvedBarSettings
    ) -> CGRect {
        // Enforce a minimum panel width so AppKit never gets a zero-size window. Kept compact
        // (icon-sized) since the vertical indicator shows per-row app icons, not text.
        // Shared with `reservedInsets` so the reserved strut always matches the real panel.
        let panelWidth = verticalPanelWidth
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
