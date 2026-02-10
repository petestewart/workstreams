import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    let appState: AppState
    let cliBridge: CLIBridge?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProjectHeaderView(project: project, appState: appState, cliBridge: cliBridge)

                Divider()

                ProjectMetadataView(project: project)

                // Windows section placeholder (Phase 4)
                // Ports section placeholder (Phase 5)

                HistorySection(entries: Array(project.history.suffix(5)))
            }
            .padding()
        }
        .navigationTitle(project.name)
    }
}

// MARK: - Header

struct ProjectHeaderView: View {
    let project: Project
    let appState: AppState
    let cliBridge: CLIBridge?
    @State private var isLoading = false
    @State private var actionError: String?

    private var isFocused: Bool {
        appState.state.currentFocus == project.name
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(project.color.swiftUIColor)
                        .frame(width: 14, height: 14)
                    Text(project.name)
                        .font(.title)
                        .fontWeight(.bold)
                }

                HStack(spacing: 8) {
                    StatusBadge(status: project.status, isFocused: isFocused)
                    if let note = project.parkedNote {
                        Text("\"\(note)\"")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !project.pathExists {
                    Label("Path not found: \(project.path)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if project.status == .parked {
                    ActionButton(label: "Unpark", isLoading: isLoading) {
                        await performAction { try await cliBridge?.unpark(project.name) }
                    }
                }

                if !isFocused {
                    ActionButton(label: "Focus", isLoading: isLoading) {
                        await performAction {
                            if project.status == .parked {
                                try await cliBridge?.unpark(project.name)
                            }
                            try await cliBridge?.focus(project.name)
                        }
                    }
                }
            }
        }

        if let error = actionError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .transition(.opacity)
        }
    }

    private func performAction(_ action: @escaping () async throws -> Void) async {
        isLoading = true
        actionError = nil
        do {
            try await action()
        } catch {
            actionError = error.localizedDescription
            Task {
                try? await Task.sleep(for: .seconds(5))
                actionError = nil
            }
        }
        isLoading = false
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let label: String
    let isLoading: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(label)
            }
        }
        .disabled(isLoading)
    }
}

// MARK: - Metadata

struct ProjectMetadataView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetadataRow(label: "Path", value: project.path)

            if let remote = project.signatures.gitRemote {
                MetadataRow(label: "Git Remote", value: remote)
            }

            if let database = project.signatures.database {
                MetadataRow(label: "Database", value: database)
            }

            if !project.signatures.urlPatterns.isEmpty {
                MetadataRow(label: "URL Patterns", value: project.signatures.urlPatterns.joined(separator: ", "))
            }

            if !project.signatures.ports.isEmpty {
                MetadataRow(label: "Ports", value: project.signatures.ports.map(String.init).joined(separator: ", "))
            }
        }
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }
}

// MARK: - History

struct HistorySection: View {
    let entries: [HistoryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.headline)

            if entries.isEmpty {
                Text("No history yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries.reversed()) { entry in
                    HistoryRow(entry: entry)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack {
            Text("•")
                .foregroundStyle(.secondary)
            Text(actionLabel)
            if let note = entry.note {
                Text("\"\(note)\"")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(timeAgo(from: entry.at))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var actionLabel: String {
        switch entry.action {
        case .added: return "Added"
        case .focused: return "Focused"
        case .parked: return "Parked"
        case .unparked: return "Unparked"
        case .unknown(let raw): return raw.capitalized
        }
    }
}
