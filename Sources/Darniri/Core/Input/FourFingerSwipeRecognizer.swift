import Foundation

struct TrackpadContact: Sendable {
    let id: Int32
    let x: Double
    let y: Double
}

/// Normalized trackpad coordinates increase rightward and upward, independently of natural scrolling.
struct FourFingerSwipeRecognizer {
    private var origin: [Int32: TrackpadContact]?
    private var consumed = false
    private var lastTimestamp: Double?

    mutating func update(
        contacts: [TrackpadContact],
        timestamp: Double,
        isEnabled: Bool = true
    ) -> Direction? {
        // An interrupted stream must not complete an old gesture after wake or reconnection.
        if let lastTimestamp, timestamp - lastTimestamp > 0.5 || timestamp < lastTimestamp {
            origin = nil
            consumed = !contacts.isEmpty
        }
        lastTimestamp = timestamp
        if contacts.isEmpty {
            origin = nil
            consumed = false
            return nil
        }
        guard isEnabled else {
            consumed = true
            origin = nil
            return nil
        }
        guard !consumed else { return nil }
        guard contacts.count == 4 else {
            if origin != nil || contacts.count > 4 { consumed = true }
            return nil
        }
        guard contacts
            .allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0 ... 1).contains($0.x) && (0 ... 1).contains($0.y) }),
            Set(contacts.map(\.id)).count == 4
        else {
            consumed = true
            return nil
        }
        guard let origin else {
            self.origin = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, $0) })
            return nil
        }
        guard contacts.allSatisfy({ origin[$0.id] != nil }) else {
            consumed = true
            return nil
        }
        let displacements = contacts.compactMap { contact in
            origin[contact.id].map { CGPoint(x: contact.x - $0.x, y: contact.y - $0.y) }
        }
        guard let direction = Self.direction(for: displacements) else { return nil }
        consumed = true
        return direction
    }

    private static func direction(for displacements: [CGPoint]) -> Direction? {
        let dx = displacements.reduce(0) { $0 + $1.x } / 4
        let dy = displacements.reduce(0) { $0 + $1.y } / 4
        let horizontal = abs(dx) > abs(dy) * 1.4
        let vertical = abs(dy) > abs(dx) * 1.4
        guard (horizontal && abs(dx) >= 0.12) || (vertical && abs(dy) >= 0.12) else { return nil }
        // All four fingers must move together; a pinch or rotating hand is not a swipe.
        let travel = horizontal ? dx : dy
        guard displacements.allSatisfy({
            let component = horizontal ? $0.x : $0.y
            return component * (travel > 0 ? 1 : -1) >= 0.06
        }) else { return nil }
        return horizontal ? (dx < 0 ? .left : .right) : (dy < 0 ? .down : .up)
    }

    static func command(for direction: Direction) -> HotkeyCommand {
        switch direction {
        case .left,
             .right: .focus(direction)
        case .up: .focusWindowOrWorkspaceUp
        case .down: .focusWindowOrWorkspaceDown
        }
    }
}
