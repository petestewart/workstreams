import SwiftUI

struct StatusBadge: View {
    let status: ProjectStatus
    let isFocused: Bool

    var body: some View {
        Text(label)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(Capsule())
    }

    private var label: String {
        if isFocused { return "Focused" }
        switch status {
        case .active: return "Active"
        case .parked: return "Parked"
        }
    }

    private var backgroundColor: Color {
        if isFocused { return .blue.opacity(0.15) }
        switch status {
        case .active: return .green.opacity(0.15)
        case .parked: return .yellow.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        if isFocused { return .blue }
        switch status {
        case .active: return .green
        case .parked: return .yellow
        }
    }
}
