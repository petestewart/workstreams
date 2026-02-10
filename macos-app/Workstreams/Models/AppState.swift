import SwiftUI

@MainActor
@Observable
final class AppState {
    // From StateMonitor
    var state: WorkstreamsState = WorkstreamsState(projects: [:], currentFocus: nil)
    var stateLoadError: String?

    // From WindowDetector
    var windowsByProject: [String: [WindowMatch]] = [:]

    // From PortChecker
    var portStatusByProject: [String: [PortStatus]] = [:]

    // From CLIBridge
    var cliPath: String?
    var cliError: String?

    // Permissions
    var hasAccessibilityPermission: Bool = false
    var hasAutomationPermission: Bool = false

    // Derived
    var focusedProject: Project? {
        guard let name = state.currentFocus else { return nil }
        return state.projects[name]
    }

    var activeProjects: [Project] {
        state.projects.values
            .filter { $0.status == .active }
            .sorted { $0.name < $1.name }
    }

    var parkedProjects: [Project] {
        state.projects.values
            .filter { $0.status == .parked }
            .sorted { $0.name < $1.name }
    }
}
