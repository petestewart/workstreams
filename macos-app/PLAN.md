# Plan: Workstreams macOS App (SwiftUI)

## Overview
Build a native SwiftUI macOS app that adds a project awareness layer on top of the existing Workstreams CLI and Raycast extension. The CLI answers "switch to project X", Raycast answers "which project do I want?" — the native app answers "what's happening across all my work right now?"

**Success criteria:**
- Menu bar icon with color-coded dot shows current focused project, dropdown for quick-switching
- Dashboard window shows project details, live detected windows, terminal process insight, port status
- Overview grid shows bird's-eye view of all projects at once
- App reads `~/.workstreams/state.json` directly, delegates writes to `ws` CLI
- Runs as menu-bar-primary app (no Dock icon), macOS 15+ (Sequoia)

## Architecture Reference
Full technical specifications in [`specs/`](./specs/README.md). Key specs: [data-model](./specs/data-model.md), [state-monitor](./specs/state-monitor.md), [cli-bridge](./specs/cli-bridge.md), [window-detection](./specs/window-detection.md), [terminal-insight](./specs/terminal-insight.md), [port-checker](./specs/port-checker.md), [ui](./specs/ui.md), [app-lifecycle](./specs/app-lifecycle.md), [error-handling](./specs/error-handling.md).

