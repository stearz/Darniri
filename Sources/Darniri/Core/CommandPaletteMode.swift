import Foundation

enum CommandPaletteMode: String, CaseIterable, Codable {
    case windows

    var displayName: String {
        switch self {
        case .windows: "Windows"
        }
    }
}
