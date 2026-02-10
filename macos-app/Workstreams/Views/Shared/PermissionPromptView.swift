import SwiftUI

struct PermissionPromptView: View {
    let appState: AppState

    var body: some View {
        if !appState.hasAccessibilityPermission || !appState.hasAutomationPermission {
            VStack(alignment: .leading, spacing: 12) {
                Label("Permissions needed for window detection", systemImage: "lock.shield")
                    .font(.headline)

                if !appState.hasAccessibilityPermission {
                    PermissionRow(
                        title: "Accessibility",
                        description: "Required for window detection",
                        isGranted: false
                    )
                }

                if !appState.hasAutomationPermission {
                    PermissionRow(
                        title: "Automation",
                        description: "Required for iTerm and Chrome detection (granted automatically on first use)",
                        isGranted: false
                    )
                }

                Text("Without permissions, the app will show project status from the state file but cannot detect open windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                #if canImport(AppKit)
                if !appState.hasAccessibilityPermission {
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                #endif
            }
            .padding()
            .background(.yellow.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.yellow.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isGranted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
