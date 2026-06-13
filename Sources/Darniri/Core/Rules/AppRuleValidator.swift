import Foundation

enum AppRuleValidator {
    private static let appIdentifierPattern = try! NSRegularExpression(
        pattern: "^[a-zA-Z0-9]+([.-][a-zA-Z0-9]+)*$"
    )

    static func bundleIdError(for bundleId: String) -> String? {
        let trimmed = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Bundle ID is required"
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard appIdentifierPattern.firstMatch(in: trimmed, range: range) != nil else {
            return "Invalid bundle ID format"
        }
        return nil
    }

    static func invalidRegexMessage(for pattern: String?) -> String? {
        guard let pattern = pattern?.trimmingCharacters(in: .whitespacesAndNewlines), !pattern.isEmpty else {
            return nil
        }

        do {
            _ = try NSRegularExpression(pattern: pattern)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
