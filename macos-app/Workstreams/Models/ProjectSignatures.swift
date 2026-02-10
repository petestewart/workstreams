import Foundation

struct ProjectSignatures: Codable {
    var gitRemote: String?
    var ports: [Int]
    var database: String?
    var urlPatterns: [String]

    enum CodingKeys: String, CodingKey {
        case ports, database
        case gitRemote = "git_remote"
        case urlPatterns = "url_patterns"
    }
}
