import SwiftUI

struct MenuBarDropdown: View {
    let appState: AppState
    let cliBridge: CLIBridge?
    @Environment(\.openWindow) private var openWindow
    @State private var focusingProject: String?
    @State private var focusError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Current focus header
            if let project = appState.focusedProject {
                FocusedProjectHeader(project: project)
                Divider()
            }

            // CLI error banner
            if let error = appState.cliError {
                CLIErrorBanner(message: error, cliBridge: cliBridge)
                Divider()
            }

            // Active projects
            if !appState.activeProjects.isEmpty {
                SectionHeader(title: "ACTIVE")
                ForEach(appState.activeProjects) { project in
                    ProjectRow(
                        project: project,
                        isFocused: project.name == appState.state.currentFocus,
                        isFocusing: focusingProject == project.name,
                        onTap: { focusProject(project.name) }
                    )
                }
                Divider()
            }

            // Parked projects
            if !appState.parkedProjects.isEmpty {
                SectionHeader(title: "PARKED")
                ForEach(appState.parkedProjects) { project in
                    ParkedProjectRow(
                        project: project,
                        isFocusing: focusingProject == project.name,
                        onTap: { unparkAndFocus(project.name) }
                    )
                }
                Divider()
            }

            // State error
            if appState.state.projects.isEmpty, appState.stateLoadError != nil {
                Text("No projects found.\nRun `ws add <project>` to get started.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
            }

            // Focus error
            if let error = focusError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }

            // Footer actions
            Button {
                openWindow(id: "dashboard")
            } label: {
                HStack {
                    Text("Open Dashboard")
                    Spacer()
                    Text("⌘D")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Text("Quit")
                    Spacer()
                    Text("⌘Q")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 280)
        .padding(.vertical, 8)
    }

    private func focusProject(_ name: String) {
        guard let cliBridge, focusingProject == nil else { return }
        focusingProject = name
        focusError = nil

        Task {
            do {
                try await cliBridge.focus(name)
            } catch {
                focusError = error.localizedDescription
            }
            focusingProject = nil
        }
    }

    private func unparkAndFocus(_ name: String) {
        guard let cliBridge, focusingProject == nil else { return }
        focusingProject = name
        focusError = nil

        Task {
            do {
                try await cliBridge.unpark(name)
                try await cliBridge.focus(name)
            } catch {
                focusError = error.localizedDescription
            }
            focusingProject = nil
        }
    }
}

// MARK: - Subviews

private struct FocusedProjectHeader: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(project.color.swiftUIColor)
                    .frame(width: 10, height: 10)
                Text(project.name)
                    .font(.headline)
                Text("(focused)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(project.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

private struct ProjectRow: View {
    let project: Project
    let isFocused: Bool
    let isFocusing: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(project.color.swiftUIColor)
                    .frame(width: 8, height: 8)
                Text(project.name)
                    .fontWeight(isFocused ? .semibold : .regular)
                Spacer()
                if isFocusing {
                    ProgressView()
                        .controlSize(.small)
                } else if isFocused {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .disabled(isFocused || isFocusing)
    }
}

private struct ParkedProjectRow: View {
    let project: Project
    let isFocusing: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Circle()
                    .fill(project.color.swiftUIColor.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(project.name)
                    .foregroundStyle(.secondary)
                if let note = project.parkedNote {
                    Text("\"\(note)\"")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                if isFocusing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .disabled(isFocusing)
    }
}

private struct CLIErrorBanner: View {
    let message: String
    let cliBridge: CLIBridge?

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let cliBridge {
                Button("Retry") {
                    Task { await cliBridge.retryDiscovery() }
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
