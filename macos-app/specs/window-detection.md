# Window Detection

Polling-based detection of project-related windows across iTerm, Chrome, and other apps. Returns individual window/tab/session matches — not app-level groupings.

## Responsibilities

1. Poll every 7 seconds for windows matching registered projects
2. Detect iTerm sessions by CWD, Chrome tabs by URL pattern, generic windows by title
3. Publish per-project window lists to `AppState`
4. Skip detection when dashboard is hidden or permissions are missing

## Interface

```swift
final class WindowDetector {
    private let appState: AppState
    private var pollingTask: Task<Void, Never>?
    private var isPolling: Bool = false

    init(appState: AppState)

    func startPolling()
    func stopPolling()
    func detectOnce() async  // Single detection pass (for manual refresh)
}
```

## Polling Loop

```swift
func startPolling() {
    guard !isPolling else { return }
    isPolling = true

    pollingTask = Task { [weak self] in
        while !Task.isCancelled {
            guard let self else { return }
            await self.detectOnce()
            try? await Task.sleep(for: .seconds(7))
        }
    }
}

func stopPolling() {
    isPolling = false
    pollingTask?.cancel()
    pollingTask = nil
}
```

### Polling Control

- **Start**: When dashboard window opens or menu bar dropdown appears.
- **Stop**: When dashboard closes and menu bar dropdown dismisses (menu-bar-only mode). Resume polling pauses detection to save CPU.
- **Manual trigger**: `detectOnce()` for immediate refresh after a focus switch.

## Detection Pass

```swift
func detectOnce() async {
    let projects = await MainActor.run { Array(appState.state.projects.values) }
    guard !projects.isEmpty else { return }

    // Check which apps are running (fast, avoids expensive AppleScript on absent apps)
    let runningApps = await checkRunningApps()

    // Run detectors in parallel
    async let itermMatches = runningApps.contains("iTerm2")
        ? detectIterm(projects: projects)
        : [:]
    async let chromeMatches = runningApps.contains("Google Chrome")
        ? detectChrome(projects: projects)
        : [:]
    async let genericMatches = detectGeneric(projects: projects, exclude: ["iTerm2", "Google Chrome"])

    let iterm = await itermMatches
    let chrome = await chromeMatches
    let generic = await genericMatches

    // Merge results per project
    var merged: [String: [WindowMatch]] = [:]
    for project in projects {
        var matches: [WindowMatch] = []
        if let im = iterm[project.name] { matches += im.map { .iterm($0) } }
        if let cm = chrome[project.name] { matches += cm.map { .chrome($0) } }
        if let gm = generic[project.name] { matches += gm.map { .generic($0) } }
        if !matches.isEmpty {
            merged[project.name] = matches
        }
    }

    await MainActor.run {
        appState.windowsByProject = merged
    }
}
```

### Running App Check

Before querying each app via AppleScript, check if it's running. This avoids launching the app or executing expensive AppleScript against absent processes.

```swift
private func checkRunningApps() async -> Set<String> {
    Set(NSWorkspace.shared.runningApplications
        .filter { !$0.isHidden }
        .compactMap { $0.localizedName })
}
```

## AppleScript Safety

**Every** string interpolated into AppleScript must be escaped. This is a security and correctness requirement.

```swift
func escapeAppleScript(_ string: String) -> String {
    string
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
```

Apply to: project names, paths, URL patterns, window titles — any value derived from user data or state file.

## iTerm Detection

Uses `it2api` for session hierarchy and `lsof`/`ps` for CWD resolution.

### Algorithm

1. Run `it2api show-hierarchy` to get window → tab → session tree with session IDs and TTYs
2. For each session, resolve shell CWD:
   - Get TTY from hierarchy
   - Find shell PID owning that TTY: `ps -o pid= -t <tty>`
   - Get CWD of that PID: `lsof -a -p <pid> -d cwd -Fn` (parse `n` line)
