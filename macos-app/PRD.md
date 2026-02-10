# PRD: Workstreams macOS App (SwiftUI)

## Problem Statement

When juggling multiple software projects, there's no single place to see what's happening across all your work right now. The CLI answers "switch to project X." Raycast answers "which project do I want?" But neither answers the ambient awareness question: which projects have active dev servers, where is Claude running, which windows belong to which project, and what did I park 30 minutes ago?

**Desired Outcome:** A native macOS menu bar app that provides always-on project awareness — current focus at a glance, live window detection, terminal process insight, and port status — without replacing the CLI or Raycast extension.

**Success Criteria:**
- Menu bar icon with color-coded dot shows current focused project; dropdown enables quick-switching
- Dashboard window shows project details, live detected windows per app with individual window/tab drill-down, terminal process insight, port status
- Overview grid shows bird's-eye view of all projects simultaneously
- App reads `~/.workstreams/state.json` directly, delegates all writes to the `ws` CLI
- Runs as menu-bar-primary app (no Dock icon), targeting macOS 15+ (Sequoia)

## Proposed Solution

### Technical Approach

A pure SwiftUI app that sits in the menu bar and watches the existing Workstreams state file. It adds a read-heavy observation layer on top of the existing CLI infrastructure:

1. **State observation** — DispatchSource file watcher on `~/.workstreams/state.json` with debounce (100ms), driving an `@Observable` model that SwiftUI views bind to directly. Retry with exponential backoff on JSON decode failures (handles partial reads during CLI writes). Fallback 2s polling timer if DispatchSource fails.

2. **Window detection** — Polling-based AppleScript queries (every 7s) that detect iTerm sessions by CWD, Chrome tabs by URL pattern, and generic windows by title. Same matching logic as the CLI's focus modules (`src/focus/`), ported to Swift. Returns individual matches at window/tab/session granularity — not just app-level groupings.

3. **Terminal enrichment** — New implementation (no CLI equivalent exists). For each detected iTerm session, resolve the shell PID from the TTY, enumerate child processes via `ps`, and classify: Claude Code session, dev server, or idle shell. Built natively in Swift using `Process` to call `ps`.

4. **Port probing** — New implementation (no CLI equivalent exists). TCP connect checks against registered ports using Swift's Network framework (`NWConnection`) or BSD sockets. The CLI scans project files for port numbers but never checks if they're listening.

5. **Write delegation** — All mutations (focus, park, rescan) go through the `ws` CLI binary via `Process`, keeping the CLI as the single source of truth for writes.

6. **AppleScript safety** — All project names and paths must be escaped before interpolation into AppleScript strings. The CLI has a known injection vulnerability (unescaped double quotes break AppleScript execution). The macOS app must implement `escapeAppleScript()` from day one, escaping `\` and `"` characters.

### Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Framework | Pure SwiftUI, macOS 15+ | `@Observable` macro eliminates boilerplate; latest APIs for MenuBarExtra, NavigationSplitView |
| App mode | LSUIElement (menu bar only) | This is a monitoring tool, not a primary workspace app — no Dock icon |
| Sandbox | Disabled | Requires AppleScript automation, subprocess execution (`ws` CLI), file system access (`~/.workstreams/`), TCP port probing |
| State reads | Direct file read with retry | Same JSON file the CLI writes; retry on decode failure to handle race with CLI's `proper-lockfile` writes |
| State writes | Shell out to `ws` CLI | Preserves the CLI as the canonical write path; avoids reimplementing state mutation logic and lock handling |
| Window detection | AppleScript via NSAppleScript | Same approach as CLI/Raycast; proven to work for iTerm, Chrome, and generic apps |
| Polling interval | 7 seconds for windows, file-watch for state | Window detection is expensive (AppleScript); state changes are cheap to watch |
| Process monitoring | Native Swift, new code | CLI has no process monitoring. Built fresh using `Process` + `ps` — no TypeScript to port |
| Port probing | Native Swift, new code | CLI detects port numbers from config files but never checks if they're listening. Use NWConnection |

