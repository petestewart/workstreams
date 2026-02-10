import SwiftUI

@main
struct WorkstreamsApp: App {
    @State private var appState = AppState()
    @State private var stateMonitor: StateMonitor?
    @State private var cliBridge: CLIBridge?

    var body: some Scene {
        MenuBarExtra {
            MenuBarDropdown(appState: appState, cliBridge: cliBridge)
        } label: {
            MenuBarIcon(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Window("Workstreams", id: "dashboard") {
            DashboardView(appState: appState, cliBridge: cliBridge)
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
        }
    }

    init() {
        let state = AppState()
        _appState = State(initialValue: state)

        let monitor = StateMonitor(appState: state)
        _stateMonitor = State(initialValue: monitor)

        let bridge = CLIBridge(appState: state)
        _cliBridge = State(initialValue: bridge)

        monitor.start()

        Task {
            await bridge.discoverCLI()
        }
    }
}
