# State Monitor

Watches `~/.workstreams/state.json` and keeps `AppState` in sync.

## Responsibilities

1. Watch the state file for changes using DispatchSource
2. Decode JSON with retry logic (handles partial reads during CLI writes)
3. Publish decoded state to `AppState` on the main actor
4. Fall back to polling if DispatchSource fails

## Interface

```swift
final class StateMonitor {
    private let filePath: String  // ~/.workstreams/state.json
    private let appState: AppState
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fallbackTimer: Timer?
    private var lastGoodState: WorkstreamsState?
    private var fileDescriptor: Int32 = -1

    init(appState: AppState) {
        self.filePath = NSHomeDirectory() + "/.workstreams/state.json"
        self.appState = appState
    }

    func start()   // Begin watching
    func stop()    // Tear down watchers and close file descriptor
}
```

## File Watching

### Primary: DispatchSource

```swift
func start() {
    // Initial load
    loadState()

    // Open file descriptor (required for DispatchSource)
    fileDescriptor = open(filePath, O_EVTONLY)
    guard fileDescriptor >= 0 else {
        startPollingFallback()
        return
    }

    // Watch for writes and renames (atomic saves create new inodes)
    let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fileDescriptor,
        eventMask: [.write, .rename, .delete],
        queue: .global(qos: .utility)
    )

    source.setEventHandler { [weak self] in
        guard let self else { return }
        let flags = source.data

        if flags.contains(.delete) || flags.contains(.rename) {
            // File was replaced (atomic write) — reopen
            self.reopenFileWatch()
        } else {
            // Debounce: 100ms delay to let CLI finish writing
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) {
                self.loadState()
            }
        }
    }

    source.setCancelHandler { [weak self] in
        guard let self, self.fileDescriptor >= 0 else { return }
        close(self.fileDescriptor)
        self.fileDescriptor = -1
    }

    source.resume()
    dispatchSource = source
}
```

### Reopen on Rename/Delete

Atomic file writes (which `proper-lockfile` may trigger) replace the inode. The DispatchSource stops firing on the old descriptor. Must close and reopen.

```swift
private func reopenFileWatch() {
    dispatchSource?.cancel()
    dispatchSource = nil

    // Brief delay for new file to stabilize
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.05) { [weak self] in
        self?.start()  // Recursive — reopens descriptor and creates new source
    }
}
```

### Fallback: Polling Timer

If DispatchSource can't be created (file doesn't exist yet, permissions issue):

```swift
private func startPollingFallback() {
    fallbackTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
        self?.loadState()
    }
}
```

Polling runs on a 2-second interval. Less responsive than DispatchSource but always works.

## State Loading with Retry

```swift
private func loadState() {
    let maxRetries = 3
    let retryDelay: UInt64 = 50_000_000  // 50ms in nanoseconds

    Task.detached(priority: .utility) { [weak self] in
        guard let self else { return }

        for attempt in 0..<maxRetries {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: self.filePath))
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let state = try decoder.decode(WorkstreamsState.self, from: data)

                // Success — publish to main
                self.lastGoodState = state
                await MainActor.run {
                    self.appState.state = state
                    self.appState.stateLoadError = nil
                }
                return

            } catch {
                if attempt < maxRetries - 1 {
                    try? await Task.sleep(nanoseconds: retryDelay)
                } else {
                    // All retries exhausted — keep last good state
                    await MainActor.run {
                        if self.lastGoodState != nil {
                            // Keep displaying last good state
                            self.appState.stateLoadError = "State file read error (showing cached): \(error.localizedDescription)"
                        } else {
                            self.appState.stateLoadError = "Cannot read state file: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
    }
}
```

### Why Retry?

The CLI uses `proper-lockfile` for writes. File writes are not atomic — there's a window where the file contains partial JSON. The 100ms debounce on DispatchSource reduces the odds, but retries catch the remaining cases.

### Retry Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Max retries | 3 | Enough to outlast a typical CLI write cycle |
| Retry delay | 50ms | CLI writes complete in <100ms typically |
| Debounce | 100ms | Prevents reading during rapid successive writes |

## State File Lifecycle

| Scenario | Behavior |
|----------|----------|
| File doesn't exist | Show empty state, start polling fallback, wait for CLI to create it |
| File exists, valid JSON | Load immediately, start DispatchSource |
| File mid-write (partial JSON) | Decode fails, retry up to 3 times, keep last good state |
| File replaced (atomic rename) | DispatchSource fires `.rename`, reopen watch |
| File deleted | DispatchSource fires `.delete`, switch to polling fallback |
| Stale lockfile present | Doesn't affect reads — lockfile is a separate `.lock` file |

## Cleanup

```swift
func stop() {
    dispatchSource?.cancel()
    dispatchSource = nil
    fallbackTimer?.invalidate()
    fallbackTimer = nil
    // File descriptor is closed in the cancel handler
}
```

Called from `App.onDisappear` or app termination. Closing the file descriptor is handled by the DispatchSource cancel handler to avoid double-close.

## Edge Cases

- **Empty file**: `Data(contentsOf:)` succeeds with 0 bytes, JSON decode fails. Retry handles it.
- **Very large state file**: Unlikely (would need thousands of projects), but `Data(contentsOf:)` reads the whole file. Not a concern for realistic usage.
- **Concurrent CLI writes**: The debounce + retry combination handles this. The macOS app never contends on the lockfile because it never writes.
- **File on network drive**: DispatchSource may not fire reliably. Polling fallback covers this case.

---
*Covers Phase 1 foundation — required before any UI or detection work*
