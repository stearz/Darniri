import Foundation

enum WorkspaceIDPolicy {
    static func normalizeRawID(_ candidate: String) -> String? {
        guard let value = Int(candidate), value > 0 else { return nil }
        let normalized = String(value)
        guard normalized == candidate else { return nil }
        return normalized
    }

    static func rawID(from workspaceNumber: Int) -> String? {
        guard workspaceNumber > 0 else { return nil }
        return String(workspaceNumber)
    }

    static func workspaceNumber(from rawID: String) -> Int? {
        guard let normalized = normalizeRawID(rawID) else { return nil }
        return Int(normalized)
    }

    static func lowestUnusedRawID<S: Sequence>(in rawIDs: S) -> String where S.Element == String {
        let usedNumbers = Set(rawIDs.compactMap(workspaceNumber(from:)))
        var candidate = 1
        while usedNumbers.contains(candidate) {
            candidate += 1
        }
        return String(candidate)
    }

    static func sortsBefore(_ lhs: String, _ rhs: String) -> Bool {
        switch (workspaceNumber(from: lhs), workspaceNumber(from: rhs)) {
        case let (lhs?, rhs?):
            return lhs < rhs
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }
}
