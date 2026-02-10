import Foundation

struct Project: Codable, Identifiable {
    var id: String { name }

    let name: String
    let path: String
    var color: ProjectColor
    var status: ProjectStatus
    var parkedNote: String?
    var parkedAt: Date?
    var signatures: ProjectSignatures
    var history: [HistoryEntry]

    enum CodingKeys: String, CodingKey {
        case name, path, color, status, signatures, history
        case parkedNote = "parked_note"
        case parkedAt = "parked_at"
    }

    var pathExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
