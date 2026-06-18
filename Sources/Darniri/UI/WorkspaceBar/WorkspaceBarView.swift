import AppKit
import Observation
import SwiftUI

struct WorkspaceBarItem: Identifiable, Equatable {
    let id: WorkspaceDescriptor.ID
    let name: String
    let rawName: String
    let isFocused: Bool
    /// 1-based index of this row within the monitor's stack (top = 1).
    let rowIndex: Int
    /// True for the topmost or bottommost empty buffer row — rendered faintly so
    /// the user perceives "there's room above/below" without cluttering the bar.
    let isBuffer: Bool
    let tiledWindows: [WorkspaceBarWindowItem]
    let floatingWindows: [WorkspaceBarWindowItem]

    var windows: [WorkspaceBarWindowItem] {
        tiledWindows + floatingWindows
    }
}

struct WorkspaceBarProjection: Equatable {
    let items: [WorkspaceBarItem]
    let scratchpad: WorkspaceBarScratchpadItem?
}

struct WorkspaceBarWindowItem: Identifiable, Equatable {
    let id: WindowToken
    let windowId: Int
    let appName: String
    let icon: NSImage?
    let isFocused: Bool
    let windowCount: Int
    let allWindows: [WorkspaceBarWindowInfo]

    static func == (lhs: WorkspaceBarWindowItem, rhs: WorkspaceBarWindowItem) -> Bool {
        lhs.id == rhs.id
            && lhs.windowId == rhs.windowId
            && lhs.appName == rhs.appName
            && lhs.icon === rhs.icon
            && lhs.isFocused == rhs.isFocused
            && lhs.windowCount == rhs.windowCount
            && lhs.allWindows == rhs.allWindows
    }
}

struct WorkspaceBarWindowInfo: Identifiable, Equatable {
    let id: WindowToken
    let windowId: Int
    let title: String
    let isFocused: Bool
}

struct WorkspaceBarScratchpadItem: Identifiable, Equatable {
    let window: WorkspaceBarWindowItem
    let isVisible: Bool
    let workspaceId: WorkspaceDescriptor.ID
    let workspaceName: String
    let rawWorkspaceName: String

    var id: WindowToken {
        window.id
    }
}

struct WorkspaceBarSnapshot: Equatable {
    let projection: WorkspaceBarProjection
    let showLabels: Bool
    let backgroundOpacity: Double
    let barHeight: CGFloat
    let accentColor: SettingsColor?
    let textColor: SettingsColor?
    /// True when the bar is positioned on a vertical edge (left/right) and should
    /// stack row chips vertically instead of horizontally.
    let isVertical: Bool

    var items: [WorkspaceBarItem] {
        projection.items
    }

    var scratchpad: WorkspaceBarScratchpadItem? {
        projection.scratchpad
    }
}

@MainActor @Observable
final class WorkspaceBarModel {
    var snapshot: WorkspaceBarSnapshot

    init(snapshot: WorkspaceBarSnapshot) {
        self.snapshot = snapshot
    }
}

@MainActor
struct WorkspaceBarView: View {
    let model: WorkspaceBarModel
    @Bindable var motionPolicy: MotionPolicy
    let onFocusWorkspace: (WorkspaceBarItem) -> Void
    let onFocusWindow: (WindowToken) -> Void
    let onActivateScratchpad: () -> Void

    var body: some View {
        WorkspaceBarContentView(
            snapshot: model.snapshot,
            animationsEnabled: motionPolicy.animationsEnabled,
            onFocusWorkspace: onFocusWorkspace,
            onFocusWindow: onFocusWindow,
            onActivateScratchpad: onActivateScratchpad
        )
    }
}

@MainActor
struct WorkspaceBarMeasurementView: View {
    let snapshot: WorkspaceBarSnapshot

    var body: some View {
        WorkspaceBarContentView(
            snapshot: snapshot,
            animationsEnabled: false,
            onFocusWorkspace: { _ in },
            onFocusWindow: { _ in },
            onActivateScratchpad: {}
        )
        // For vertical bars: constrain horizontally so fittingSize.width gives us
        // the needed width of the panel. For horizontal bars: constrain horizontally
        // so fittingSize.width gives the needed width.
        .fixedSize(horizontal: true, vertical: false)
    }
}

