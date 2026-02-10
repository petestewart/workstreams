# CLI Bridge

Discovers the `ws` CLI binary and executes commands as subprocesses. The single write path for all state mutations.

## Responsibilities

1. Discover the `ws` binary location at launch
2. Execute CLI commands (`focus`, `park`, `unpark`, `rescan`) as subprocesses
3. Capture stdout/stderr and surface errors to the UI
4. Handle timeouts and stale lockfile scenarios

## Interface

```swift
final class CLIBridge {
    private let appState: AppState
    private var resolvedPath: String?

    init(appState: AppState)

    /// Discover CLI binary. Call once at launch.
    func discoverCLI() async

    /// Execute a ws command. Returns stdout on success.
    func execute(_ command: String, args: [String]) async throws -> String

    /// Convenience methods
    func focus(_ projectName: String) async throws
    func park(_ projectName: String, note: String?) async throws
    func unpark(_ projectName: String) async throws
    func rescan(_ projectName: String) async throws
}
```

## Binary Discovery

Cascade through locations, stop at first success:

```swift
func discoverCLI() async {
    // 1. UserDefaults override (user-configured path)
    if let userPath = UserDefaults.standard.string(forKey: "cliPath"),
       FileManager.default.isExecutableFile(atPath: userPath) {
        resolvedPath = userPath
        await publish(path: userPath)
        return
    }

    // 2. `which ws` via shell (gets PATH-resolved location)
    if let whichResult = try? shellWhich("ws") {
        resolvedPath = whichResult
        await publish(path: whichResult)
        return
    }

    // 3. Common Homebrew/npm-link locations
    let commonPaths = [
        "/usr/local/bin/ws",
        "/opt/homebrew/bin/ws",
        NSHomeDirectory() + "/.npm-global/bin/ws",
    ]
    for path in commonPaths {
        if FileManager.default.isExecutableFile(atPath: path) {
            resolvedPath = path
            await publish(path: path)
            return
        }
    }

    // 4. Failure
    await MainActor.run {
        appState.cliPath = nil
        appState.cliError = "Could not find 'ws' CLI. Install it or set the path in Settings."
    }
}
```

### `which` via Shell

GUI apps don't inherit the user's shell PATH. Must invoke a login shell to resolve:

```swift
private func shellWhich(_ command: String) throws -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = ["-l", "-c", "which \(command)"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else { return nil }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return path?.isEmpty == false ? path : nil
}
```

Using `/bin/zsh -l` loads the user's login profile, which includes PATH modifications from `.zshrc`, `.zprofile`, etc. This is critical for finding npm-linked or Homebrew-installed binaries.

## Command Execution

```swift
func execute(_ command: String, args: [String] = []) async throws -> String {
    guard let path = resolvedPath else {
        throw CLIError.noBinary
    }

    return try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [command] + args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Timeout: 5 seconds
        let timeoutItem = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeoutItem)

        process.terminationHandler = { proc in
            timeoutItem.cancel()

            let stdout = String(
                data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let stderr = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""

            if proc.terminationStatus == 0 {
                continuation.resume(returning: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            } else if proc.terminationReason == .uncaughtSignal {
                continuation.resume(throwing: CLIError.timeout(command: command))
            } else {
                continuation.resume(throwing: CLIError.executionFailed(
                    command: command,
                    exitCode: proc.terminationStatus,
                    stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        }

        do {
            try process.run()
        } catch {
            timeoutItem.cancel()
            continuation.resume(throwing: CLIError.launchFailed(error))
        }
    }
}
```

## Error Types

```swift
enum CLIError: LocalizedError {
    case noBinary
    case timeout(command: String)
    case executionFailed(command: String, exitCode: Int32, stderr: String)
    case launchFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noBinary:
            return "ws CLI not found. Check Settings to configure the path."
        case .timeout(let cmd):
            return "ws \(cmd) timed out (possible stale lockfile). Try running 'ws \(cmd)' in terminal."
        case .executionFailed(let cmd, let code, let stderr):
            return "ws \(cmd) failed (exit \(code)): \(stderr)"
        case .launchFailed(let error):
            return "Failed to launch ws: \(error.localizedDescription)"
        }
    }
}
```

## Convenience Methods

```swift
func focus(_ projectName: String) async throws {
    _ = try await execute("focus", args: [projectName])
}

func park(_ projectName: String, note: String? = nil) async throws {
    var args = [projectName]
    if let note { args.append(note) }
    _ = try await execute("park", args: args)
}

func unpark(_ projectName: String) async throws {
    _ = try await execute("unpark", args: [projectName])
}

func rescan(_ projectName: String) async throws {
    _ = try await execute("rescan", args: [projectName])
}
```

## Timeout & Stale Lockfile Handling

The CLI's `park.ts` has a known bug where `process.exit(1)` inside `withState()` can leave a stale lockfile. When this happens, subsequent CLI calls hang waiting for the lock.

**Detection**: The 5-second timeout catches this. If `ws focus` or `ws park` times out, it's likely a stale lockfile.

**User messaging**: The error message suggests running the command in terminal directly, where the user can see the lockfile error and manually resolve it.

**Not auto-resolved**: The macOS app does not attempt to delete stale lockfiles. That's a write operation that belongs to the CLI.

## Design Notes

- **`/bin/zsh -l`** over `/bin/sh`: macOS defaults to zsh. Login shell (`-l`) is necessary to load PATH from `.zshrc`/`.zprofile`. Using `/bin/sh` misses Homebrew and nvm PATH entries.
- **5-second timeout**: CLI commands should complete in <1s. 5s is generous enough for slow disks but catches lockfile hangs.
- **No retry on failure**: CLI errors are surfaced to the user, not silently retried. The user should see "park failed" immediately, not after multiple hidden retries.
- **`terminationHandler` over `waitUntilExit`**: Non-blocking. Using `waitUntilExit` would block the calling thread/task.

---
*Foundation component (Phase 1) — required before any UI actions can mutate state*
