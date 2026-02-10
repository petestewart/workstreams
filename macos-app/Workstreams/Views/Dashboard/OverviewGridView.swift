import SwiftUI

struct OverviewGridView: View {
    let appState: AppState
    let cliBridge: CLIBridge?
    @Binding var selectedProject: String?
    @Binding var showOverview: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 350))
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(appState.activeProjects + appState.parkedProjects) { project in
                    ProjectCard(
                        project: project,
                        appState: appState,
                        cliBridge: cliBridge,
                        onNavigate: {
                            selectedProject = project.name
                            showOverview = false
                        }
                    )
                }
            }
            .padding()
        }
        .navigationTitle("All Projects")
    }
}

struct ProjectCard: View {
    let project: Project
    let appState: AppState
    let cliBridge: CLIBridge?
    let onNavigate: () -> Void
    @State private var isLoading = false

    private var isFocused: Bool {
        appState.state.currentFocus == project.name
    }

    private var isParked: Bool {
        project.status == .parked
    }

    var body: some View {
        Button(action: onNavigate) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle()
                        .fill(project.color.swiftUIColor)
                        .frame(width: 10, height: 10)
                    Text(project.name)
                        .font(.headline)
                    Spacer()
                    StatusBadge(status: project.status, isFocused: isFocused)
                }

                // Signals
                VStack(alignment: .leading, spacing: 4) {
                    if let windows = appState.windowsByProject[project.name] {
                        Label("\(windows.count) window\(windows.count == 1 ? "" : "s")", systemImage: "macwindow")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let claudeSession = windows.first(where: { isClaudeActive($0) }) {
                            Label("Claude active", systemImage: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    if let ports = appState.portStatusByProject[project.name] {
                        ForEach(ports.filter(\.isListening)) { port in
                            Label("localhost:\(port.port)", systemImage: "network")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                // Action buttons
                if !isFocused {
                    HStack(spacing: 8) {
                        Button {
                            focusProject()
                        } label: {
                            Text("Focus")
                                .font(.caption)
                        }
                        .disabled(isLoading)
                    }
                }
            }
            .padding(12)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFocused ? project.color.swiftUIColor : .separator, lineWidth: isFocused ? 2 : 1)
            )
            .opacity(isParked ? 0.6 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func isClaudeActive(_ match: WindowMatch) -> Bool {
        if case .iterm(let m) = match, let info = m.processInfo {
            if case .claudeCode = info.type { return true }
        }
        return false
    }

    private func focusProject() {
        guard let cliBridge else { return }
        isLoading = true
        Task {
            do {
                if project.status == .parked {
                    try await cliBridge.unpark(project.name)
                }
                try await cliBridge.focus(project.name)
            } catch {
                // Error handled by state update
            }
            isLoading = false
        }
    }
}