@MainActor
private struct WorkspaceBarContentView: View {
    let snapshot: WorkspaceBarSnapshot
    let animationsEnabled: Bool
    let onFocusWorkspace: (WorkspaceBarItem) -> Void
    let onFocusWindow: (WindowToken) -> Void
    let onActivateScratchpad: () -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var itemHeight: CGFloat {
        max(16, snapshot.barHeight - 4)
    }

    private var iconSize: CGFloat {
        max(12, itemHeight - 6)
    }

    private let workspaceSpacing: CGFloat = 8
    private let windowSpacing: CGFloat = 2
    private let cornerRadius: CGFloat = 6

    private var effectiveAnimationsEnabled: Bool {
        animationsEnabled && !accessibilityReduceMotion
    }

    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(snapshot.backgroundOpacity)
            : Color.black.opacity(snapshot.backgroundOpacity * 0.5)
    }

    private var accentColor: Color? {
        snapshot.accentColor?.swiftUIColor
    }

    private var textColor: Color? {
        snapshot.textColor?.swiftUIColor
    }

    private var barShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        if snapshot.isVertical {
            verticalBody
        } else {
            horizontalBody
        }
    }

    // MARK: - Horizontal layout (top-edge bar, original)

    @ViewBuilder
    private var horizontalBody: some View {
        HStack(spacing: workspaceSpacing) {
            ForEach(snapshot.items, id: \.id) { item in
                WorkspaceItemView(
                    item: item,
                    iconSize: iconSize,
                    itemHeight: itemHeight,
                    windowSpacing: windowSpacing,
                    cornerRadius: cornerRadius,
                    animationsEnabled: effectiveAnimationsEnabled,
                    showLabels: snapshot.showLabels,
                    accentColor: accentColor,
                    textColor: textColor,
                    onFocusWorkspace: { onFocusWorkspace(item) },
                    onFocusWindow: onFocusWindow
                )
            }

            if let scratchpad = snapshot.scratchpad {
                ScratchpadPillView(
                    item: scratchpad,
                    iconSize: iconSize,
                    itemHeight: itemHeight,
                    animationsEnabled: effectiveAnimationsEnabled,
                    accentColor: accentColor,
                    textColor: textColor,
                    onActivateScratchpad: onActivateScratchpad
                )
            }
        }
        .padding(.horizontal, 4)
        .frame(height: itemHeight + 4)
        .background {
            if accessibilityReduceTransparency {
                barShape.fill(Color(NSColor.windowBackgroundColor).opacity(0.96))
            } else {
                barShape
                    .fill(backgroundColor)
                    .background(.ultraThinMaterial, in: barShape)
            }

            barShape.strokeBorder(
                colorSchemeContrast == .increased
                    ? Color.primary.opacity(0.45)
                    : Color.secondary.opacity(0.18),
                lineWidth: colorSchemeContrast == .increased ? 1 : 0.5
            )
        }
    }

    // MARK: - Vertical layout (side-edge indicator, rows stacked top→bottom)

    @ViewBuilder
    private var verticalBody: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: workspaceSpacing) {
                ForEach(snapshot.items, id: \.id) { item in
                    WorkspaceItemView(
                        item: item,
                        iconSize: iconSize,
                        itemHeight: itemHeight,
                        windowSpacing: windowSpacing,
                        cornerRadius: cornerRadius,
                        animationsEnabled: effectiveAnimationsEnabled,
                        showLabels: snapshot.showLabels,
                        isVertical: true,
                        accentColor: accentColor,
                        textColor: textColor,
                        onFocusWorkspace: { onFocusWorkspace(item) },
                        onFocusWindow: onFocusWindow
                    )
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
            .background {
                if accessibilityReduceTransparency {
                    barShape.fill(Color(NSColor.windowBackgroundColor).opacity(0.96))
                } else {
                    barShape
                        .fill(backgroundColor)
                        .background(.ultraThinMaterial, in: barShape)
                }
                barShape.strokeBorder(
                    colorSchemeContrast == .increased
                        ? Color.primary.opacity(0.45)
                        : Color.secondary.opacity(0.18),
                    lineWidth: colorSchemeContrast == .increased ? 1 : 0.5
                )
            }
            Spacer(minLength: 0)
        }
    }
}

