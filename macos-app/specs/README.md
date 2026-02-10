# Technical Specification: Workstreams macOS App

## Overview

A native SwiftUI menu bar application for macOS 15+ (Sequoia) that provides ambient awareness of concurrent software projects. The app reads the shared `~/.workstreams/state.json` file, detects project windows across apps, monitors terminal processes, probes ports, and delegates all writes to the `ws` CLI binary.

The app is **read-heavy by design**: it observes, enriches, and displays — but never mutates state directly.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        SwiftUI Views                        │
│  MenuBarView  │  DashboardWindow  │  OverviewGrid           │
└───────┬───────┴────────┬──────────┴──────────┬──────────────┘
        │                │                     │
        ▼                ▼                     ▼
┌─────────────────────────────────────────────────────────────┐
│                      AppState (@Observable)                  │
│  projects, currentFocus, windowsByProject, portStatus,       │
│  processInfo, cliPath, permissionStatus                      │
└──┬──────────┬───────────┬──────────┬──────────┬─────────────┘
   │          │           │          │          │
   ▼          ▼           ▼          ▼          ▼
StateMonitor  WindowDetector  ProcessMonitor  PortChecker  CLIBridge
 (file watch)  (7s poll)      (per-session)   (per-port)   (subprocess)
   │          │               │               │            │
   ▼          ▼               ▼               ▼            ▼
state.json   AppleScript     ps + lsof       NWConnection  ws CLI
             + it2api
```

### Dependency Rule

Strict downward flow. Views depend on AppState. AppState is populated by five independent subsystems. Subsystems never reference each other — coordination happens through AppState.

### Threading Model

- **Main actor**: All `@Observable` state mutations and SwiftUI view updates.
- **Background tasks**: File watching, AppleScript execution, process enumeration, port probing, CLI subprocess calls. Each subsystem runs its work off-main and publishes results back to main via `@MainActor`.
- **No actors required**: The subsystems are simple enough that structured concurrency (`Task`, `Task.detached`) with `@MainActor` annotations on publish methods is sufficient. No need for custom actors unless profiling shows contention.

## Components

| Component | Spec | Phase | Description |
|-----------|------|-------|-------------|
| Data Model | [data-model.md](./data-model.md) | 1 | Swift types mirroring state.json, window matches, enums |
| State Monitor | [state-monitor.md](./state-monitor.md) | 1 | File watching with DispatchSource, retry, @Observable |
| CLI Bridge | [cli-bridge.md](./cli-bridge.md) | 1 | Binary discovery, subprocess execution, error handling |
| App Lifecycle | [app-lifecycle.md](./app-lifecycle.md) | 1 | Initialization, subsystem startup, polling lifecycle |
| Error Handling | [error-handling.md](./error-handling.md) | All | Unified error recovery, display tiers, degradation |
| Menu Bar | [ui.md](./ui.md#menu-bar) | 2 | MenuBarExtra with dropdown, quick actions |
| Dashboard | [ui.md](./ui.md#dashboard-window) | 3 | NavigationSplitView with project detail |
| Window Detection | [window-detection.md](./window-detection.md) | 4 | iTerm, Chrome, and generic detectors |
| Terminal Insight | [terminal-insight.md](./terminal-insight.md) | 5 | Process classification per iTerm session |
| Port Checker | [port-checker.md](./port-checker.md) | 5 | TCP probe against registered ports |
| Overview Grid | [ui.md](./ui.md#overview-grid) | 6 | Bird's-eye project card grid |
| Settings & Permissions | [ui.md](./ui.md#settings--permissions) | 6 | UserDefaults, permission detection |

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| State observation | `@Observable` class, no Combine | macOS 15 baseline means `@Observable` is available; simpler than Combine publishers |
| File watching | DispatchSource + polling fallback | DispatchSource is zero-overhead when idle; polling fallback covers edge cases (network drives, APFS edge cases) |
| AppleScript execution | `NSAppleScript` on background thread | Synchronous but moved off-main; avoids `osascript` subprocess overhead |
| Subprocess calls | `Process` (Foundation) | Standard Swift API for CLI invocation; captures stdout/stderr |
| Port probing | `NWConnection` (Network.framework) | Non-blocking, timeout-capable, no BSD socket boilerplate |
| Navigation | `NavigationSplitView` | Two-column layout fits sidebar + detail pattern; native macOS behavior |
| Menu bar | `MenuBarExtra` with `.window` style | SwiftUI-native menu bar API; `.window` allows custom views in popover |
| Persistence | `UserDefaults` for settings only | Only settings (CLI path, polling interval) need persistence; project state lives in state.json |
| Error handling | Graceful degradation, never crash | Missing permissions → visible indicator. CLI failure → error message. Decode failure → keep last good state |

## Constraints

- **macOS 15+ only** — uses `@Observable`, latest `MenuBarExtra` APIs
- **Xcode 16+** for building
- **No sandbox** — requires file system access, AppleScript automation, subprocess execution, TCP connections
- **LSUIElement = true** — no Dock icon, menu-bar-primary
- **Read-only for state.json** — all writes go through `ws` CLI via CLIBridge
- **iTerm detection requires `it2api`** — no fallback; returns empty results if missing
- **Accessibility + Automation permissions required** — graceful degradation when denied

## Phase Milestones

| Phase | Deliverable | Depends On |
|-------|-------------|------------|
| 1 — Foundation | Data model, state monitor, CLI bridge, app shell | Nothing |
| 2 — Menu Bar | Menu bar icon, dropdown, quick focus switching | Phase 1 |
| 3 — Dashboard | NavigationSplitView, project detail, history | Phase 2 |
| 4 — Windows | All three detectors, window list, per-window activation | Phase 3 |
| 5 — Enrichment | Process monitor, port checker, enhanced terminal cards | Phase 4 |
| 6 — Polish | Overview grid, settings, permissions flow, performance tuning | Phase 5 |

## Resolved Open Questions

From the PRD's open questions, resolved with sensible defaults:

| Question | Decision | Rationale | Spec |
|----------|----------|-----------|------|
| Dashboard window position/size persistence? | **Yes** — use SwiftUI's built-in Window state restoration | Standard macOS behavior; users expect windows to remember their frame | [app-lifecycle.md](./app-lifecycle.md) |
| Window detection when dashboard is closed? | **Yes, at reduced rate (30s)** instead of 7s | Menu bar dropdown needs window counts and signals; 30s is cheap enough | [app-lifecycle.md](./app-lifecycle.md) |
| Projects whose paths no longer exist? | **Show with warning badge**, skip from detection | Don't silently remove — user may have unmounted a drive or renamed a directory | [app-lifecycle.md](./app-lifecycle.md) |
| Overview grid shows parked projects? | **Yes**, visually dimmed below active projects | Bird's-eye view should show everything; parked projects are dimmed, not hidden | [ui.md](./ui.md#overview-grid) |
| Polling interval user-configurable? | **No** — hardcode 7s (active) / 30s (background) | Simplicity; expose later if users request it | [app-lifecycle.md](./app-lifecycle.md) |

---
*Generated from PRD.md on 2026-02-09*
