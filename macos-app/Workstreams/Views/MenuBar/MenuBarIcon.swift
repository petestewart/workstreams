import SwiftUI

struct MenuBarIcon: View {
    let appState: AppState

    var body: some View {
        Image(systemName: "circle.fill")
            .foregroundStyle(iconColor)
            .symbolRenderingMode(.palette)
    }

    private var iconColor: Color {
        guard let project = appState.focusedProject else {
            return .gray
        }
        return project.color.swiftUIColor
    }
}