@MainActor
private struct WorkspaceItemView: View {
    let item: WorkspaceBarItem
    let iconSize: CGFloat
    let itemHeight: CGFloat
    let windowSpacing: CGFloat
    let cornerRadius: CGFloat
    let animationsEnabled: Bool
    let showLabels: Bool
    var isVertical: Bool = false
    let accentColor: Color?
    let textColor: Color?
    let onFocusWorkspace: () -> Void
    let onFocusWindow: (WindowToken) -> Void

    @State private var isHovered = false

    // In the vertical (side-edge) bar the app icons stack top→bottom so the bar
    // stays narrow; in the horizontal bar they remain side-by-side.
    private var contentLayout: AnyLayout {
        isVertical
            ? AnyLayout(VStackLayout(spacing: windowSpacing))
            : AnyLayout(HStackLayout(spacing: windowSpacing))
    }

    // A separator that runs across the stacking axis: vertical line between
    // horizontal items, horizontal line between vertically stacked items.
    @ViewBuilder
    private var separator: some View {
        Divider()
            .frame(width: isVertical ? iconSize : nil, height: isVertical ? nil : iconSize)
            .padding(isVertical ? .vertical : .horizontal, 2)
            .accessibilityHidden(true)
    }

    var body: some View {
        contentLayout {
            if showLabels {
                WorkspaceLabelButton(
                    item: item,
                    accentColor: accentColor,
                    textColor: textColor,
                    onFocusWorkspace: onFocusWorkspace
                )

                if !item.windows.isEmpty {
                    separator
                }
            } else if item.windows.isEmpty {
                WorkspaceLabelButton(
                    item: item,
                    accentColor: accentColor,
                    textColor: textColor,
                    onFocusWorkspace: onFocusWorkspace
                )
            }

            ForEach(item.tiledWindows, id: \.id) { window in
                WindowIconView(
                    window: window,
                    iconSize: iconSize,
                    isFocused: window.isFocused,
                    isInFocusedWorkspace: item.isFocused,
                    context: .tiled,
                    animationsEnabled: animationsEnabled,
                    accentColor: accentColor,
                    textColor: textColor,
                    onFocusWindow: onFocusWindow
                )
            }

            if !item.tiledWindows.isEmpty && !item.floatingWindows.isEmpty {
                separator
            }

            if !item.floatingWindows.isEmpty {
                FloatingWindowsGroupView(
                    windows: item.floatingWindows,
                    iconSize: iconSize,
                    itemHeight: itemHeight,
                    isInFocusedWorkspace: item.isFocused,
                    isVertical: isVertical,
                    animationsEnabled: animationsEnabled,
                    accentColor: accentColor,
                    textColor: textColor,
                    onFocusWindow: onFocusWindow
                )
            }
        }
        .padding(.horizontal, isVertical ? 4 : 8)
        .padding(.vertical, isVertical ? 4 : 2)
        .frame(height: isVertical ? nil : itemHeight)
        .frame(maxWidth: isVertical ? .infinity : nil)
        .background {
            if item.isFocused || isHovered {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.regularMaterial)
                    .overlay {
                        if item.isFocused {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .strokeBorder(accentColor ?? .accentColor, lineWidth: 1)
                        }
                    }
            }
        }
        // Buffer rows (top/bottom empty sentinels) are shown faintly so the user
        // can perceive "there's room above/below" without the chip dominating.
        .opacity(item.isBuffer ? 0.35 : 1.0)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.isBuffer ? "Buffer row \(item.rowIndex)" : "Row \(item.rowIndex)")
    }
}

@MainActor
private struct WorkspaceLabelButton: View {
    let item: WorkspaceBarItem
    let accentColor: Color?
    let textColor: Color?
    let onFocusWorkspace: () -> Void

    private var resolvedAccentColor: Color {
        accentColor ?? .accentColor
    }

    private var resolvedLabelColor: Color {
        textColor ?? (item.isFocused ? resolvedAccentColor : .secondary)
    }

