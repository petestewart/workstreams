import SwiftUI

enum ProjectColor: String, Codable, CaseIterable {
    case red, blue, green, yellow, magenta, cyan, white

    var swiftUIColor: Color {
        switch self {
        case .red: return .red
        case .blue: return .blue
        case .green: return .green
        case .yellow: return .yellow
        case .magenta: return .purple
        case .cyan: return .cyan
        case .white: return .white
        }
    }
}
