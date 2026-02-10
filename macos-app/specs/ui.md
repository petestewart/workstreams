# UI Specification

SwiftUI views for the menu bar, dashboard window, overview grid, settings, and permissions flow.

## App Entry Point

```swift
@main
struct WorkstreamsApp: App {
    @State private var appState = AppState()
    @State private var stateMonitor: StateMonitor?
    @State private var cliBridge: CLIBridge?
    @State private var windowDetector: WindowDetector?

    var body: some Scene {
        // Menu bar (always present)
        MenuBarExtra {
            MenuBarDropdown(appState: appState, cliBridge: cliBridge)
        } label: {
            MenuBarIcon(appState: appState)
        }
        .menuBarExtraStyle(.window)

        // Dashboard window (opened from menu bar)
        Window("Workstreams", id: "dashboard") {
            DashboardView(appState: appState, cliBridge: cliBridge)
        }
        .defaultSize(width: 900, height: 600)
    }
}
```

> **Note**: This is a simplified view hierarchy. Full initialization logic, subsystem startup, and polling lifecycle management are in [app-lifecycle.md](./app-lifecycle.md).

### LSUIElement

Set in `Info.plist`:

```xml
<key>LSUIElement</key>
<true/>
```

This hides the app from the Dock. The menu bar icon is the only persistent UI element.

---

## Menu Bar

### Menu Bar Icon

An SF Symbol circle filled with the focused project's color.

```swift
struct MenuBarIcon: View {
    let appState: AppState

    var body: some View {
        Image(systemName: "circle.fill")
            .foregroundStyle(iconColor)
            .symbolRenderingMode(.palette)
    }

    private var iconColor: Color {
        guard let project = appState.focusedProject else {
            return .gray
        }
        return project.color.swiftUIColor
    }
}
```

**States:**
- Focused project → project's color
- No focus → gray
- State load error → gray with exclamation badge (optional, Phase 6 polish)

### Menu Bar Dropdown

`.menuBarExtraStyle(.window)` renders the dropdown as a custom SwiftUI view (not a standard NSMenu), allowing richer layout.

```
┌─────────────────────────────────┐
│  ● my-project (focused)         │  ← Current focus header
│  Path: ~/Projects/my-project    │
├─────────────────────────────────┤
│  ACTIVE                         │
│  ○ project-alpha                │  ← Click to focus
│  ○ project-beta                 │
├─────────────────────────────────┤
│  PARKED                         │
│  ○ old-project  "needs review"  │  ← Parked note shown
│  ○ side-thing   "waiting on API"│
├─────────────────────────────────┤
│  Open Dashboard    ⌘D           │
│  Quit              ⌘Q           │
└─────────────────────────────────┘
```

#### Interactions

- **Click active project** → calls `cliBridge.focus(name)`. State file updates, StateMonitor picks up the change, icon color updates.
- **Click parked project** → calls `cliBridge.unpark(name)` then `cliBridge.focus(name)`.
- **Open Dashboard** → opens the `Window("Workstreams", id: "dashboard")` scene via `OpenWindowAction`.
- **Quit** → `NSApplication.shared.terminate(nil)`.

#### Quick Focus Feedback

After clicking a project, show a brief checkmark or loading spinner next to the project name while the CLI executes. On success, the StateMonitor will update AppState and the view will reflect the new focus. On failure, show the error inline.

---

## Dashboard Window

### Layout: NavigationSplitView

```
┌──────────────────┬──────────────────────────────────────┐
│  SIDEBAR          │  DETAIL                              │
│                   │                                      │
│  ★ All Projects   │  (depends on sidebar selection)      │
│                   │                                      │
│  ACTIVE           │                                      │
│  ● my-project     │                                      │
│  ● project-alpha  │                                      │
│                   │                                      │
│  PARKED           │                                      │
│  ○ old-project    │                                      │
│  ○ side-thing     │                                      │
│                   │                                      │
└──────────────────┴──────────────────────────────────────┘
```

```swift
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
                OverviewGrid(appState: appState, cliBridge: cliBridge)
            } else if let name = selectedProject,
                      let project = appState.state.projects[name] {
                ProjectDetail(project: project, appState: appState, cliBridge: cliBridge)
            } else {
                Text("Select a project")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

### Sidebar

```swift
struct SidebarView: View {
    let appState: AppState
    @Binding var selectedProject: String?
    @Binding var showOverview: Bool