    var body: some View {
        Button(action: onFocusWorkspace) {
            Text(item.name)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundColor(resolvedLabelColor)
                .frame(minWidth: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Row \(item.rowIndex)")
        .accessibilityValue(item.isFocused ? "Focused" : "")
        .help("Focus row \(item.rowIndex)")
    }
}

@MainActor
private struct FloatingWindowsGroupView: View {
    let windows: [WorkspaceBarWindowItem]
    let iconSize: CGFloat
    let itemHeight: CGFloat
    let isInFocusedWorkspace: Bool
    var isVertical: Bool = false
    let animationsEnabled: Bool
    let accentColor: Color?
    let textColor: Color?
    let onFocusWindow: (WindowToken) -> Void

    private var resolvedSecondaryTextColor: Color {
        textColor ?? .secondary
    }

    private var groupLayout: AnyLayout {
        isVertical
            ? AnyLayout(VStackLayout(spacing: 3))
            : AnyLayout(HStackLayout(spacing: 3))
    }

    var body: some View {
        groupLayout {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: max(10, iconSize * 0.58), weight: .medium))
                .foregroundStyle(resolvedSecondaryTextColor)
                .accessibilityHidden(true)

            ForEach(windows, id: \.id) { window in
                WindowIconView(
                    window: window,
                    iconSize: iconSize,
                    isFocused: window.isFocused,
                    isInFocusedWorkspace: isInFocusedWorkspace,
                    context: .floating,
                    animationsEnabled: animationsEnabled,
                    accentColor: accentColor,
                    textColor: textColor,
                    onFocusWindow: onFocusWindow
                )
            }
        }
        .padding(isVertical ? .vertical : .horizontal, 5)
        .frame(width: isVertical ? max(16, itemHeight - 2) : nil)
        .frame(height: isVertical ? nil : max(16, itemHeight - 2))
        .background {
            Capsule(style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.24), lineWidth: 0.75)
                }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floating windows")
    }
}

@MainActor
private struct ScratchpadPillView: View {
    let item: WorkspaceBarScratchpadItem
    let iconSize: CGFloat
    let itemHeight: CGFloat
    let animationsEnabled: Bool
    let accentColor: Color?
    let textColor: Color?
    let onActivateScratchpad: () -> Void

    @State private var isHovered = false

    private var resolvedAccentColor: Color {
        accentColor ?? .accentColor
    }

    private var resolvedSecondaryTextColor: Color {
        textColor ?? .secondary
    }

