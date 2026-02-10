# App Lifecycle

Initialization sequence, subsystem startup, polling lifecycle, and dashboard visibility management.

## App Entry Point

```swift
@main
struct WorkstreamsApp: App {
    @State private var appState = AppState()
    @State private var stateMonitor: StateMonitor?
    @State private var cliBridge: CLIBridge?
    @State private var windowDetector: WindowDetector?
    @State private var portChecker: PortChecker?
    @State private var processMonitor: ProcessMonitor?

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
            DashboardView(appState: appState, cliBridge: cliBridge)
                .onAppear { onDashboardOpen() }
                .onDisappear { onDashboardClose() }
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
        }
    }
}
```

## Startup Sequence

All subsystems initialize at app launch. Order matters.

```
App launch
  1. AppState created (empty, in-memory)
  2. StateMonitor.start()          ← Loads state.json, begins file watching
  3. CLIBridge.discoverCLI()       ← Finds ws binary (async, non-blocking)
  4. Check permissions              ← AXIsProcessTrusted(), test AppleScript
  5. WindowDetector created         ← But NOT polling yet
  6. PortChecker created            ← But NOT checking yet
  7. ProcessMonitor created         ← Ready, no work until detection runs
  8. Start reduced-rate polling     ← 30s interval for menu bar indicators
```

### Why Start Polling at Launch?

The menu bar icon needs window counts and signals (Claude active, server running) even when the dashboard is closed. A reduced-rate poll (30s) keeps the menu bar dropdown useful without burning CPU.

```swift
// In App init or .task modifier:
.task {
    stateMonitor = StateMonitor(appState: appState)
    stateMonitor?.start()

    cliBridge = CLIBridge(appState: appState)
    await cliBridge?.discoverCLI()

    let perms = await WindowDetector.checkPermissions()
    await MainActor.run {
        appState.hasAccessibilityPermission = perms.accessibility
        appState.hasAutomationPermission = perms.automation
    }

    processMonitor = ProcessMonitor(appState: appState)
    portChecker = PortChecker(appState: appState)
    windowDetector = WindowDetector(
        appState: appState,
        processMonitor: processMonitor!,
        portChecker: portChecker!
    )
    windowDetector?.startPolling(interval: .reducedRate)  // 30s
}
```

## Polling Lifecycle

Two polling rates based on UI visibility:

| State | Interval | Rationale |
|-------|----------|-----------|
| Dashboard open | 7 seconds | User is actively viewing window details |
| Menu bar dropdown open | 7 seconds | User is looking at project list |
| Both closed (menu-bar-only) | 30 seconds | Ambient awareness without CPU cost |

### Visibility Tracking

```swift
enum PollingRate {
    case fullRate      // 7s — dashboard or dropdown visible
    case reducedRate   // 30s — menu-bar-only mode

    var interval: TimeInterval {
        switch self {
        case .fullRate: return 7
        case .reducedRate: return 30
        }
    }
}
```

The app tracks two visibility flags:

```swift
// In WorkstreamsApp:
@State private var isDashboardOpen = false
@State private var isDropdownOpen = false

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
    windowDetector?.detectOnce()  // Immediate refresh on open
}

private func onMenuBarDropdownClose() {
    isDropdownOpen = false
    if !isDashboardOpen {
        windowDetector?.startPolling(interval: .reducedRate)
    }
}
```

### Polling Rate Changes

`WindowDetector.startPolling(interval:)` cancels the existing polling task and restarts with the new interval. No data is lost — the next poll fires at the new rate.

```swift
func startPolling(interval rate: PollingRate) {
    guard currentRate != rate || !isPolling else { return }
    stopPolling()
    currentRate = rate
    isPolling = true

    pollingTask = Task { [weak self] in
        while !Task.isCancelled {
            guard let self else { return }
            await self.detectOnce()
            try? await Task.sleep(for: .seconds(rate.interval))
        }
    }
}
```

## Dashboard Window State

