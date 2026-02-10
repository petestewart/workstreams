# Terminal Insight

Classifies running processes in detected iTerm sessions. Enriches `ItermMatch` with process type and duration.

## Responsibilities

1. For each detected iTerm session, resolve the shell PID from the TTY
2. Enumerate child processes of the shell
3. Classify each session: Claude Code, dev server, or idle
4. Calculate process duration
5. Publish enriched matches back to AppState

## Interface

```swift
final class ProcessMonitor {
    private let appState: AppState

    init(appState: AppState)

    /// Enrich all iTerm matches with process info.
    /// Called after each window detection pass.
    func enrich(_ matches: [String: [ItermMatch]]) async -> [String: [ItermMatch]]
}
```

## Enrichment Flow

```
ItermMatch.tty
    → shell PID (ps -o pid= -t <tty>)
    → child processes (ps -o pid=,comm=,etime= -ppid <shellPID>)
    → classify (Claude? dev server? idle?)
    → ItermMatch.processInfo = ProcessInfo(type, duration, pid)
```

## Shell PID Resolution

The iTerm session's TTY is known from `it2api show-hierarchy`. Get the shell PID that owns it:

```swift
private func shellPID(forTTY tty: String) -> pid_t? {
    // tty comes as "/dev/ttys004" — strip prefix for ps
    let ttyName = tty.replacingOccurrences(of: "/dev/", with: "")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-o", "pid=", "-t", ttyName]

    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()

    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    // May return multiple PIDs — take the first (shell process)
    guard let firstLine = output?.components(separatedBy: .newlines).first,
          let pid = pid_t(firstLine.trimmingCharacters(in: .whitespaces)) else {
        return nil
    }
    return pid
}
```

## Child Process Enumeration

```swift
struct RawProcess {
    let pid: pid_t
    let command: String  // comm (short name, e.g., "node")
    let elapsed: String  // etime format: "HH:MM:SS" or "MM:SS" or "days-HH:MM:SS"
}

private func childProcesses(ofPID parentPID: pid_t) -> [RawProcess] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-o", "pid=,comm=,etime=", "-ppid", "\(parentPID)"]

    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()

    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    return output.components(separatedBy: .newlines).compactMap { line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Parse: "  12345 node      01:23:45"
        let parts = trimmed.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3,
              let pid = pid_t(parts[0]) else { return nil }

        return RawProcess(pid: pid, command: parts[1], elapsed: parts[2].trimmingCharacters(in: .whitespaces))
    }
}
```

## Process Classification

```swift
private func classify(_ children: [RawProcess]) -> ProcessInfo? {
    guard !children.isEmpty else {
        return ProcessInfo(type: .idle, duration: nil, pid: 0)
    }

    // Priority: Claude Code > dev server > other
    // Check for Claude Code first
    if let claude = children.first(where: { isClaude($0) }) {
        return ProcessInfo(
            type: .claudeCode,
            duration: parseElapsed(claude.elapsed),
            pid: claude.pid
        )
    }

    // Check for dev server
    if let server = children.first(where: { isDevServer($0) }) {
        return ProcessInfo(
            type: .devServer(command: server.command),
            duration: parseElapsed(server.elapsed),
            pid: server.pid
        )
    }

    // Has children but none recognized — report first child
    let first = children[0]
    return ProcessInfo(
        type: .devServer(command: first.command),
        duration: parseElapsed(first.elapsed),
        pid: first.pid
    )
}
```

### Claude Code Detection

```swift
private func isClaude(_ proc: RawProcess) -> Bool {
    let claudePatterns = ["claude", "claude-code"]
    return claudePatterns.contains(where: { proc.command.lowercased().contains($0) })
}
```

Claude Code runs as a Node.js process. The `comm` field may show `node` rather than `claude`. To improve detection:

1. Check `comm` for "claude" (works when installed globally as `claude`)
2. If `comm` is "node", check the full command line via `ps -o args= -p <pid>` for "claude" in the args

```swift
private func fullCommandContainsClaude(_ pid: pid_t) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-o", "args=", "-p", "\(pid)"]

    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()

    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return output.lowercased().contains("claude")
}
```

### Dev Server Detection

```swift
private func isDevServer(_ proc: RawProcess) -> Bool {
    let serverCommands = ["node", "ruby", "python", "python3", "rails", "puma", "uvicorn", "gunicorn", "next-server"]
    return serverCommands.contains(where: { proc.command.lowercased().contains($0) })
}
```

This is a heuristic. Not all `node` processes are dev servers, but for the "ambient awareness" use case, false positives are acceptable — showing "node (running 45m)" is more useful than showing "idle" when a server is actually running.

## Elapsed Time Parsing

`ps etime` format varies:

| Running For | Format |
|-------------|--------|
| < 1 hour | `MM:SS` |
| 1-24 hours | `HH:MM:SS` |
| > 1 day | `DD-HH:MM:SS` |

```swift
private func parseElapsed(_ etime: String) -> TimeInterval? {
    // Handle "DD-HH:MM:SS" format
    if etime.contains("-") {
        let parts = etime.split(separator: "-")
        guard parts.count == 2,
              let days = Int(parts[0]) else { return nil }
        guard let hms = parseHMS(String(parts[1])) else { return nil }
        return TimeInterval(days * 86400) + hms
    }
    return parseHMS(etime)
}

private func parseHMS(_ hms: String) -> TimeInterval? {
    let parts = hms.split(separator: ":").compactMap { Int($0) }
    switch parts.count {
    case 2: // MM:SS
        return TimeInterval(parts[0] * 60 + parts[1])
    case 3: // HH:MM:SS
        return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
    default:
        return nil
    }
}
```

## Display Formatting

```swift
extension ProcessInfo {
    var displayLabel: String {
        switch type {
        case .claudeCode:
            return "Claude: active" + durationSuffix
        case .devServer(let cmd):
            return "\(cmd)" + durationSuffix
        case .idle:
            return "Shell: idle" + durationSuffix
        }
    }

    private var durationSuffix: String {
        guard let d = duration else { return "" }
        if d < 60 { return " (\(Int(d))s)" }
        if d < 3600 { return " (\(Int(d / 60))m)" }
        return " (\(Int(d / 3600))h \(Int(d.truncatingRemainder(dividingBy: 3600) / 60))m)"
    }
}
```

## Integration with Window Detection

ProcessMonitor runs **after** WindowDetector completes each pass. The detection loop becomes:

```swift
// In WindowDetector.detectOnce():
let itermMatches = await detectIterm(projects: projects)
let enrichedIterm = await processMonitor.enrich(itermMatches)
// ... merge enrichedIterm with chrome and generic matches
```

This keeps ProcessMonitor's `ps` calls scoped to only the sessions that were actually detected, avoiding unnecessary process lookups.

## Performance

| Operation | Cost | Frequency |
|-----------|------|-----------|
| `ps -o pid= -t <tty>` | ~5ms | Per iTerm session |
| `ps -o pid=,comm=,etime= -ppid` | ~5ms | Per iTerm session |
| `ps -o args= -p <pid>` | ~5ms | Only for `node` processes (Claude detection) |

With 5 active iTerm sessions, total enrichment takes ~50-75ms. Well within the 7s polling interval.

---
*Phase 5 component — enriches iTerm matches from Phase 4 window detection*
