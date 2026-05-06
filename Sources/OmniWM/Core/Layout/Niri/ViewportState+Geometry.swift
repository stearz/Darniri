import Foundation

extension ViewportState {
    func columnX(at index: Int, columns: [NiriContainer], gap: CGFloat) -> CGFloat {
        containerPosition(at: index, containers: columns, gap: gap, sizeKeyPath: \.cachedWidth)
    }

    func totalWidth(columns: [NiriContainer], gap: CGFloat) -> CGFloat {
        totalSpan(containers: columns, gap: gap, sizeKeyPath: \.cachedWidth)
    }

    func containerPosition(at index: Int, containers: [NiriContainer], gap: CGFloat, sizeKeyPath: KeyPath<NiriContainer, CGFloat>) -> CGFloat {
        var pos: CGFloat = 0
        for i in 0 ..< index {
            guard i < containers.count else { break }
            pos += containers[i][keyPath: sizeKeyPath] + gap
        }
        return pos
    }

    func totalSpan(containers: [NiriContainer], gap: CGFloat, sizeKeyPath: KeyPath<NiriContainer, CGFloat>) -> CGFloat {
        guard !containers.isEmpty else { return 0 }
        let sizeSum = containers.reduce(0) { $0 + $1[keyPath: sizeKeyPath] }
        let gapSum = CGFloat(max(0, containers.count - 1)) * gap
        return sizeSum + gapSum
    }

    func computeCenteredOffset(containerIndex: Int, containers: [NiriContainer], gap: CGFloat, viewportSpan: CGFloat, sizeKeyPath: KeyPath<NiriContainer, CGFloat>) -> CGFloat {
        guard !containers.isEmpty, containerIndex < containers.count else { return 0 }

        let containerSize = containers[containerIndex][keyPath: sizeKeyPath]
        if viewportSpan <= containerSize {
            return 0
        }

        return -(viewportSpan - containerSize) / 2
    }

    private func computeFitOffset(
        currentViewPos: CGFloat,
        viewSpan: CGFloat,
        targetPos: CGFloat,
        targetSpan: CGFloat,
        gap: CGFloat,
        scale: CGFloat = 2.0
    ) -> CGFloat {
        let pixelEpsilon: CGFloat = 1.0 / max(scale, 1.0)

        if viewSpan <= targetSpan + pixelEpsilon {
            return 0
        }

        let padding = ((viewSpan - targetSpan) / 2).clamped(to: 0 ... gap)
        let preferredStart = targetPos - padding
        let targetEnd = targetPos + targetSpan
        let preferredEnd = targetEnd + padding

        if currentViewPos - pixelEpsilon <= preferredStart
            && preferredEnd <= currentViewPos + viewSpan + pixelEpsilon
        {
            return currentViewPos - targetPos
        }

        let distToStart = abs(currentViewPos - preferredStart)
        let distToEnd = abs((currentViewPos + viewSpan) - preferredEnd)

        if distToStart <= distToEnd {
            return -padding
        } else {
            return -(viewSpan - padding - targetSpan)
        }
    }

    func computeVisibleOffset(
        containerIndex: Int,
        containers: [NiriContainer],
        gap: CGFloat,
        viewportSpan: CGFloat,
        sizeKeyPath: KeyPath<NiriContainer, CGFloat>,
        currentViewStart: CGFloat,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool = false,
        fromContainerIndex: Int? = nil,
        scale: CGFloat = 2.0
    ) -> CGFloat {
        guard !containers.isEmpty, containerIndex >= 0, containerIndex < containers.count else { return 0 }

        let effectiveCenterMode = (containers.count == 1 && alwaysCenterSingleColumn) ? .always : centerMode
        let targetPos = containerPosition(at: containerIndex, containers: containers, gap: gap, sizeKeyPath: sizeKeyPath)
        let targetSize = containers[containerIndex][keyPath: sizeKeyPath]

        var targetOffset: CGFloat

        switch effectiveCenterMode {
        case .always:
            targetOffset = computeCenteredOffset(
                containerIndex: containerIndex,
                containers: containers,
                gap: gap,
                viewportSpan: viewportSpan,
                sizeKeyPath: sizeKeyPath
            )

        case .onOverflow:
            if viewportSpan <= targetSize {
                targetOffset = computeCenteredOffset(
                    containerIndex: containerIndex,
                    containers: containers,
                    gap: gap,
                    viewportSpan: viewportSpan,
                    sizeKeyPath: sizeKeyPath
                )
            } else if let fromIdx = fromContainerIndex,
                      fromIdx != containerIndex,
                      containers.indices.contains(fromIdx)
            {
                let sourceIdx = if fromIdx > containerIndex {
                    min(containerIndex + 1, containers.count - 1)
                } else {
                    max(containerIndex - 1, 0)
                }
                let sourcePos = containerPosition(at: sourceIdx, containers: containers, gap: gap, sizeKeyPath: sizeKeyPath)
                let sourceSize = containers[sourceIdx][keyPath: sizeKeyPath]
                let pairSpan = if sourcePos < targetPos {
                    targetPos - sourcePos + targetSize
                } else {
                    sourcePos - targetPos + sourceSize
                }

                if pairSpan + gap * 2 <= viewportSpan {
                    targetOffset = computeFitOffset(
                        currentViewPos: currentViewStart,
                        viewSpan: viewportSpan,
                        targetPos: targetPos,
                        targetSpan: targetSize,
                        gap: gap,
                        scale: scale
                    )
                } else {
                    targetOffset = computeCenteredOffset(
                        containerIndex: containerIndex,
                        containers: containers,
                        gap: gap,
                        viewportSpan: viewportSpan,
                        sizeKeyPath: sizeKeyPath
                    )
                }
            } else {
                targetOffset = computeFitOffset(
                    currentViewPos: currentViewStart,
                    viewSpan: viewportSpan,
                    targetPos: targetPos,
                    targetSpan: targetSize,
                    gap: gap,
                    scale: scale
                )
            }

        case .never:
            targetOffset = computeFitOffset(
                currentViewPos: currentViewStart,
                viewSpan: viewportSpan,
                targetPos: targetPos,
                targetSpan: targetSize,
                gap: gap,
                scale: scale
            )
        }

        return targetOffset
    }

    func computeCenteredOffset(
        columnIndex: Int,
        columns: [NiriContainer],
        gap: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        computeCenteredOffset(containerIndex: columnIndex, containers: columns, gap: gap, viewportSpan: viewportWidth, sizeKeyPath: \.cachedWidth)
    }

    func computeVisibleOffset(
        columnIndex: Int,
        columns: [NiriContainer],
        gap: CGFloat,
        viewportWidth: CGFloat,
        currentOffset: CGFloat,
        centerMode: CenterFocusedColumn,
        alwaysCenterSingleColumn: Bool = false,
        fromColumnIndex: Int? = nil,
        scale: CGFloat = 2.0
    ) -> CGFloat {
        let colX = columnX(at: columnIndex, columns: columns, gap: gap)
        return computeVisibleOffset(
            containerIndex: columnIndex,
            containers: columns,
            gap: gap,
            viewportSpan: viewportWidth,
            sizeKeyPath: \.cachedWidth,
            currentViewStart: colX + currentOffset,
            centerMode: centerMode,
            alwaysCenterSingleColumn: alwaysCenterSingleColumn,
            fromContainerIndex: fromColumnIndex,
            scale: scale
        )
    }
}