    var body: some View {
        Button(action: onActivateScratchpad) {
            HStack(spacing: 5) {
                Image(systemName: "tray.fill")
                    .font(.system(size: max(10, iconSize * 0.64), weight: .semibold))
                    .foregroundColor(item.window.isFocused ? resolvedAccentColor : resolvedSecondaryTextColor)
                    .accessibilityHidden(true)

                AppIconImage(icon: item.window.icon)
                    .frame(width: iconSize, height: iconSize)
                    .opacity(item.window.isFocused ? 1 : 0.82)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .frame(height: itemHeight)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(scale)
        .animation(animationsEnabled ? .easeInOut(duration: 0.12) : nil, value: isHovered)
        .animation(animationsEnabled ? .easeInOut(duration: 0.15) : nil, value: item.window.isFocused)
        .background {
            Capsule(style: .continuous)
                .fill(item.window.isFocused ? resolvedAccentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                .background(.regularMaterial, in: Capsule(style: .continuous))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            item.window.isFocused ? resolvedAccentColor : Color.secondary.opacity(item.isVisible ? 0.36 : 0.22),
                            lineWidth: item.window.isFocused ? 1.2 : 0.8
                        )
                }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel("Scratchpad")
        .accessibilityValue(accessibilityValue)
        .help("Scratchpad: \(item.window.appName), \(item.isVisible ? "visible" : "hidden")")
    }

    private var scale: CGFloat {
        if item.window.isFocused {
            1.04
        } else if isHovered {
            1.03
        } else {
            1
        }
    }

    private var accessibilityValue: String {
        var parts = [item.window.appName, item.isVisible ? "Visible" : "Hidden"]
        if item.window.isFocused {
            parts.append("Focused")
        }
        parts.append("Workspace \(item.workspaceName)")
        return parts.joined(separator: ", ")
    }
}

private enum WorkspaceBarWindowContext {
    case tiled
    case floating

    var label: String {
        switch self {
        case .tiled:
            "window"
        case .floating:
            "floating window"
        }
    }
}

@MainActor
private struct WindowIconView: View {
    let window: WorkspaceBarWindowItem
    let iconSize: CGFloat
    let isFocused: Bool
    let isInFocusedWorkspace: Bool
    let context: WorkspaceBarWindowContext
    let animationsEnabled: Bool
    let accentColor: Color?
    let textColor: Color?
    let onFocusWindow: (WindowToken) -> Void

    @State private var isHovered = false
    @State private var showingWindowList = false

    private var resolvedAccentColor: Color {
        accentColor ?? .accentColor
    }

    var body: some View {
        Button {
            if window.windowCount > 1 {
                showingWindowList = true
            } else {
                onFocusWindow(window.id)
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                AppIconImage(icon: window.icon)
                    .frame(width: iconSize, height: iconSize)
                    .opacity(opacity)
                    .shadow(color: resolvedAccentColor.opacity(glowOpacity), radius: glowRadius)
                    .accessibilityHidden(true)

                if window.windowCount > 1 {
                    WindowCountBadge(count: window.windowCount, iconSize: iconSize, textColor: textColor)
                        .offset(x: iconSize * 0.2, y: -iconSize * 0.1)
                }
            }
            .frame(minWidth: max(16, iconSize + 4), minHeight: max(16, iconSize + 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(scale)
        .animation(animationsEnabled ? .easeInOut(duration: 0.15) : nil, value: isFocused)
        .animation(animationsEnabled ? .easeInOut(duration: 0.1) : nil, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .sheet(isPresented: $showingWindowList) {
            WindowListSheet(
                windows: window.allWindows,
                appName: window.appName,
                accentColor: accentColor,
                textColor: textColor,
                onFocusWindow: { token in
                    onFocusWindow(token)
                    showingWindowList = false
                }
            )
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .help(window.appName)
    }

    private var opacity: Double {
        if isFocused {
            1.0
        } else if isInFocusedWorkspace {
            0.4
        } else {
            0.5
        }
    }

    private var scale: CGFloat {
        if isFocused {
            1.1
        } else if isHovered {
            1.05
        } else {
            1.0
        }
    }

    private var glowRadius: CGFloat {
        isFocused ? 4 : 0
    }

    private var glowOpacity: Double {
        isFocused ? 0.5 : 0
    }

    private var accessibilityLabel: String {
        if window.windowCount > 1 {
            "\(window.appName), \(window.windowCount) \(context.label)s"
        } else {
            "Focus \(window.appName) \(context.label)"
        }
    }

    private var accessibilityValue: String {
        isFocused ? "Focused" : ""
    }
}

@MainActor
private struct AppIconImage: View {
    let icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
    }
}

@MainActor
private struct WindowCountBadge: View {
    let count: Int
    let iconSize: CGFloat
    let textColor: Color?

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundColor(textColor ?? .primary)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5)
                    }
            )
            .frame(minWidth: max(12, iconSize * 0.55), minHeight: max(12, iconSize * 0.55))
            .accessibilityHidden(true)
    }
}

@MainActor
private struct WindowListSheet: View {
    let windows: [WorkspaceBarWindowInfo]
    let appName: String
    let accentColor: Color?
    let textColor: Color?
    let onFocusWindow: (WindowToken) -> Void
    @Environment(\.dismiss) private var dismiss

    private var resolvedAccentColor: Color {
        accentColor ?? .accentColor
    }

    private var resolvedPrimaryTextColor: Color {
        textColor ?? .primary
    }

    private var resolvedSecondaryTextColor: Color {
        textColor ?? .secondary
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(appName)
                    .font(.headline)
                    .padding()
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .padding()
            }
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            List(windows) { windowInfo in
                Button {
                    onFocusWindow(windowInfo.id)
                } label: {
                    HStack {
                        Text(windowInfo.title)
                            .foregroundColor(windowInfo.isFocused ? resolvedPrimaryTextColor : resolvedSecondaryTextColor)
                        Spacer()
                        if windowInfo.isFocused {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(resolvedAccentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minWidth: 300, minHeight: 200)
    }
}
