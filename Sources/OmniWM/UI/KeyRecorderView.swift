import AppKit
import Carbon
import SwiftUI

struct KeyRecorderView: NSViewRepresentable {
    let accessibilityLabel: String
    let onCapture: (KeyBinding) -> Void
    let onCancel: () -> Void

    func makeNSView(context _: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.recordingAccessibilityLabel = accessibilityLabel
        view.onCapture = onCapture
        view.onCancel = onCancel
        view.updateAccessibility()
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context _: Context) {
        nsView.recordingAccessibilityLabel = accessibilityLabel
        nsView.updateAccessibility()
    }
}

class KeyRecorderNSView: NSView {
    var onCapture: ((KeyBinding) -> Void)?
    var onCancel: (() -> Void)?
    var recordingAccessibilityLabel = "Recording hotkey"

    private let label = NSTextField(labelWithString: "Press keys...")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
        layer?.cornerRadius = 4
        focusRingType = .exterior

        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .labelColor
        addSubview(label)

        updateAccessibility()

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func updateAccessibility() {
        setAccessibilityRole(.group)
        setAccessibilityLabel(recordingAccessibilityLabel)
        setAccessibilityValue("Recording. Press a key combination.")
        setAccessibilityHelp("Press a key combination. Press Escape to cancel recording.")
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        needsDisplay = true
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        needsDisplay = true
        return resigned
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startRecording()
        } else {
            stopRecording()
        }
    }

    private func startRecording() {
        guard let window else { return }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }
            if window.makeFirstResponder(self) {
                NSAccessibility.post(element: self, notification: .focusedUIElementChanged)
            }
        }
    }

    private func stopRecording() {}

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == UInt16(kVK_Escape) {
            stopRecording()
            onCancel?()
            return true
        }

        guard let binding = binding(from: event) else { return false }

        stopRecording()
        onCapture?(binding)
        return true
    }

    private func binding(from event: NSEvent) -> KeyBinding? {
        guard event.type != .flagsChanged else { return nil }

        let carbonModifiers = carbonModifiersFromNSEvent(event)
        let requiresModifier = !isSpecialKey(Int(event.keyCode))
        guard !requiresModifier || carbonModifiers != 0 else { return nil }

        return KeyBinding(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers
        )
    }

    private func carbonModifiersFromNSEvent(_ event: NSEvent) -> UInt32 {
        var modifiers: UInt32 = 0
        let flags = event.modifierFlags

        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }

        return modifiers
    }

    private func isSpecialKey(_ keyCode: Int) -> Bool {
        (keyCode >= kVK_F1 && keyCode <= kVK_F12) ||
            keyCode == kVK_F13 || keyCode == kVK_F14 ||
            keyCode == kVK_F15 || keyCode == kVK_F16 ||
            keyCode == kVK_F17 || keyCode == kVK_F18 ||
            keyCode == kVK_F19 || keyCode == kVK_F20
    }

    override func keyDown(with event: NSEvent) {
        guard !handleKeyEvent(event) else { return }
        super.keyDown(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        _ = handleKeyEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        return handleKeyEvent(event)
    }

    override var acceptsFirstResponder: Bool {
        true
    }
}