## Scope

### Affected Systems

- **macos-app/** — New SwiftUI application (all new code). Self-contained within this directory.
- **~/.workstreams/state.json** — Read by the app; no schema changes required.
- **ws CLI binary** — Called as a subprocess for write operations; no changes to the CLI itself.

### Dependencies

- macOS 15+ (Sequoia) for `@Observable` macro and latest SwiftUI APIs
- Xcode 16+ for building
- `ws` CLI installed and available in PATH (for focus/park/rescan operations)
- iTerm2 with `it2api` utility at `/Applications/iTerm.app/Contents/Resources/utilities/it2api` (**required** for iTerm session hierarchy — no fallback without it)
- User grants Accessibility and Automation permissions (for AppleScript window detection)

### Out of Scope

- Changes to the CLI or Raycast extension
- State file schema modifications
- Chrome extension integration (separate future effort)
- Window tiling/layout management (use Rectangle or similar)
- Multi-machine state sync
- Triggers and automated follow-up actions
- iOS/iPadOS companion app
- iTerm detection without `it2api` (no basic AppleScript fallback — detection requires the hierarchy mapping that only `it2api show-hierarchy` provides)

## Feature Breakdown

### Menu Bar (Phase 2)

**Menu Bar Icon** — SF Symbol colored circle reflecting the focused project's color. Gray when no project is focused.

**Menu Bar Dropdown** — Focused project displayed at top, then sections for active and parked projects (parked shows notes). Footer with "Open Dashboard" and "Quit."

**Quick Actions** — Clicking a project in the dropdown calls `ws focus <name>` via CLIBridge. Instant context switch.

### Dashboard Window (Phase 3)

**NavigationSplitView Layout** — Sidebar with project list (grouped Active/Parked, color dots, focus highlight) + "All Projects" overview option. Detail pane shows selected project.

**Project Detail** — Header with name, color, status badge, Focus/Park action buttons. Metadata section showing path, git remote, database, URL patterns. History section showing last 5 entries with relative timestamps.

### Window Detection (Phase 4)

The CLI already provides granular window/tab detection (`ws windows`) and per-window activation (`ws focus --window=N --app=X`). The macOS app ports this same granularity to Swift.

**iTerm Detection** — Detect individual sessions whose shell CWD starts with project path. Uses TTY → shell PID → `lsof` for CWD resolution. Parses `it2api show-hierarchy` for window/tab/session mapping. Each match includes `window_id`, `tab_id`, `session_id`, and `title` (session name). Requires `it2api` — returns empty if not present.

**Chrome Detection** — Detect individual tabs matching project URL patterns. URL patterns are normalized from git remote (e.g., `git@github.com:org/repo.git` → `github.com/org/repo`). Strip trailing `/**` from patterns, test if tab URL contains the prefix. Each match includes `window_index`, `tab_index`, `title`, and `url`.

**Generic Detection** — Detect individual windows from any non-background process (`background only is false` in AppleScript) whose title contains project name. Catches VS Code, Figma, Typora, etc. Each match includes `process_name` and `window_title`.

**Window List View** — Shows all detected windows grouped by app. Each window/tab is an individual card with:
- iTerm: session name, tab ID (enriched with process info in Phase 5)
- Chrome: page title + URL
- Generic: window title + process name

**Per-Window Activation** — Clicking any window card activates that specific window/tab via AppleScript (matching `ws focus --window=N` behavior). For iTerm: `it2api activate tab` + `it2api activate window`. For Chrome: set `active tab index` + bring window to front. For generic: set `frontmost of process` to true.

### Terminal Insight + Port Status (Phase 5)

**Process Monitor** — New Swift implementation for each iTerm session match:
1. Get the shell PID from the session's TTY (same TTY → PID resolution as detection)
2. Enumerate child processes via `ps -o pid=,comm=,etime= -ppid <shellPID>`
3. Classify: Claude Code (match process name/title patterns), dev server (node/ruby/python with server-like args), idle shell (no children)
4. Calculate process duration from `etime`

**Terminal Cards** — Enhanced iTerm cards showing process status: "Claude: active," "npm run dev (running 45m)," "Shell: idle (2m)."

**Port Checker** — New Swift implementation. TCP connect probe to `localhost:<port>` with brief timeout (~500ms) for each registered port. Uses NWConnection or BSD socket connect. Returns `port → isListening` map. Note: CLI port scanning only detects 4-5 digit port numbers (regex `\d{4,5}`), so ports like 80 or 443 won't appear in signatures.

**Port Status View** — Green/red dot per port with "localhost:PORT" label and "Listening"/"Not listening" text. Auto-refreshes with window detection cycle.

### Overview Grid (Phase 6)

**Project Cards** — Adaptive grid of summary cards: color, name, status, window count, key signals (Claude active, dev server up). Click to navigate to detail.

**Park with Note** — Park button shows text field for optional note, calls `ws park [note]` via CLIBridge.

**Settings** — UserDefaults-backed ws binary path, accessible from menu bar dropdown, auto-detect on first launch.

**Permissions Flow** — Detect missing Accessibility/Automation permissions, show helpful prompt, gracefully degrade when denied (show empty window lists with "Grant permissions to detect windows" message — don't fail silently like the CLI does).

## Data Flow

```
~/.workstreams/state.json ←writes— ws CLI ←called by— CLIBridge ←triggered by— UI actions
                          —reads→ StateMonitor (@Observable) —drives→ SwiftUI Views

WindowDetector (polling 7s) → NSAppleScript → publishes windowsByProject
  ├── ItermDetector: TTY → shell PID → lsof CWD → it2api hierarchy → ItermMatch[]
  ├── ChromeDetector: URL patterns (normalized from git remote) → tab scan → ChromeMatch[]
  └── GenericDetector: project name → window title scan → GenericMatch[]

ProcessMonitor → shell PID → ps child processes → enriches ItermMatch with process type/duration
PortChecker → NWConnection probe localhost:port → green/red indicators
```

## Codebase Constraints

Details verified against the CLI codebase that affect macOS app implementation:

### State File & Locking

- **Lock mechanism**: CLI uses `proper-lockfile` with 3 retries (100-1000ms exponential backoff). The macOS app only reads, never writes, but reads during an active lock may see partial JSON.
- **Stale lockfiles**: `commands/park.ts` calls `process.exit(1)` inside the `withState()` callback (lines 9, 20), which can leave a stale lockfile. The macOS app may encounter this — CLIBridge should handle the case where `ws park` or `ws focus` fails due to a stale lock.
- **Retry strategy for reads**: On JSON decode failure, retry up to 3 times with 50ms delay. If all retries fail, keep the last successfully decoded state and log the error.

### AppleScript Injection

- All three CLI focus modules (`iterm.ts`, `chrome.ts`, `generic.ts`) interpolate project names and paths directly into AppleScript strings without escaping.
- Project names containing `"` will break AppleScript execution silently (returns empty results, no error).
- **The macOS app must implement `escapeAppleScript()`** that escapes `\` → `\\` and `"` → `\"` before interpolating any user-controlled string into AppleScript.

### URL Pattern Normalization

- Git remote URLs are normalized before storage: `git@github.com:org/repo.git` → `github.com/org/repo`
- `localhost:<port>/**` patterns are auto-generated for each detected port
- Chrome detection strips trailing `/**` from patterns and does a simple `contains` check
- The macOS app's Chrome detection must replicate this exact normalization

### Port Number Detection

- The CLI's scan regex only matches 4-5 digit port numbers (`\d{4,5}`)
- Ports like 80, 443, or 8080 would need to be 4+ digits to be detected (8080 works, 80 doesn't)
- Duplicate ports across `.env`, `package.json`, and `docker-compose.yml` are deduplicated

### Window Match Types

The CLI defines three discriminated union variants (from `src/types.ts`):

```
ItermMatch:   { app: "iTerm", window_id, tab_id, session_id, title }
ChromeMatch:  { app: "Chrome", window_index, tab_index, title, url }
GenericMatch: { app: string, window_title, process_name }
```

The macOS app's Swift models should mirror these exactly. Discrimination is by field presence (`session_id` → iTerm, `url` → Chrome, else generic) or by an enum tag.

### CLI Binary Discovery

- The Raycast extension hardcodes `~/Projects/workstreams/dist/cli.js` — this breaks for users with non-standard installs.
- **Learn from this mistake**: The macOS app should try: (1) `which ws` via shell subprocess, (2) `/usr/local/bin/ws`, (3) `/opt/homebrew/bin/ws`, (4) UserDefaults override. Never hardcode a single path.

### History Entry Types

- CLI types `action` as: `"added" | "focused" | "parked" | "unparked"`
- Raycast extension types it as bare `string` (known drift)
- The macOS app should use a Swift enum with these four cases plus an `unknown(String)` fallback for forward compatibility

## Risks & Open Questions

### Risks

- **Accessibility/Automation permissions UX**: macOS permission prompts are confusing. If the user denies or forgets, the app silently loses window detection. Mitigation: clear first-launch guidance, graceful degradation with visible "Grant permissions to detect windows" indicator (not silent failure like the CLI).

- **AppleScript performance**: Running three AppleScript queries across all projects every 7 seconds could become slow with many projects. Mitigation: cache results, only re-query apps that are running (check via `System Events` `exists process`), pause polling when dashboard is hidden.

- **CLI binary discovery**: The app needs to find `ws` in the user's PATH, but GUI apps don't inherit shell PATH. Mitigation: cascade through `which ws` (via shell), common locations, UserDefaults override. Never hardcode.

- **State file race conditions**: CLI uses `proper-lockfile` for writes. If the macOS app reads mid-write, it gets partial JSON. Mitigation: retry decode up to 3 times with 50ms delay, keep last good state on failure, DispatchSource debounce (100ms) to avoid reading during rapid writes.

- **Stale lockfiles from CLI bugs**: `park.ts` can leave stale lockfiles if validation fails inside `withState()`. Mitigation: CLIBridge should detect hung CLI calls (timeout after 5s) and surface the error rather than hanging.

- **AppleScript injection**: Project names with double quotes break window detection silently. Mitigation: implement `escapeAppleScript()` that escapes `\` and `"` in all interpolated strings. Apply universally — never interpolate raw user input.

### Open Questions

- [ ] Should the dashboard window remember its position/size between launches?
- [ ] Should window detection continue when the dashboard is closed (menu-bar-only mode)?
- [ ] How should the app handle projects whose paths no longer exist on disk?
- [ ] Should the overview grid show parked projects, or only active ones?
- [ ] Is 7 seconds the right polling interval, or should it be user-configurable?

## Success Criteria

1. **Menu bar presence**: App launches as menu-bar-only, shows colored dot matching focused project, dropdown lists all projects with correct status
2. **State reactivity**: Changing focus via `ws focus` in terminal updates the menu bar icon within 1 second
3. **Window detection**: Dashboard accurately shows individual iTerm sessions, Chrome tabs, and generic windows per project — not just app-level groupings
4. **Per-window activation**: Clicking a specific window card in the dashboard activates that exact window/tab in the target app
5. **Terminal insight**: iTerm cards display running process type (Claude/server/idle) and duration
6. **Port status**: Green/red indicators correctly reflect whether registered ports are listening
7. **Write delegation**: Focus/park actions from the app successfully call the CLI and state updates propagate back
8. **Zero interference**: App never writes to state.json directly; never modifies window positions or sizes
9. **Graceful degradation**: Missing permissions, absent `it2api`, or unreachable CLI produce visible status messages, not silent failures

---
*Generated from PLAN.md on 2026-02-09. Validated against CLI codebase.*