3. Match CWD against project paths: session belongs to project if CWD starts with project path
4. Build `ItermMatch` with window_id, tab_id, session_id, title from hierarchy

### Hierarchy Parsing

`it2api show-hierarchy` outputs JSON:

```json
[{
    "id": "window-id",
    "tabs": [{
        "id": "tab-id",
        "sessions": [{
            "id": "session-id",
            "name": "session name",
            "tty": "/dev/ttys004"
        }]
    }]
}]
```

Parse with `JSONSerialization` or a lightweight `Decodable` struct.

### it2api Location

Fixed path: `/Applications/iTerm.app/Contents/Resources/utilities/it2api`

Check existence at startup. If missing, iTerm detection returns empty results and the UI shows "Install iTerm2 for terminal detection" in the window list.

### CWD Resolution

```swift
private func resolveCWD(tty: String) -> String? {
    // Get shell PID from TTY
    guard let pid = shellPIDForTTY(tty) else { return nil }

    // Get CWD via lsof
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
    process.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
    // ... capture output, parse line starting with "n"
    // Returns path like "/Users/pete/Projects/myapp"
}
```

### Project Matching

```swift
private func matchesProject(_ cwd: String, project: Project) -> Bool {
    let normalizedCWD = (cwd as NSString).standardizingPath
    let normalizedPath = (project.path as NSString).standardizingPath
    return normalizedCWD.hasPrefix(normalizedPath)
}
```

Use `standardizingPath` to resolve symlinks and `~` for consistent comparison.

## Chrome Detection

Queries Chrome tabs via AppleScript and matches against project URL patterns.

### URL Pattern Normalization

Replicate the CLI's normalization:

```swift
private func normalizeURLPattern(_ pattern: String) -> String {
    // Strip trailing /**
    var normalized = pattern
    if normalized.hasSuffix("/**") {
        normalized = String(normalized.dropLast(3))
    }
    return normalized
}
```

### AppleScript Query

```swift
private func detectChrome(projects: [Project]) async -> [String: [ChromeMatch]] {
    let script = """
    tell application "Google Chrome"
        set allTabs to {}
        repeat with w from 1 to (count of windows)
            repeat with t from 1 to (count of tabs of window w)
                set tabURL to URL of tab t of window w
                set tabTitle to title of tab t of window w
                set end of allTabs to {w, t, tabURL, tabTitle}
            end repeat
        end repeat
        return allTabs
    end tell
    """

    guard let result = executeAppleScript(script) else { return [:] }

    // Parse result into (windowIndex, tabIndex, url, title) tuples
    // Match each tab against each project's URL patterns
    var matches: [String: [ChromeMatch]] = [:]

    for (windowIndex, tabIndex, url, title) in parsedTabs {
        for project in projects {
            for pattern in project.signatures.urlPatterns {
                let normalized = normalizeURLPattern(pattern)
                if url.contains(normalized) {
                    let match = ChromeMatch(
                        windowIndex: windowIndex,
                        tabIndex: tabIndex,
                        title: title,
                        url: url
                    )
                    matches[project.name, default: []].append(match)
                    break  // Don't double-count same tab for same project
                }
            }
        }
    }

    return matches
}
```

### URL Pattern Matching

The CLI strips trailing `/**` and does `url.includes(pattern)`. The macOS app replicates this exactly:

- `github.com/org/repo` matches `https://github.com/org/repo/pulls`
- `localhost:3000` matches `http://localhost:3000/dashboard`

## Generic Detection

Catches windows from any app whose title contains the project name.

### AppleScript Query

