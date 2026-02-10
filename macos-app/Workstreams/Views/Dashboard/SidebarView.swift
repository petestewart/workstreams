import SwiftUI

struct SidebarView: View {
    let appState: AppState
    @Binding var selectedProject: String?
    @Binding var showOverview: Bool

    var body: some View {
        List(selection: $selectedProject) {
            Button {
                showOverview = true
                selectedProject = nil
            } label: {
                Label("All Projects", systemImage: "square.grid.2x2")
            }

            Section("Active") {
                ForEach(appState.activeProjects) { project in
                    SidebarRow(
                        project: project,
                        isFocused: project.name == appState.state.currentFocus
                    )
                    .tag(project.name)
                }
            }

            if !appState.parkedProjects.isEmpty {
                Section("Parked") {
                    ForEach(appState.parkedProjects) { project in
                        SidebarRow(project: project, isFocused: false)
                            .tag(project.name)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Projects")
        .onChange(of: selectedProject) { _, newValue in
            if newValue != nil {
                showOverview = false
            }
        }
    }
}

struct SidebarRow: View {
    let project: Project
    let isFocused: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(project.color.swiftUIColor)
                .frame(width: 8, height: 8)
            Text(project.name)
                .fontWeight(isFocused ? .semibold : .regular)
            if !project.pathExists {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
            if isFocused {
                Spacer()
                Image(systemName: "eye.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}
