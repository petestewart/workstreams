import Foundation

struct WorkstreamsState: Codable {
    var projects: [String: Project]
    var currentFocus: String?

    enum CodingKeys: String, CodingKey {
        case projects
        case currentFocus = "current_focus"
    }
}
