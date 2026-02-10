# Error Handling

Unified strategy for error recovery, display, and graceful degradation across all subsystems.

## Principle

**Never crash. Never fail silently. Always show what's wrong and what to do about it.**

Every error produces a visible indicator with an actionable message. The app continues operating in a degraded mode — showing whatever data it has — rather than blocking on any single failure.

## Error Categories

| Category | Example | Display Location | Recovery |
|----------|---------|-----------------|----------|
| State file error | JSON decode failure | Menu bar badge + dashboard banner | Auto-retry, show cached state |
| CLI not found | `ws` not in PATH | Menu bar dropdown + dashboard banner | Manual: Settings or Retry |
| CLI execution failure | `ws focus` returns non-zero | Inline at action site | Show error, user re-tries |
| CLI timeout | Stale lockfile | Inline at action site | Suggest running in terminal |
| Permission missing | Accessibility denied | Dashboard section placeholder | Link to System Settings |
| Detection failure | AppleScript error | Log only (non-visible) | Skip silently, retry next cycle |
| Port probe failure | Connection error | Show "Unknown" instead of red/green | Retry next cycle |
| it2api missing | File not at expected path | iTerm section message | Install iTerm2 |

## Error Display Model

### Three tiers of visibility:

**Tier 1 — Persistent banner** (top of dashboard, visible in menu bar icon)
- State file unreadable (no cached data)
- CLI binary not found

These block core functionality. User must act.

```swift
struct ErrorBanner: View {
    let message: String
    let actionLabel: String?
    let action: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "exclamation.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
            Spacer()
            if let actionLabel, let action {
                Button(actionLabel, action: action)
            }
        }
        .padding()
        .background(.yellow.opacity(0.1))
        .cornerRadius(8)
    }
}
```

**Tier 2 — Inline message** (at the action site or section)
- CLI command failed → message next to the button that triggered it
- Permission missing → placeholder in the window list section
- it2api missing → placeholder in iTerm section

These affect a specific feature. The rest of the app works fine.

```swift
struct InlineError: View {
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}
```

**Tier 3 — Silent log** (console only, never shown to user)
- AppleScript returned unexpected format
- Single port probe timed out
- Process classification didn't match any pattern

These are transient or low-impact. Retry on next cycle.

## Per-Subsystem Recovery

### StateMonitor

| Failure | Behavior |
|---------|----------|
| File doesn't exist | Show "No projects found" + setup instructions. Poll at 2s until file appears. |
| JSON decode error (first time) | Retry 3x with 50ms delay. If all fail, show Tier 1 banner: "Cannot read state file." |
| JSON decode error (subsequent) | Keep displaying last good state. Show Tier 2 note: "Showing cached data — state file temporarily unreadable." |
| File permissions error | Show Tier 1 banner: "Cannot read ~/.workstreams/state.json — check file permissions." |
| DispatchSource fails to create | Fall back to 2s polling timer. No user-visible indication (polling works fine). |

**Key**: `lastGoodState` is the safety net. Once the app has decoded the state file successfully even once, it never shows "no data" for a transient decode failure.

### CLIBridge

| Failure | Behavior |
|---------|----------|
| Binary not found | Tier 1 banner: "ws CLI not found." Action: "Open Settings" / "Retry". All action buttons disabled. |
| Command exits non-zero | Tier 2 inline error at button: "Failed: {stderr message}". Error auto-clears after 5 seconds or on next action. |
| Command timeout (5s) | Tier 2 inline error: "Command timed out — possible stale lockfile. Try running `ws {cmd}` in terminal." |
| Launch failure (permission) | Tier 1 banner: "Cannot execute ws CLI — check file permissions." |

**Inline error lifecycle**: Errors from CLI actions (focus, park) appear next to the button that triggered them. They clear after 5 seconds or when the user takes another action. This prevents stale errors from lingering.

```swift
@Observable
final class AppState {
    // ...
    var actionError: ActionError?

    struct ActionError: Identifiable {
        let id = UUID()
        let message: String
        let timestamp: Date = Date()
    }
}
```

### WindowDetector

