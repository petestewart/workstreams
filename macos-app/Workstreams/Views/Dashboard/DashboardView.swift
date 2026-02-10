import SwiftUI

struct DashboardView: View {
    let appState: AppState
    let cliBridge: CLIBridge?
    @State private var selectedProject: String?
    @State private var showOverview = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                appState: appState,
                selectedProject: $selectedProject,
                showOverview: $showOverview
            )
        } detail: {
            if showOverview {
                Text("Overview Grid — coming in Phase 6")
                    .foregroundStyle(.secondary)
            } else if let name = selectedProject,
                      let project = appState.state.projects[name] {
                ProjectDetailView(project: project, appState: appState, cliBridge: cliBridge)
            } else {
                Text("Select a project")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