**Key architectural decisions:**
- Pure SwiftUI, targeting macOS 15+ for `@Observable` macro
- Located at `macos-app/` inside existing workstreams repo
- NSAppleScript for window detection (same logic as CLI's `src/focus/*.ts`)
- DispatchSource file watching for state.json changes
- LSUIElement=YES (menu bar primary, no Dock icon)
- No App Sandbox (needs AppleScript automation, subprocess execution, file system, network)
- Reads state.json directly, writes via CLI binary (same pattern as Raycast extension)

**Data flow:**
```
~/.workstreams/state.json ←writes— ws CLI ←called by— CLIBridge ←triggered by— UI actions
                          —reads→ StateMonitor (@Observable) —drives→ SwiftUI Views
WindowDetector (polling 7s) → NSAppleScript → publishes windowsByProject
ProcessMonitor → shell PID → child processes → enriches terminal cards
PortChecker → TCP probe localhost:port → green/red indicators
```

**File structure:**
```
macos-app/Workstreams/
├── App/WorkstreamsApp.swift
├── Models/ (7 files: state, project, color, status, signatures, history, window match)
├── Services/ (6 files: state monitor, window detector, CLI bridge, port checker, process monitor, AppleScript runner)
├── Views/MenuBar/ (2 files: icon, dropdown)
├── Views/Dashboard/ (13 files: layout, sidebar, detail, windows, terminal, ports, history, overview)
├── Views/Shared/ (2 files: status badge, time formatting)
└── Resources/Assets.xcassets
```

## Tasks

### Phase 1: Xcode Project + Data Models
- [x] **Create Xcode project structure** `[complete]`
  - Spec: [app-lifecycle.md](./specs/app-lifecycle.md) (LSUIElement, Info.plist), [specs/README.md](./specs/README.md) (constraints)
  - Scope: Create `macos-app/` directory, initialize Xcode project targeting macOS 15+, configure Info.plist (LSUIElement=YES, NSAppleEventsUsageDescription), disable App Sandbox
  - Acceptance: `xcodebuild build` succeeds with empty app

- [x] **Implement Codable model types** `[complete]`
  - Spec: [data-model.md](./specs/data-model.md) — all Swift types, CodingKeys, HistoryAction with `.unknown(String)` fallback, AppState `@Observable` class
  - Scope: WorkstreamsState, Project, ProjectColor (with SwiftUI Color mapping), ProjectStatus, ProjectSignatures, HistoryEntry, WindowMatch (enum with iTerm/Chrome/Generic variants), ProcessInfo, PortStatus, AppState
  - Acceptance: Models successfully decode real `~/.workstreams/state.json`

- [x] **Implement WorkstreamsApp entry point stub** `[complete]`
  - Spec: [app-lifecycle.md](./specs/app-lifecycle.md) (startup sequence, subsystem init), [ui.md](./specs/ui.md#app-entry-point) (scene structure)
  - Scope: `@main` struct with empty MenuBarExtra scene, verify app launches as menu-bar-only
  - Acceptance: App builds, shows empty menu bar icon, no Dock icon

### Phase 2: State Monitor + Menu Bar
- [x] **Implement StateMonitor service** `[complete]`
  - Spec: [state-monitor.md](./specs/state-monitor.md) — DispatchSource setup, reopen on rename/delete, retry logic (3x/50ms), fallback polling, file lifecycle table
  - Scope: `@Observable` class that reads `~/.workstreams/state.json`, watches with DispatchSource (debounced 100ms), fallback 2s polling timer, publishes state changes
  - Acceptance: State updates reactively when CLI modifies state.json

- [x] **Implement MenuBarIcon** `[complete]`
  - Spec: [ui.md](./specs/ui.md#menu-bar-icon) — icon states, color mapping
  - Scope: SF Symbol colored circle reflecting focused project's color, gray when no focus
  - Acceptance: Menu bar shows colored dot matching `current_focus` project's color

- [x] **Implement MenuBarView dropdown** `[complete]`
  - Spec: [ui.md](./specs/ui.md#menu-bar-dropdown) — layout wireframe, interaction model, quick focus feedback
  - Scope: Focused project at top, active projects section, parked projects section (with notes), "Open Dashboard" and "Quit" at bottom
  - Acceptance: Clicking menu bar dot shows project list, projects display correctly

- [x] **Implement CLIBridge service** `[complete]`
  - Spec: [cli-bridge.md](./specs/cli-bridge.md) — discovery cascade, `/bin/zsh -l` for PATH, 5s timeout, CLIError types, convenience methods
  - Scope: Discover `ws` binary (UserDefaults → `which ws` via login shell → common paths), execute focus/park/rescan/unpark commands via Process with timeout
  - Acceptance: Clicking a project in menu bar dropdown calls `ws focus <name>` and project switches

### Phase 3: Dashboard Window
- [x] **Implement DashboardView with NavigationSplitView** `[complete]`
  - Spec: [ui.md](./specs/ui.md#dashboard-window) — NavigationSplitView layout, [app-lifecycle.md](./specs/app-lifecycle.md) (onDashboardOpen/Close for polling lifecycle)
  - Scope: Main window shell with sidebar + detail area, "Open Dashboard" from menu bar opens this window, wire up visibility callbacks for polling rate changes
  - Acceptance: Window opens from menu bar, shows sidebar and detail pane

- [x] **Implement SidebarView + SidebarProjectRow** `[complete]`
  - Spec: [ui.md](./specs/ui.md#sidebar) — SidebarView, SidebarRow with focus indicator
  - Scope: Project list grouped into Active/Parked sections, color dots, focused project highlighted, "All Projects" overview option at top
  - Acceptance: Sidebar shows all projects from state, selection updates detail pane

- [x] **Implement ProjectDetailView** `[complete]`
  - Spec: [ui.md](./specs/ui.md#project-detail) — header, metadata, history layouts; [error-handling.md](./specs/error-handling.md) (ActionButton states for Focus/Park); [app-lifecycle.md](./specs/app-lifecycle.md) (missing path warning badge)
  - Scope: ScrollView with ProjectHeaderView (name, color, status badge, Focus/Park action buttons), ProjectMetadataView (path, git remote, database, URL patterns), HistorySection (last 5 entries with timeAgo), missing-path warning
  - Acceptance: Selecting a project shows full metadata and history

- [x] **Implement shared components** `[complete]`
  - Spec: [ui.md](./specs/ui.md#history-view) — timeAgo function; [error-handling.md](./specs/error-handling.md) — ErrorBanner, InlineError, ActionButton components
  - Scope: StatusBadge (Active/Focused/Parked pill), TimeFormatting (timeAgo utility), ErrorBanner (Tier 1), InlineError (Tier 2), ActionButton (ready/loading/error states with 5s auto-clear)
  - Acceptance: Badges render correctly, time formatting matches CLI output, error components render in all states

### Phase 4: Window Detection
- [x] **Implement AppleScriptRunner service** `[complete]`
  - Spec: [window-detection.md](./specs/window-detection.md#applescript-safety) — `escapeAppleScript()` function, [window-detection.md](./specs/window-detection.md#applescript-execution-helper) — executeAppleScript helper
  - Scope: Wrapper around NSAppleScript on background thread, `escapeAppleScript()` for all interpolated strings (escape `\` and `"`), error handling, result parsing
  - Acceptance: Can execute AppleScript and return string results without blocking UI

- [x] **Implement WindowDetector — iTerm detection** `[complete]`
  - Spec: [window-detection.md](./specs/window-detection.md#iterm-detection) — hierarchy parsing, CWD resolution via lsof, project matching with `standardizingPath`, it2api JSON structure
  - Scope: Detect iTerm sessions whose shell CWD starts with project path (via TTY → shell PID → lsof CWD), parse it2api hierarchy for window/tab/session mapping. Check it2api exists at launch, return empty if missing.
  - Acceptance: Returns ItermMatch array for projects with open iTerm sessions

- [x] **Implement WindowDetector — Chrome detection** `[complete]`
  - Spec: [window-detection.md](./specs/window-detection.md#chrome-detection) — URL pattern normalization (strip `/**`, contains check), AppleScript query for all tabs
  - Scope: Detect Chrome tabs matching project URL patterns (strip `/**`, test URL contains pattern prefix)
  - Acceptance: Returns ChromeMatch array for projects with matching Chrome tabs

- [x] **Implement WindowDetector — Generic detection** `[complete]`
  - Spec: [window-detection.md](./specs/window-detection.md#generic-detection) — System Events query, case-insensitive matching, exclude iTerm/Chrome
  - Scope: Detect windows from any non-background process whose title contains project name (case-insensitive)
  - Acceptance: Returns GenericMatch array (catches VS Code, Figma, etc.)

- [x] **Implement WindowDetector polling orchestration** `[complete]`
  - Spec: [window-detection.md](./specs/window-detection.md#polling-loop) — detection pass, running app check; [app-lifecycle.md](./specs/app-lifecycle.md#polling-lifecycle) — two-rate model (7s active / 30s background), visibility callbacks
  - Scope: Two-rate polling (7s when dashboard/dropdown visible, 30s in background), check which apps are running before querying, run detectors in parallel, publish windowsByProject
  - Acceptance: Dashboard updates live as windows open/close, polling slows when dashboard closes

- [x] **Implement WindowsSection + WindowCard views** `[complete]`
  - Spec: [ui.md](./specs/ui.md#window-list-view) — window card layouts per app type; [window-detection.md](./specs/window-detection.md#per-window-activation) — activation AppleScript for iTerm/Chrome/generic
  - Scope: Group detected windows by app name, show app icon + title + detail (URL for Chrome, session name for iTerm, process for generic), click to activate window via AppleScript
  - Acceptance: Dashboard shows live windows per project, clicking a card brings that window forward

### Phase 5: Terminal Insight + Port Status
- [ ] **Implement ProcessMonitor service** `[in_progress]`
  - Spec: [terminal-insight.md](./specs/terminal-insight.md) — shell PID resolution, child enumeration, classification heuristics, Claude detection (check `ps -o args=` for node processes), elapsed time parsing (MM:SS, HH:MM:SS, DD-HH:MM:SS)
  - Scope: For each iTerm session match, get shell PID from TTY, enumerate child processes via `ps`, detect Claude Code (process name/title patterns), detect dev servers (node/ruby/python with server args), detect idle shells (no children), calculate process duration
  - Acceptance: Returns process info per session: type (claude/server/idle), name, duration

- [ ] **Implement TerminalSessionCard view** `[pending]`
  - Spec: [terminal-insight.md](./specs/terminal-insight.md#display-formatting) — displayLabel format; [ui.md](./specs/ui.md#window-list-view) — iTerm card layout with process info
  - Scope: Enhanced iTerm card showing process status — "Claude: active (12m)", "node (running 45m)", "Shell: idle (2m)"
  - Acceptance: iTerm cards in dashboard show rich process information

- [ ] **Implement PortChecker service** `[pending]`
  - Spec: [port-checker.md](./specs/port-checker.md) — NWConnection probe implementation, 500ms timeout, parallel probing with TaskGroup, edge cases (port 0, >65535), integration with detection cycle
  - Scope: TCP connect probe to localhost:port with brief timeout, check all registered ports in parallel, return port→isListening map
  - Acceptance: Correctly reports whether dev servers are running on registered ports

- [ ] **Implement PortStatusView** `[pending]`
  - Spec: [ui.md](./specs/ui.md#port-status-view) — green/red circle, monospace labels; [port-checker.md](./specs/port-checker.md#display) — indicator design
  - Scope: Green/red dot per port with "localhost:PORT" label and "Listening"/"Not listening" text, auto-refreshes with window detection cycle
  - Acceptance: Port indicators match actual server status

### Phase 6: Overview Grid + Polish
- [ ] **Implement OverviewGridView + ProjectCard** `[pending]`
  - Spec: [ui.md](./specs/ui.md#overview-grid) — LazyVGrid layout, ProjectCard wireframe, parked projects shown dimmed
  - Scope: Adaptive grid of project summary cards showing color, name, status, window count, key signals (Claude active, dev server up, etc.), click card to navigate to detail. Include parked projects (visually dimmed).
  - Acceptance: "All Projects" sidebar option shows card grid overview

- [ ] **Implement Park action with note input** `[pending]`
  - Spec: [cli-bridge.md](./specs/cli-bridge.md#convenience-methods) — park/unpark methods; [error-handling.md](./specs/error-handling.md#action-button-states) — loading/error states
  - Scope: Park button in dashboard shows text field for optional note, calls `ws park [note]` via CLIBridge. Use ActionButton component for loading/error feedback.
  - Acceptance: Can park a project from the dashboard with a note

- [ ] **Implement Settings for CLI path** `[pending]`
  - Spec: [ui.md](./specs/ui.md#settings--permissions) — SettingsView layout; [cli-bridge.md](./specs/cli-bridge.md#binary-discovery) — discovery cascade, retryDiscovery(); [app-lifecycle.md](./specs/app-lifecycle.md#cli-binary-re-discovery) — retry flow
  - Scope: UserDefaults-backed setting for ws binary path, settings accessible from menu bar dropdown, auto-detect on first launch, "Retry" button when CLI not found
  - Acceptance: User can configure CLI path if auto-detection fails

- [ ] **Handle Accessibility permission flow** `[pending]`
  - Spec: [ui.md](./specs/ui.md#permissions-flow) — permission prompt UI, degradation table; [window-detection.md](./specs/window-detection.md#permission-detection) — AXIsProcessTrusted check; [app-lifecycle.md](./specs/app-lifecycle.md#permission-re-checking) — 30s re-check, transition detection
  - Scope: Detect when Accessibility/Automation permissions are missing, show helpful prompt directing user to System Settings, gracefully degrade (show permission prompt in window sections when denied), re-check every 30s until granted
  - Acceptance: First launch guides user through permission grants, app works after granting

- [ ] **Create app icon** `[pending]`
  - Scope: App icon for Assets.xcassets, should reflect the workstreams concept (multiple colored streams/dots)
  - Acceptance: App has a proper icon in menu bar "about" and Finder

## Dependencies
- macOS 15+ (Sequoia) for `@Observable` and latest SwiftUI APIs
- Xcode 16+ for building
- `ws` CLI installed and linked (for write operations)
- iTerm2 with `it2api` utility at `/Applications/iTerm.app/Contents/Resources/utilities/it2api`
- Accessibility and Automation permissions granted by user

## Design Decisions (Resolved)
- **Menu bar icon**: Simple colored circle (SF Symbol) — see [ui.md](./specs/ui.md#menu-bar-icon)
- **CLI path discovery**: Cascade: UserDefaults → `which ws` via login shell → common paths — see [cli-bridge.md](./specs/cli-bridge.md#binary-discovery)
- **Window detection when hidden**: Reduced-rate polling (30s) when dashboard/dropdown closed, full-rate (7s) when visible — see [app-lifecycle.md](./specs/app-lifecycle.md#polling-lifecycle)
- **Dashboard window position**: Remembered between launches via SwiftUI Window state restoration — see [app-lifecycle.md](./specs/app-lifecycle.md#dashboard-window-state)
- **Missing project paths**: Show with warning badge, skip from detection — see [app-lifecycle.md](./specs/app-lifecycle.md#projects-with-missing-paths)
- **Parked projects in overview**: Shown, visually dimmed — see [specs/README.md](./specs/README.md#resolved-open-questions)
- **Error handling**: Three-tier system (persistent banner, inline, silent log) — see [error-handling.md](./specs/error-handling.md)
- **Multiple monitors**: Defer — detect windows regardless of screen for now, add screen awareness later if needed

---
*Generated from planning conversation on 2026-02-09*