| Failure | Behavior |
|---------|----------|
| Accessibility permission denied | Tier 2 placeholder in window list: "Grant Accessibility permission to detect windows" + button to open System Settings. |
| Automation permission denied | Tier 2 placeholder per app: "Grant Automation permission for {app} detection." |
| AppleScript returns unexpected data | Tier 3 log. Return empty results for that detector. Other detectors unaffected. |
| App not running | Not an error — just skip that detector (normal behavior). |
| it2api missing | Tier 2 message in iTerm section: "iTerm session detection requires it2api (included with iTerm2)." |

**Isolation**: Each detector (iTerm, Chrome, generic) runs independently. If Chrome detection throws an error, iTerm and generic detection still complete and publish their results.

### PortChecker

| Failure | Behavior |
|---------|----------|
| Connection refused | Normal — port not listening. Show red indicator. |
| Connection timeout | Port not listening (or filtered). Show red indicator. |
| NWConnection internal error | Tier 3 log. Show gray "Unknown" indicator for that port. |
| Invalid port number (>65535) | Skip port, Tier 3 log. |

**No retries within a cycle**: If a probe fails, it will be retried on the next polling cycle (7s or 30s). No immediate retry — the cost is one stale indicator for one cycle.

### ProcessMonitor

| Failure | Behavior |
|---------|----------|
| `ps` command fails | Tier 3 log. ItermMatch.processInfo stays nil. UI shows session title without enrichment. |
| TTY not found for session | Same — processInfo stays nil. |
| Unrecognized process | Classify as `.devServer(command:)` with the raw command name. Not an error. |

**Graceful nil**: `ItermMatch.processInfo` is optional by design. If enrichment fails for any reason, the UI falls back to showing just the session title. No error displayed — the user still sees the window, just without process details.

## Error State Transitions

```
Normal ──[error]──→ Degraded ──[recovery]──→ Normal
                       │
                  Shows indicator
                  Continues operating
                  Retries automatically
```

The app never enters a "broken" state. It oscillates between normal and degraded, with clear indicators at each transition.

## Action Button States

Buttons that trigger CLI commands have three states:

```swift
enum ActionButtonState {
    case ready           // Enabled, normal appearance
    case loading         // Disabled, shows spinner
    case error(String)   // Enabled, shows error below

    // Error auto-clears after 5 seconds
}
```

```swift
struct ActionButton: View {
    let label: String
    let action: () async throws -> Void
    @State private var state: ActionButtonState = .ready

    var body: some View {
        VStack(alignment: .leading) {
            Button {
                Task {
                    state = .loading
                    do {
                        try await action()
                        state = .ready
                    } catch {
                        state = .error(error.localizedDescription)
                        // Auto-clear after 5s
                        Task {
                            try? await Task.sleep(for: .seconds(5))
                            if case .error = state { state = .ready }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(label)
                    if case .loading = state {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .disabled(state.isLoading)

            if case .error(let msg) = state {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
```

## Quick Focus Feedback

When the user clicks a project in the menu bar dropdown:

1. Button enters `.loading` state (spinner)
2. CLIBridge calls `ws focus <name>` (typically <1s)
3. On success:
   - Button returns to `.ready`
   - StateMonitor detects the file change (DispatchSource, ~100ms)
   - AppState updates, menu bar icon color changes
   - **No optimistic update** — wait for StateMonitor confirmation to avoid UI inconsistency
4. On failure:
   - Button enters `.error` state with the CLI error message
   - Error clears after 5 seconds
   - Menu bar dropdown stays open (so user sees the error)

## What NOT to Do

- **Don't crash on unexpected state**: If a JSON field is missing, use defaults. If an enum has an unknown value, use `.unknown(String)`.
- **Don't retry indefinitely**: Each subsystem has a fixed retry count. After exhaustion, show the error and wait for the next natural retry (polling cycle, user action, or file change).
- **Don't show technical errors to users**: "JSON decode error at offset 42" → "State file temporarily unreadable". "Exit code 1" → "Command failed: {stderr}".
- **Don't block the UI on errors**: All error recovery happens in background tasks. The UI stays responsive. Errors are displayed as non-modal indicators.
- **Don't accumulate errors**: Only show the most recent error per subsystem. Old errors are replaced, not stacked.

---
*Unified error strategy addressing the fragmented per-subsystem handling*
