import Foundation

struct HistoryEntry: Codable, Identifiable {
    let id = UUID()
    let action: HistoryAction
    let note: String?
    let at: Date

    enum CodingKeys: String, CodingKey {
        case action, note, at
    }
}

enum HistoryAction: Codable {
    case added, focused, parked, unparked
    case unknown(String)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "added": self = .added
        case "focused": self = .focused
        case "parked": self = .parked
        case "unparked": self = .unparked
        default: self = .unknown(raw)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .added: try container.encode("added")
        case .focused: try container.encode("focused")
        case .parked: try container.encode("parked")
        case .unparked: try container.encode("unparked")
        case .unknown(let raw): try container.encode(raw)
        }
    }
}