    var body: some View {
        List(selection: $selectedProject) {
            // Overview row
            Button { showOverview = true; selectedProject = nil } label: {
                Label("All Projects", systemImage: "square.grid.2x2")
            }

            // Active section
            Section("Active") {
                ForEach(appState.activeProjects) { project in
                    SidebarRow(project: project, isFocused: project.name == appState.state.currentFocus)
                        .tag(project.name)
                }
            }

            // Parked section
            Section("Parked") {
                ForEach(appState.parkedProjects) { project in
                    SidebarRow(project: project, isFocused: false)
                        .tag(project.name)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Projects")
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
            if isFocused {
                Spacer()
                Image(systemName: "eye.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}
```

### Project Detail

```swift
struct ProjectDetail: View {
    let project: Project
    let appState: AppState
    let cliBridge: CLIBridge?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                ProjectHeader(project: project, appState: appState, cliBridge: cliBridge)

                Divider()

                // Metadata
                ProjectMetadata(project: project)

                // Windows (Phase 4)
                if let windows = appState.windowsByProject[project.name], !windows.isEmpty {
                    WindowListView(windows: windows, project: project)
                } else if !appState.hasAccessibilityPermission {
                    PermissionPrompt(type: .accessibility)
                }

                // Ports (Phase 5)
                if let ports = appState.portStatusByProject[project.name], !ports.isEmpty {
                    PortStatusView(ports: ports)
                }

                // History
                HistoryView(entries: Array(project.history.suffix(5)))
            }
            .padding()
        }
        .navigationTitle(project.name)
    }
}
```

#### Project Header

```
┌──────────────────────────────────────────────────────────┐
│  ● my-project                              [Focus] [Park]│
│  Active                                                   │
└──────────────────────────────────────────────────────────┘
```

- Color dot + name (large, bold)
- Status badge: "Active" (green) or "Parked" (yellow) with parked note
- Action buttons:
  - **Focus** → `cliBridge.focus(name)` (hidden if already focused)
  - **Park** → shows text field for note, then `cliBridge.park(name, note)`
  - **Unpark** → `cliBridge.unpark(name)` (shown when parked)

#### Project Metadata

```
Path:         ~/Projects/my-project
Git Remote:   github.com/org/my-project
Database:     my_project_development
URL Patterns: github.com/org/my-project, localhost:3000
Ports:        3000, 5432
```

Simple key-value layout. Values are selectable text (for copy-paste). Path is clickable → opens in Finder.

#### Window List View (Phase 4)

Windows grouped by app, each as a clickable card:

```
iTerm (3 sessions)
┌─────────────────────────────────────────────┐
│ 📁 my-project — zsh                         │ ← Click to activate
│    Claude: active (12m)                      │ ← Process info (Phase 5)
├─────────────────────────────────────────────┤
│ 📁 my-project — server                      │
│    node (running 1h 23m)                     │
├─────────────────────────────────────────────┤
│ 📁 my-project — shell                       │
│    Shell: idle                               │
└─────────────────────────────────────────────┘

Chrome (2 tabs)
┌─────────────────────────────────────────────┐
│ 🌐 Pull Request #42 - my-project            │
│    github.com/org/my-project/pull/42         │
├─────────────────────────────────────────────┤
│ 🌐 my-project Dashboard                     │
│    localhost:3000/dashboard                  │
└─────────────────────────────────────────────┘

VS Code (1 window)
┌─────────────────────────────────────────────┐
│ 💻 my-project — Visual Studio Code           │
└─────────────────────────────────────────────┘
```

Each card is a `Button` that calls the appropriate activation method from `WindowDetector`.

#### Port Status View (Phase 5)

```
Ports
● localhost:3000  Listening
○ localhost:5432  Not listening
```

Green/red circles. Monospace port labels.

#### History View

```
History
• Focused                    2 minutes ago
• Unparked                   1 hour ago
• Parked  "waiting on API"   3 hours ago
• Focused                    yesterday
• Added                      3 days ago
```

Last 5 entries, reverse chronological. Relative timestamps using a `timeAgo()` function.

```swift
func timeAgo(from date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60 { return "just now" }
    if interval < 3600 { return "\(Int(interval / 60))m ago" }
    if interval < 86400 { return "\(Int(interval / 3600))h ago" }
    if interval < 172800 { return "yesterday" }
    return "\(Int(interval / 86400))d ago"
}
```

---

## Overview Grid

Bird's-eye view of all projects as a card grid.

```swift
struct OverviewGrid: View {
    let appState: AppState
    let cliBridge: CLIBridge?

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 350))
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(appState.activeProjects + appState.parkedProjects) { project in
                    ProjectCard(project: project, appState: appState)
                }
            }
            .padding()
        }
        .navigationTitle("All Projects")
    }
}
```

### Project Card

```
┌─────────────────────────────┐
│ ● my-project        Active  │
│                              │
│ 🖥 3 windows                 │
│ 🟢 Claude active             │
│ 🟢 localhost:3000             │
│                              │
│ [Focus]  [Park]              │
└─────────────────────────────┘
```

- Color-coded left border or header
- Project name + status badge
- Window count from `appState.windowsByProject`
- Key signals: Claude active, dev server running, ports listening
- Action buttons (Focus/Park)

Clicking the card body navigates to the project detail in the dashboard.

---

## Settings & Permissions

### Settings View

Accessible from the menu bar dropdown footer.

```swift
struct SettingsView: View {
    @AppStorage("cliPath") private var cliPath: String = ""
    @AppStorage("pollingInterval") private var pollingInterval: Double = 7.0

