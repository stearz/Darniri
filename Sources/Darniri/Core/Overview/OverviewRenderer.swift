import AppKit
import CoreGraphics
import Foundation

enum OverviewRenderer {
    private enum Colors {
        static let background = CGColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0)
        static let windowBackground = CGColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1.0)
        static let windowBorder = CGColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 1.0)
        static let windowHoverBorder = CGColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 1.0)
        static let windowSelectedBorder = CGColor(red: 0.3, green: 0.8, blue: 0.4, alpha: 1.0)
        static let windowDimmed = CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 0.7)
        static let closeButtonBackground = CGColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 0.9)
        static let closeButtonHover = CGColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
        static let closeButtonX = CGColor(gray: 1.0, alpha: 1.0)
        static let searchBarBackground = CGColor(red: 0.12, green: 0.12, blue: 0.15, alpha: 0.95)
        static let searchBarBorder = CGColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 1.0)
        static let textWhite = CGColor(gray: 1.0, alpha: 1.0)
        static let textGray = CGColor(gray: 0.7, alpha: 1.0)
        static let textDimmed = CGColor(gray: 0.4, alpha: 1.0)
        static let workspaceLabelActive = CGColor(red: 0.3, green: 0.7, blue: 1.0, alpha: 1.0)
        static let workspaceLabelInactive = CGColor(gray: 0.6, alpha: 1.0)
        static let dropTarget = CGColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1.0)
        static let dropTargetBackground = CGColor(red: 0.1, green: 0.6, blue: 1.0, alpha: 0.2)
        static let placeholderFill = CGColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 0.15)
        static let placeholderBorder = CGColor(red: 0.2, green: 0.7, blue: 1.0, alpha: 0.85)
        static let columnBackground = CGColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1.0)
        static let columnBorder = CGColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 1.0)
        static let columnDivider = CGColor(red: 0.2, green: 0.2, blue: 0.25, alpha: 0.8)
    }

    private enum Metrics {
        static let windowCornerRadius: CGFloat = 8
        static let windowBorderWidth: CGFloat = 2
        static let selectedBorderWidth: CGFloat = 3
        static let closeButtonSize: CGFloat = 20
        static let closeButtonPadding: CGFloat = 6
        static let thumbnailInset: CGFloat = 1
        static let searchBarCornerRadius: CGFloat = 10
        static let searchBarBorderWidth: CGFloat = 1.5
        static let iconSize: CGFloat = 24
        static let titleFontSize: CGFloat = 12
        static let appNameFontSize: CGFloat = 10
        static let workspaceLabelFontSize: CGFloat = 16
        static let searchFontSize: CGFloat = 16
        static let dropLineHeight: CGFloat = 4
        static let dropOutlineWidth: CGFloat = 3
        static let dropLineWidth: CGFloat = 4
        static let columnCornerRadius: CGFloat = 10
        static let dividerHeight: CGFloat = 2
        static let placeholderCornerRadius: CGFloat = 8
        static let placeholderBorderWidth: CGFloat = 2
    }

    static func render(
        context: CGContext,
        layout: OverviewLayout,
        thumbnails: [Int: CGImage],
        searchQuery: String,
        progress: Double,
        bounds: CGRect,
        draggedHandle: WindowHandle? = nil
    ) {
        let alpha = CGFloat(progress)

        context.saveGState()
        context.setFillColor(Colors.background.copy(alpha: alpha)!)
        context.fill(bounds)
        context.restoreGState()

        guard progress > 0 else { return }

        let scrollOffset = layout.scrollOffset

        context.saveGState()
        context.translateBy(x: 0, y: -scrollOffset)

        for section in layout.workspaceSections {
            renderWorkspaceLabel(context: context, section: section, alpha: alpha)

            if section.isEmptyRow {
                renderEmptyRowBand(context: context, section: section, alpha: alpha)
            } else {
                if let columns = layout.niriColumnsByWorkspace[section.workspaceId] {
                    renderNiriColumns(
                        context: context,
                        columns: columns,
                        layout: layout,
                        alpha: alpha
                    )
                }

                for window in section.windows {
                    // A. Skip the lifted (dragged) window's thumbnail so it reads as
                    //    "picked up". The layout slot stays in place but is invisible.
                    if let draggedHandle, window.handle == draggedHandle {
                        continue
                    }
                    renderWindow(
                        context: context,
                        window: window,
                        thumbnail: thumbnails[window.windowId],
                        progress: progress
                    )
                }
            }
        }

        if let dragTarget = layout.dragTarget {
            renderDragTarget(
                context: context,
                layout: layout,
                dragTarget: dragTarget,
                alpha: alpha
            )
        }

        context.restoreGState()

        renderSearchBar(
            context: context,
            frame: layout.searchBarFrame,
            searchQuery: searchQuery,
            alpha: alpha
        )
    }

    private static func renderNiriColumns(
        context: CGContext,
        columns: [OverviewNiriColumn],
        layout: OverviewLayout,
        alpha: CGFloat
    ) {
        for column in columns {
            let frame = column.frame
            let path = CGPath(
                roundedRect: frame,
                cornerWidth: Metrics.columnCornerRadius,
                cornerHeight: Metrics.columnCornerRadius,
                transform: nil
            )
            context.addPath(path)
            context.setFillColor(Colors.columnBackground.copy(alpha: alpha * 0.6)!)
            context.fillPath()

            context.addPath(path)
            context.setStrokeColor(Colors.columnBorder.copy(alpha: alpha)!)
            context.setLineWidth(1.0)
            context.strokePath()

            if column.windowHandles.count > 1 {
                let frames = column.windowHandles.compactMap { layout.window(for: $0)?.overviewFrame }
                let sorted = frames.sorted { $0.maxY > $1.maxY }
                for i in 0 ..< (sorted.count - 1) {
                    let upper = sorted[i]
                    let lower = sorted[i + 1]
                    let y = (upper.minY + lower.maxY) / 2
                    let divider = CGRect(
                        x: frame.minX + 8,
                        y: y - Metrics.dividerHeight / 2,
                        width: frame.width - 16,
                        height: Metrics.dividerHeight
                    )
                    context.setFillColor(Colors.columnDivider.copy(alpha: alpha)!)
                    context.fill(divider)
                }
            }
        }
    }

    // MARK: - Empty row band

    /// Renders the placeholder band for an empty (buffer) row — a faint dashed rectangle
    /// that acts as a visible drop target in the overview.
    private static func renderEmptyRowBand(
        context: CGContext,
        section: OverviewWorkspaceSection,
        alpha: CGFloat
    ) {
        let frame = section.gridFrame
        guard frame.width > 0, frame.height > 0 else { return }

        // Faint fill
        context.setFillColor(
            CGColor(red: 0.15, green: 0.15, blue: 0.2, alpha: alpha * 0.25)
        )
        let path = CGPath(
            roundedRect: frame,
            cornerWidth: 8,
            cornerHeight: 8,
            transform: nil
        )
        context.addPath(path)
        context.fillPath()

        // Dashed border
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(CGColor(red: 0.35, green: 0.35, blue: 0.45, alpha: alpha * 0.7))
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [6, 4])
        context.strokePath()
        context.restoreGState()
    }

    private static func renderDragTarget(
        context: CGContext,
        layout: OverviewLayout,
        dragTarget: OverviewDragTarget,
        alpha: CGFloat
    ) {
        switch dragTarget {
        case let .niriWindowInsert(_, targetHandle, position):
            guard let window = layout.window(for: targetHandle) else { return }
            // B. Placeholder: a window-sized translucent dashed rounded rect placed
            //    to the left (.after in screen coords = above in overview Y) or right
            //    (.before = below in overview Y) of the target window, offset by half
            //    the window width.
            let frame = window.overviewFrame
            let placeholderWidth = frame.width
            let placeholderHeight = frame.height
            // In the overview grid layout, windows are arranged left→right. .before means
            // "insert visually before (left)" and .after means "insert visually after (right)".
            // The renderer draws a side-by-side placeholder beside the target window.
            let placeholderX: CGFloat
            switch position {
            case .before:
                // Placeholder to the left of the target.
                placeholderX = frame.minX - placeholderWidth - 8
            case .after, .swap:
                // Placeholder to the right of the target.
                placeholderX = frame.maxX + 8
            }
            let placeholderFrame = CGRect(
                x: placeholderX,
                y: frame.minY,
                width: placeholderWidth,
                height: placeholderHeight
            )
            renderPlaceholder(context: context, frame: placeholderFrame, alpha: alpha)

        case let .niriColumnInsert(workspaceId, insertIndex):
            // B. Placeholder: a column-width translucent dashed rect placed in the gap.
            guard let columns = layout.niriColumnsByWorkspace[workspaceId],
                  !columns.isEmpty
            else { return }

            // Infer a representative column width from the existing columns.
            let avgColumnWidth = columns.reduce(CGFloat(0)) { $0 + $1.frame.width } / CGFloat(columns.count)
            let gridMinY = columns.map(\.frame.minY).min() ?? 0
            let gridMaxY = columns.map(\.frame.maxY).max() ?? 0
            let gridHeight = max(gridMaxY - gridMinY, 40)

            // Find the X position for this insert index.
            let sortedColumns = columns.sorted { $0.columnIndex < $1.columnIndex }
            let placeholderX: CGFloat
            if insertIndex == 0 {
                let firstX = sortedColumns.first?.frame.minX ?? 0
                placeholderX = firstX - avgColumnWidth - 8
            } else if let leftCol = sortedColumns.first(where: { $0.columnIndex == insertIndex - 1 }) {
                placeholderX = leftCol.frame.maxX + 8
            } else if let rightCol = sortedColumns.first(where: { $0.columnIndex == insertIndex }) {
                placeholderX = rightCol.frame.minX - avgColumnWidth - 8
            } else {
                let lastX = sortedColumns.last?.frame.maxX ?? 0
                placeholderX = lastX + 8
            }

            let placeholderFrame = CGRect(
                x: placeholderX,
                y: gridMinY,
                width: avgColumnWidth,
                height: gridHeight
            )
            renderPlaceholder(context: context, frame: placeholderFrame, alpha: alpha)

        case let .workspaceMove(workspaceId):
            guard let section = layout.workspaceSections.first(where: { $0.workspaceId == workspaceId })
            else { return }

            if section.isEmptyRow {
                // B. For an empty-row drop target, render a window-sized placeholder
                //    centered in the grid band.
                let band = section.gridFrame
                let phWidth = min(band.width * 0.4, 300)
                let phHeight = band.height * 0.8
                let placeholderFrame = CGRect(
                    x: band.midX - phWidth / 2,
                    y: band.midY - phHeight / 2,
                    width: phWidth,
                    height: phHeight
                )
                renderPlaceholder(context: context, frame: placeholderFrame, alpha: alpha)
            } else {
                // Generic section highlight (outline of the whole section).
                context.setStrokeColor(Colors.dropTarget.copy(alpha: alpha)!)
                context.setLineWidth(Metrics.dropOutlineWidth)
                context.stroke(section.sectionFrame)
            }
        }
    }

    /// B. Renders a "drop placeholder": a translucent filled rounded rect with a
    ///    dashed accent border — reads as a concrete window-shaped insertion slot.
    private static func renderPlaceholder(
        context: CGContext,
        frame: CGRect,
        alpha: CGFloat
    ) {
        guard frame.width > 0, frame.height > 0 else { return }

        let path = CGPath(
            roundedRect: frame,
            cornerWidth: Metrics.placeholderCornerRadius,
            cornerHeight: Metrics.placeholderCornerRadius,
            transform: nil
        )

        // Translucent fill.
        context.addPath(path)
        context.setFillColor(Colors.placeholderFill.copy(alpha: alpha)!)
        context.fillPath()

        // Dashed border.
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(Colors.placeholderBorder.copy(alpha: alpha)!)
        context.setLineWidth(Metrics.placeholderBorderWidth)
        context.setLineDash(phase: 0, lengths: [8, 5])
        context.strokePath()
        context.restoreGState()
    }

    private static func renderWorkspaceLabel(
        context: CGContext,
        section: OverviewWorkspaceSection,
        alpha: CGFloat
    ) {
        let font = CTFontCreateWithName("SF Pro Display" as CFString, Metrics.workspaceLabelFontSize, nil)
        let color = section.isActive ? Colors.workspaceLabelActive : Colors.workspaceLabelInactive

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: color.copy(alpha: alpha)!)!
        ]

        let attributedString = NSAttributedString(string: section.name, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: section.labelFrame.minX, y: section.labelFrame.minY + 8)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func renderWindow(
        context: CGContext,
        window: OverviewWindowItem,
        thumbnail: CGImage?,
        progress: Double
    ) {
        let frame = window.interpolatedFrame(progress: progress)
        let alpha = CGFloat(progress) * (window.matchesSearch ? 1.0 : 0.3)

        context.saveGState()

        let path = CGPath(
            roundedRect: frame,
            cornerWidth: Metrics.windowCornerRadius,
            cornerHeight: Metrics.windowCornerRadius,
            transform: nil
        )
        context.addPath(path)
        context.setFillColor(Colors.windowBackground.copy(alpha: alpha)!)
        context.fillPath()

        if let thumbnail {
            let thumbnailRect = frame.insetBy(dx: Metrics.thumbnailInset, dy: Metrics.thumbnailInset)
            let drawRect = aspectFitRect(
                contentSize: CGSize(width: thumbnail.width, height: thumbnail.height),
                in: thumbnailRect
            )
            context.saveGState()
            let clipPath = CGPath(
                roundedRect: thumbnailRect,
                cornerWidth: Metrics.windowCornerRadius - 1,
                cornerHeight: Metrics.windowCornerRadius - 1,
                transform: nil
            )
            context.addPath(clipPath)
            context.clip()
            context.draw(thumbnail, in: drawRect)
            context.restoreGState()
        }

        if !window.matchesSearch {
            context.addPath(path)
            context.setFillColor(Colors.windowDimmed)
            context.fillPath()
        }

        let borderColor: CGColor
        let borderWidth: CGFloat
        if window.isSelected {
            borderColor = Colors.windowSelectedBorder.copy(alpha: alpha)!
            borderWidth = Metrics.selectedBorderWidth
        } else if window.isHovered {
            borderColor = Colors.windowHoverBorder.copy(alpha: alpha)!
            borderWidth = Metrics.windowBorderWidth
        } else {
            borderColor = Colors.windowBorder.copy(alpha: alpha * 0.5)!
            borderWidth = Metrics.windowBorderWidth
        }

        context.addPath(path)
        context.setStrokeColor(borderColor)
        context.setLineWidth(borderWidth)
        context.strokePath()

        let infoHeight: CGFloat = 36
        let infoRect = CGRect(
            x: frame.minX,
            y: frame.minY,
            width: frame.width,
            height: infoHeight
        )

        context.saveGState()
        let infoPath = CGMutablePath()
        infoPath.move(to: CGPoint(x: infoRect.minX + Metrics.windowCornerRadius, y: infoRect.minY))
        infoPath.addLine(to: CGPoint(x: infoRect.maxX - Metrics.windowCornerRadius, y: infoRect.minY))
        infoPath.addArc(
            center: CGPoint(
                x: infoRect.maxX - Metrics.windowCornerRadius,
                y: infoRect.minY + Metrics.windowCornerRadius
            ),
            radius: Metrics.windowCornerRadius,
            startAngle: -.pi / 2,
            endAngle: 0,
            clockwise: false
        )
        infoPath.addLine(to: CGPoint(x: infoRect.maxX, y: infoRect.maxY))
        infoPath.addLine(to: CGPoint(x: infoRect.minX, y: infoRect.maxY))
        infoPath.addLine(to: CGPoint(x: infoRect.minX, y: infoRect.minY + Metrics.windowCornerRadius))
        infoPath.addArc(
            center: CGPoint(
                x: infoRect.minX + Metrics.windowCornerRadius,
                y: infoRect.minY + Metrics.windowCornerRadius
            ),
            radius: Metrics.windowCornerRadius,
            startAngle: .pi,
            endAngle: -.pi / 2,
            clockwise: false
        )
        infoPath.closeSubpath()

        context.addPath(infoPath)
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: alpha * 0.9))
        context.fillPath()
        context.restoreGState()

        if let icon = window.appIcon {
            let iconRect = CGRect(
                x: infoRect.minX + 8,
                y: infoRect.minY + (infoHeight - Metrics.iconSize) / 2,
                width: Metrics.iconSize,
                height: Metrics.iconSize
            )
            if let cgIcon = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                context.draw(cgIcon, in: iconRect)
            }
        }

        let textX = infoRect.minX + 8 + Metrics.iconSize + 6
        let maxTextWidth = infoRect.width - (textX - infoRect.minX) - 8

        let titleFont = CTFontCreateWithName("SF Pro Text" as CFString, Metrics.titleFontSize, nil)
        let truncatedTitle = truncateText(window.title, font: titleFont, maxWidth: maxTextWidth)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(cgColor: Colors.textWhite.copy(alpha: alpha)!)!
        ]
        let titleString = NSAttributedString(string: truncatedTitle, attributes: titleAttributes)
        let titleLine = CTLineCreateWithAttributedString(titleString)

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: textX, y: infoRect.minY + 20)
        CTLineDraw(titleLine, context)
        context.restoreGState()

        let appFont = CTFontCreateWithName("SF Pro Text" as CFString, Metrics.appNameFontSize, nil)
        let appAttributes: [NSAttributedString.Key: Any] = [
            .font: appFont,
            .foregroundColor: NSColor(cgColor: Colors.textGray.copy(alpha: alpha)!)!
        ]
        let appString = NSAttributedString(string: window.appName, attributes: appAttributes)
        let appLine = CTLineCreateWithAttributedString(appString)

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: textX, y: infoRect.minY + 6)
        CTLineDraw(appLine, context)
        context.restoreGState()

        if window.isHovered {
            renderCloseButton(
                context: context,
                frame: window.closeButtonFrame,
                isHovered: window.closeButtonHovered,
                alpha: alpha
            )
        }

        context.restoreGState()
    }

    private static func renderCloseButton(
        context: CGContext,
        frame: CGRect,
        isHovered: Bool,
        alpha: CGFloat
    ) {
        let bgColor = isHovered ? Colors.closeButtonHover : Colors.closeButtonBackground
        let path = CGPath(ellipseIn: frame, transform: nil)

        context.addPath(path)
        context.setFillColor(bgColor.copy(alpha: alpha)!)
        context.fillPath()

        let xInset: CGFloat = 6
        context.setStrokeColor(Colors.closeButtonX.copy(alpha: alpha)!)
        context.setLineWidth(2)
        context.setLineCap(.round)

        context.move(to: CGPoint(x: frame.minX + xInset, y: frame.minY + xInset))
        context.addLine(to: CGPoint(x: frame.maxX - xInset, y: frame.maxY - xInset))
        context.strokePath()

        context.move(to: CGPoint(x: frame.maxX - xInset, y: frame.minY + xInset))
        context.addLine(to: CGPoint(x: frame.minX + xInset, y: frame.maxY - xInset))
        context.strokePath()
    }

    private static func renderSearchBar(
        context: CGContext,
        frame: CGRect,
        searchQuery: String,
        alpha: CGFloat
    ) {
        let path = CGPath(
            roundedRect: frame,
            cornerWidth: Metrics.searchBarCornerRadius,
            cornerHeight: Metrics.searchBarCornerRadius,
            transform: nil
        )

        context.addPath(path)
        context.setFillColor(Colors.searchBarBackground.copy(alpha: alpha)!)
        context.fillPath()

        context.addPath(path)
        context.setStrokeColor(Colors.searchBarBorder.copy(alpha: alpha)!)
        context.setLineWidth(Metrics.searchBarBorderWidth)
        context.strokePath()

        let displayText = searchQuery.isEmpty ? "Type to search..." : searchQuery
        let textColor = searchQuery.isEmpty ? Colors.textDimmed : Colors.textWhite

        let font = CTFontCreateWithName("SF Pro Text" as CFString, Metrics.searchFontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: textColor.copy(alpha: alpha)!)!
        ]
        let attributedString = NSAttributedString(string: displayText, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)

        let textBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let textX = frame.midX - textBounds.width / 2
        let textY = frame.midY - textBounds.height / 2

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: textX, y: textY)
        CTLineDraw(line, context)
        context.restoreGState()

        if !searchQuery.isEmpty {
            let cursorX = textX + textBounds.width + 2
            let cursorHeight: CGFloat = 18
            let cursorY = frame.midY - cursorHeight / 2

            let time = CACurrentMediaTime()
            let cursorAlpha = (sin(time * 3) + 1) / 2

            context.setFillColor(Colors.textWhite.copy(alpha: alpha * CGFloat(cursorAlpha))!)
            context.fill(CGRect(x: cursorX, y: cursorY, width: 2, height: cursorHeight))
        }
    }

    private static func truncateText(_ text: String, font: CTFont, maxWidth: CGFloat) -> String {
        var result = text
        while result.count > 0 {
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let attrString = NSAttributedString(string: result + "...", attributes: attributes)
            let line = CTLineCreateWithAttributedString(attrString)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

            if bounds.width <= maxWidth || result.count <= 3 {
                return result == text ? text : result + "..."
            }
            result = String(result.dropLast())
        }
        return text
    }

    static func aspectFitRect(contentSize: CGSize, in bounds: CGRect) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / contentSize.width, bounds.height / contentSize.height)
        let fittedSize = CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
        return CGRect(
            x: bounds.minX + (bounds.width - fittedSize.width) / 2,
            y: bounds.minY + (bounds.height - fittedSize.height) / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}