```swift
private func detectGeneric(projects: [Project], exclude: [String]) async -> [String: [GenericMatch]] {
    // Query all visible processes for their windows
    let script = """
    tell application "System Events"
        set results to {}
        repeat with proc in (every process whose background only is false)
            set procName to name of proc
            try
                repeat with w in (every window of proc)
                    set winTitle to name of w
                    set end of results to {procName, winTitle}
                end repeat
            end try
        end repeat
        return results
    end tell
    """

    guard let result = executeAppleScript(script) else { return [:] }

    var matches: [String: [GenericMatch]] = [:]

    for (processName, windowTitle) in parsedWindows {
        // Skip excluded apps (iTerm and Chrome handled by dedicated detectors)
        guard !exclude.contains(processName) else { continue }

        for project in projects {
            let escapedName = escapeAppleScript(project.name)
            if windowTitle.localizedCaseInsensitiveContains(project.name) {
                let match = GenericMatch(processName: processName, windowTitle: windowTitle)
                matches[project.name, default: []].append(match)
            }
        }
    }

    return matches
}
```

### Case-Insensitive Matching

Use `localizedCaseInsensitiveContains` for project name matching. A project named "MyApp" should match a VS Code window titled "myapp - Visual Studio Code".

## Per-Window Activation

Clicking a window card in the UI activates that specific window/tab.

### iTerm Activation

```swift
func activateItermSession(_ match: ItermMatch) async {
    // Use it2api for precise session activation
    let it2api = "/Applications/iTerm.app/Contents/Resources/utilities/it2api"

    let activateTab = Process()
    activateTab.executableURL = URL(fileURLWithPath: it2api)
    activateTab.arguments = ["activate", match.sessionId]
    try? activateTab.run()
    activateTab.waitUntilExit()

    // Bring iTerm to front
    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/iTerm.app"))
}
```

### Chrome Activation

```swift
func activateChromeTab(_ match: ChromeMatch) async {
    let script = """
    tell application "Google Chrome"
        set active tab index of window \(match.windowIndex) to \(match.tabIndex)
        set index of window \(match.windowIndex) to 1
        activate
    end tell
    """
    executeAppleScript(script)
}
```

### Generic Activation

```swift
func activateGenericWindow(_ match: GenericMatch) async {
    let escaped = escapeAppleScript(match.processName)
    let script = """
    tell application "System Events"
        set frontmost of process "\(escaped)" to true
    end tell
    """
    executeAppleScript(script)
}
```

Note: Generic activation brings the process to front but cannot target a specific window by title. This matches the CLI's behavior.

## AppleScript Execution Helper

```swift
private func executeAppleScript(_ source: String) -> NSAppleEventDescriptor? {
    let script = NSAppleScript(source: source)
    var error: NSDictionary?
    let result = script?.executeAndReturnError(&error)

    if let error {
        // Log but don't crash — AppleScript errors are expected
        // (app not running, permission denied, etc.)
        print("AppleScript error: \(error)")
    }

    return result
}
```

Run on a background thread (via `Task.detached` or a dedicated serial queue). `NSAppleScript.executeAndReturnError` is synchronous and can block for hundreds of milliseconds.

## Performance Considerations

| Concern | Mitigation |
|---------|------------|
| AppleScript is slow (~100-500ms per query) | Run detectors in parallel; skip absent apps |
| Many projects multiply detection time | Detection scales with running apps, not project count — each AppleScript query scans all windows once |
| Polling when hidden wastes CPU | Stop polling when dashboard is closed and menu bar dropdown dismissed |
| `lsof` calls per iTerm session | Batch TTY lookups where possible; cache CWD for 7s (one poll cycle) |

## Permission Detection

```swift
func checkPermissions() async -> (accessibility: Bool, automation: Bool) {
    let accessibility = AXIsProcessTrusted()

    // Automation: try a harmless AppleScript
    let testScript = """
    tell application "System Events"
        return name of first process whose frontmost is true
    end tell
    """
    let automation = executeAppleScript(testScript) != nil

    return (accessibility, automation)
}
```

If permissions are missing, `appState.hasAccessibilityPermission` / `hasAutomationPermission` are set to false, and the UI shows a "Grant permissions" prompt instead of empty window lists.

---
*Phase 4 component — depends on data model and AppState from Phase 1*