    var body: some View {
        Form {
            Section("CLI Binary") {
                TextField("Path to ws", text: $cliPath)
                Text("Leave empty to auto-detect")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }
}
```

Settings stored in `UserDefaults` via `@AppStorage`. Only the CLI path is configurable in Phase 6. Polling interval may be exposed later if users request it.

### Permissions Flow

On first launch (or when permissions are missing):

```
┌──────────────────────────────────────────────┐
│  Workstreams needs permissions to detect      │
│  your project windows.                        │
│                                               │
│  ☐ Accessibility                              │
│    Required for window detection              │
│    [Open System Settings]                     │
│                                               │
│  ☐ Automation                                 │
│    Required for iTerm and Chrome detection    │
│    (Granted automatically on first use)       │
│                                               │
│  Without permissions, the app will show       │
│  project status from the state file but       │
│  cannot detect open windows.                  │
└──────────────────────────────────────────────┘
```

- Check `AXIsProcessTrusted()` for Accessibility
- Automation permissions are granted per-app on first AppleScript execution
- "Open System Settings" button → `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`
- Re-check permissions periodically (every 30s) to detect when the user grants them

### Graceful Degradation

| Permission | Missing Behavior |
|------------|------------------|
| Accessibility | Window list shows "Grant Accessibility permission to detect windows" |
| Automation (iTerm) | iTerm section shows "Grant Automation permission for iTerm detection" |
| Automation (Chrome) | Chrome section shows similar message |
| Both missing | Project detail shows metadata and history only, no window list |
| CLI not found | Action buttons disabled, "ws CLI not found" shown in menu bar dropdown |

Never fail silently. Every missing capability gets a visible, actionable message.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘D | Open/focus Dashboard |
| ⌘Q | Quit |
| ⌘W | Close Dashboard window (returns to menu-bar-only) |
| ↑↓ | Navigate project list in sidebar |
| ⏎ | Focus selected project |

---

## Color Mapping

```swift
extension ProjectColor {
    var swiftUIColor: Color {
        switch self {
        case .red:     return .red
        case .blue:    return .blue
        case .green:   return .green
        case .yellow:  return .yellow
        case .magenta: return .purple
        case .cyan:    return .cyan
        case .white:   return .white
        }
    }
}
```

Note: `.magenta` maps to SwiftUI `.purple` (SwiftUI has no `.magenta`). `.white` may need a dark-mode-aware variant (white on white background).

---
*Covers Phases 2, 3, 6 — Menu Bar, Dashboard, Overview Grid, Settings, Permissions*
