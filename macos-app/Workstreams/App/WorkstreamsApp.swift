import SwiftUI

@main
struct WorkstreamsApp: App {
    @State private var appState = AppState()
    @State private var stateMonitor: StateMonitor?
    @State private var cliBridge: CLIBridge?
    @State private var windowDetector: WindowDetector?
    @State private var isDashboardOpen = false
    @State private var isDropdownOpen = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarDropdown(appState: appState, cliBridge: cliBridge)
                .onAppear { onMenuBarDropdownOpen() }
                .onDisappear { onMenuBarDropdownClose() }
        } label: {
            MenuBarIcon(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Window("Workstreams", id: "dashboard") {
            DashboardView(
                appState: appState,
                cliBridge: cliBridge,
                windowDetector: windowDetector
            )
            .onAppear { onDashboardOpen() }
            .onDisappear { onDashboardClose() }
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

        let detector = WindowDetector(appState: state)
        _windowDetector = State(initialValue: detector)

        monitor.start()
        detector.startPolling(interval: .reducedRate)

        Task {
            await bridge.discoverCLI()

            let perms = await WindowDetector.checkPermissions()
            await MainActor.run {
                state.hasAccessibilityPermission = perms.accessibility
                state.hasAutomationPermission = perms.automation
            }
        }
    }

    private func onDashboardOpen() {
        isDashboardOpen = true
        windowDetector?.startPolling(interval: .fullRate)
    }

    private func onDashboardClose() {
        isDashboardOpen = false
        if !isDropdownOpen {
            windowDetector?.startPolling(interval: .reducedRate)
        }
    }

    private func onMenuBarDropdownOpen() {
        isDropdownOpen = true
        windowDetector?.startPolling(interval: .fullRate)
        Task { await windowDetector?.detectOnce() }
    }

    private func onMenuBarDropdownClose() {
        isDropdownOpen = false
        if !isDashboardOpen {
            windowDetector?.startPolling(interval: .reducedRate)
        }
    }
}
