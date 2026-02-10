# Port Checker

TCP connect probes against registered ports to determine if services are listening.

## Responsibilities

1. For each project, probe registered ports from `signatures.ports`
2. Determine listening status via TCP connect with timeout
3. Publish per-project port status to AppState
4. Refresh on the same cycle as window detection

## Interface

```swift
final class PortChecker {
    private let appState: AppState

    init(appState: AppState)

    /// Probe all ports for all projects. Call after state load or on detection cycle.
    func checkAll() async

    /// Probe ports for a single project.
    func check(project: Project) async -> [PortStatus]
}
```

## TCP Probe Implementation

Using `NWConnection` from Network.framework for non-blocking, timeout-capable probes.

```swift
import Network

private func probe(port: Int, timeout: TimeInterval = 0.5) async -> Bool {
    let endpoint = NWEndpoint.hostPort(
        host: .ipv4(.loopback),
        port: NWEndpoint.Port(integerLiteral: UInt16(port))
    )

    let connection = NWConnection(to: endpoint, using: .tcp)

    return await withCheckedContinuation { continuation in
        var resumed = false

        connection.stateUpdateHandler = { state in
            guard !resumed else { return }
            switch state {
            case .ready:
                resumed = true
                connection.cancel()
                continuation.resume(returning: true)
            case .failed, .cancelled:
                resumed = true
                connection.cancel()
                continuation.resume(returning: false)
            case .waiting:
                // Connection waiting (e.g., no route) — treat as not listening
                resumed = true
                connection.cancel()
                continuation.resume(returning: false)
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .utility))

        // Timeout
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
            guard !resumed else { return }
            resumed = true
            connection.cancel()
            continuation.resume(returning: false)
        }
    }
}
```

### Why NWConnection over BSD Sockets?

- **Non-blocking**: NWConnection handles async state transitions natively
- **Timeout built-in**: No need to manage `select()` or `poll()` timeouts manually
- **Clean cancellation**: `connection.cancel()` tears down cleanly
- **No file descriptor management**: BSD sockets require manual `close()` on every code path

### Why Not URLSession?

`URLSession` is for HTTP. Port probing checks raw TCP connectivity — the port might be running a non-HTTP service (e.g., PostgreSQL on 5432, Redis on 6379).

## Check All Projects

```swift
func checkAll() async {
    let projects = await MainActor.run { Array(appState.state.projects.values) }

    // Probe all projects in parallel
    await withTaskGroup(of: (String, [PortStatus]).self) { group in
        for project in projects where !project.signatures.ports.isEmpty {
            group.addTask {
                let statuses = await self.check(project: project)
                return (project.name, statuses)
            }
        }

        var results: [String: [PortStatus]] = [:]
        for await (name, statuses) in group {
            results[name] = statuses
        }

        await MainActor.run {
            appState.portStatusByProject = results
        }
    }
}
```

## Single Project Check

```swift
func check(project: Project) async -> [PortStatus] {
    // Probe all ports for this project in parallel
    await withTaskGroup(of: PortStatus.self) { group in
        for port in project.signatures.ports {
            group.addTask {
                let listening = await self.probe(port: port)
                return PortStatus(port: port, isListening: listening)
            }
        }

        var statuses: [PortStatus] = []
        for await status in group {
            statuses.append(status)
        }
        return statuses.sorted { $0.port < $1.port }
    }
}
```

## Integration with Detection Cycle

Port checking runs alongside window detection, not sequentially:

```swift
// In the main polling loop:
async let windowResults = windowDetector.detectOnce()
async let portResults = portChecker.checkAll()
await windowResults
await portResults
```

This keeps the total cycle time bounded by the slowest operation (typically window detection), not the sum.

## Port Number Constraints

From the CLI codebase:
- Port scanning regex matches only 4-5 digit numbers (`\d{4,5}`)
- Ports like 80 or 443 won't appear in `signatures.ports`
- 8080, 3000, 5432, 6379 are typical values
- The macOS app probes whatever ports are in the state file — it doesn't do its own scanning

## Timeout Tuning

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Connect timeout | 500ms | Localhost connections complete in <1ms if listening. 500ms catches slow-starting services without blocking the cycle. |
| Probes per project | Typically 1-3 | Most projects have 1-2 ports (dev server + database) |
| Total probe time | < 600ms | All probes run in parallel; bounded by timeout, not count |

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Port listening | `NWConnection` reaches `.ready` state. Return `true`. |
| Port not listening | Connection refused → `.failed` state. Return `false`. |
| Port filtered (firewall) | Connection hangs → timeout at 500ms. Return `false`. |
| Port 0 in state file | Invalid port — `NWEndpoint.Port` will be 0, connection fails immediately. Fine. |
| Very high port (65535+) | `UInt16` overflow. The CLI's regex caps at 5 digits so max is 99999, but `UInt16` maxes at 65535. Clamp or skip. |
| macOS firewall prompt | First probe to a new port may trigger "allow incoming connections" dialog. This is a system-level prompt — can't be suppressed. The app is connecting to localhost, which typically doesn't trigger it. |

## Display

Port status appears as colored indicators in the project detail view:

```
● localhost:3000  Listening
○ localhost:5432  Not listening
```

- Green filled circle for listening
- Red/gray empty circle for not listening
- Font: monospace for port numbers, regular for status text

---
*Phase 5 component — runs alongside window detection in the polling cycle*