**Decision**: Remember window position and size between launches.

Use SwiftUI's built-in `WindowGroup` state restoration. On macOS 15, `Window` scenes automatically persist frame via the window's `id`. No manual UserDefaults code needed — the system handles it as long as the window has a stable identifier (`"dashboard"`).

If the automatic restoration doesn't work reliably, fall back to:

```swift
// Manual persistence via NSWindow delegate
@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Restore window frame from UserDefaults if needed
    }
}
```

## State File Missing on First Launch

If `~/.workstreams/state.json` doesn't exist:

1. StateMonitor's `Data(contentsOf:)` throws → all retries fail
2. `AppState.state` stays at the initial empty value: `WorkstreamsState(projects: [:], currentFocus: nil)`
3. `AppState.stateLoadError` is set to "Cannot read state file"
4. UI shows: "No projects found. Run `ws add <project>` to get started."
5. StateMonitor switches to polling fallback (2s) to detect when the file appears
6. Once the file is created by the CLI, the next poll picks it up and the UI populates

No crash. No empty error. A helpful message guiding the user to the CLI.

## Projects with Missing Paths

**Decision**: Show with a warning indicator; don't remove.

```swift
extension Project {
    var pathExists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
```

In the UI:
- Sidebar: project name with a ⚠️ badge
- Detail: "Path not found: ~/Projects/old-thing" with a "Rescan" button that calls `cliBridge.rescan(name)`
- Window detection: skip projects with missing paths (no point querying AppleScript for non-existent directories)

## Permission Re-checking

Check permissions periodically to detect when user grants them:

```swift
// In the polling loop or a separate timer:
private func recheckPermissions() async {
    let perms = await WindowDetector.checkPermissions()
    await MainActor.run {
        appState.hasAccessibilityPermission = perms.accessibility
        appState.hasAutomationPermission = perms.automation
    }
}
```

- Re-check every 30 seconds (aligned with reduced-rate polling)
- When a permission transitions from `false` to `true`, trigger an immediate full detection pass
- When both permissions are granted, stop re-checking (save the syscall overhead)

## CLI Binary Re-discovery

CLIBridge attempts discovery once at launch. If it fails:

1. `appState.cliPath` is nil, `appState.cliError` is set
2. UI shows "ws CLI not found" in menu bar dropdown and dashboard
3. Action buttons (Focus, Park) are disabled
4. User opens Settings → configures path manually → CLIBridge re-validates
5. OR: CLIBridge re-attempts discovery when the user clicks "Retry" in the error banner

**No automatic periodic re-discovery.** The CLI binary location doesn't change at runtime in normal usage. If the user installs `ws` after launching the app, they click "Retry" or set the path in Settings.

```swift
// In CLIBridge:
func retryDiscovery() async {
    await MainActor.run {
        appState.cliError = nil
    }
    await discoverCLI()
}
```

## App Termination

```swift
// In App or AppDelegate:
func applicationWillTerminate(_ notification: Notification) {
    stateMonitor?.stop()
    windowDetector?.stopPolling()
    // No state to save — all state lives in state.json
    // UserDefaults (settings) auto-persist
}
```

Clean shutdown: cancel DispatchSource, cancel polling tasks, close file descriptors. No data loss risk since the app never writes to state.json.

## Subsystem Dependency Graph

```
AppState (shared, @Observable)
    ↑ writes to
    ├── StateMonitor (independent, starts first)
    ├── CLIBridge (independent, starts second)
    ├── WindowDetector (depends on AppState for project list)
    │       ├── uses ProcessMonitor (per-session enrichment)
    │       └── uses PortChecker (per-project probing)
    └── UI Views (read AppState, call CLIBridge for actions)
```

No circular dependencies. Subsystems only communicate through AppState. WindowDetector reads the project list from AppState (populated by StateMonitor) and writes detection results back.

---
*Addresses the initialization, lifecycle, and visibility gaps identified in the spec review*
