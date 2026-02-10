import SwiftUI

struct DashboardView: View {
    let appState: AppState
    let cliBridge: CLIBridge?
    var windowDetector: WindowDetector?
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
                OverviewGridView(
                    appState: appState,
                    cliBridge: cliBridge,
                    selectedProject: $selectedProject,
                    showOverview: $showOverview
                )
            } else if let name = selectedProject,
                      let project = appState.state.projects[name] {
                ProjectDetailView(
                    project: project,
                    appState: appState,
                    cliBridge: cliBridge,
                    windowDetector: windowDetector
                )
            } else {
                Text("Select a project")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
