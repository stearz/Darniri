import Foundation

enum MonitorAssignment: Equatable, Hashable {
    case main
    case secondary
    case specificDisplay(OutputId)

    var displayName: String {
        switch self {
        case .main: "Main"
        case .secondary: "Secondary"
        case let .specificDisplay(output): output.name
        }
    }

    func toMonitorDescription() -> MonitorDescription {
        switch self {
        case .main: return .main
        case .secondary: return .secondary
        case let .specificDisplay(output): return .output(output)
        }
    }
}

extension MonitorAssignment: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, output
    }

    private enum AssignmentType: String, Codable {
        case main, secondary, specificDisplay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(AssignmentType.self, forKey: .type)
        switch type {
        case .main: self = .main
        case .secondary: self = .secondary
        case .specificDisplay:
            let output = try container.decode(OutputId.self, forKey: .output)
            self = .specificDisplay(output)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .main:
            try container.encode(AssignmentType.main, forKey: .type)
        case .secondary:
            try container.encode(AssignmentType.secondary, forKey: .type)
        case let .specificDisplay(output):
            try container.encode(AssignmentType.specificDisplay, forKey: .type)
            try container.encode(output, forKey: .output)
        }
    }
}

struct WorkspaceConfiguration: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var displayName: String?
    var monitorAssignment: MonitorAssignment

    var effectiveDisplayName: String {
        displayName.flatMap { $0.isEmpty ? nil : $0 } ?? name
    }

    init(
        id: UUID = UUID(),
        name: String,
        displayName: String? = nil,
        monitorAssignment: MonitorAssignment = .main
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.monitorAssignment = monitorAssignment
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, displayName, monitorAssignment
    }

    // Hand-authored entries only need `name`. A missing `id` is generated so
    // users never have to mint UUIDs themselves, and `monitorAssignment`
    // defaults to the main display when omitted.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        monitorAssignment = try container.decodeIfPresent(MonitorAssignment.self, forKey: .monitorAssignment) ?? .main
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encode(monitorAssignment, forKey: .monitorAssignment)
    }

    var sortOrder: Int {
        WorkspaceIDPolicy.workspaceNumber(from: name) ?? .max
    }
}
