# Data Model

Swift types that mirror the CLI's state file schema and window detection types.

## State File Types

These types decode `~/.workstreams/state.json`. Field names use `CodingKeys` to map between Swift's camelCase and the JSON's snake_case.

```swift
struct WorkstreamsState: Codable {
    var projects: [String: Project]
    var currentFocus: String?

    enum CodingKeys: String, CodingKey {
        case projects
        case currentFocus = "current_focus"
    }
}

struct Project: Codable, Identifiable {
    var id: String { name }

    let name: String
    let path: String
    var color: ProjectColor
    var status: ProjectStatus
    var parkedNote: String?
    var parkedAt: Date?
    var signatures: ProjectSignatures
    var history: [HistoryEntry]

    enum CodingKeys: String, CodingKey {
        case name, path, color, status, signatures, history
        case parkedNote = "parked_note"
        case parkedAt = "parked_at"
    }
}
```

### Enums

```swift
enum ProjectColor: String, Codable, CaseIterable {
    case red, blue, green, yellow, magenta, cyan, white

    /// Maps to SwiftUI Color for icon/dot rendering
    var swiftUIColor: Color { ... }
}

enum ProjectStatus: String, Codable {
    case active, parked
}

enum HistoryAction: Codable {
    case added, focused, parked, unparked
    case unknown(String)

    // Custom Codable: decode known cases, fallback to unknown(rawValue)
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "added": self = .added
        case "focused": self = .focused
        case "parked": self = .parked
        case "unparked": self = .unparked
        default: self = .unknown(raw)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .added: try container.encode("added")
        case .focused: try container.encode("focused")
        case .parked: try container.encode("parked")
        case .unparked: try container.encode("unparked")
        case .unknown(let raw): try container.encode(raw)
        }
    }
}
```

### Supporting Types

```swift
struct ProjectSignatures: Codable {
    var gitRemote: String?
    var ports: [Int]
    var database: String?
    var urlPatterns: [String]

    enum CodingKeys: String, CodingKey {
        case ports, database
        case gitRemote = "git_remote"
        case urlPatterns = "url_patterns"
    }
}

struct HistoryEntry: Codable, Identifiable {
    let id = UUID()  // Local only, not in JSON
    let action: HistoryAction
    let note: String?
    let at: Date

    enum CodingKeys: String, CodingKey {
        case action, note, at
    }
}
```

### Date Decoding

The state file stores ISO 8601 dates. Configure the decoder:

```swift
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
```

The CLI writes dates via `new Date().toISOString()` which produces `2026-02-09T14:30:00.000Z` format — compatible with `.iso8601`.

## Window Match Types

Mirror the CLI's discriminated union from `src/types.ts`. Use a Swift enum with associated values.

```swift
enum WindowMatch: Identifiable {
    case iterm(ItermMatch)
    case chrome(ChromeMatch)
    case generic(GenericMatch)

    var id: String {
        switch self {
        case .iterm(let m): return "iterm-\(m.windowId)-\(m.tabId)-\(m.sessionId)"
        case .chrome(let m): return "chrome-\(m.windowIndex)-\(m.tabIndex)"
        case .generic(let m): return "generic-\(m.processName)-\(m.windowTitle.hashValue)"
        }
    }

    var appName: String {
        switch self {
        case .iterm: return "iTerm"
        case .chrome: return "Chrome"
        case .generic(let m): return m.processName
        }
    }

    var displayTitle: String {
        switch self {
        case .iterm(let m): return m.title
        case .chrome(let m): return m.title
        case .generic(let m): return m.windowTitle
        }
    }
}

struct ItermMatch: Identifiable {
    let id: String  // "\(windowId)-\(tabId)-\(sessionId)"
    let windowId: String
    let tabId: String
    let sessionId: String
    let title: String
    var processInfo: ProcessInfo?  // Enriched in Phase 5
}

struct ChromeMatch: Identifiable {
    var id: String { "chrome-\(windowIndex)-\(tabIndex)" }
    let windowIndex: Int
    let tabIndex: Int
    let title: String
    let url: String
}

struct GenericMatch: Identifiable {
    var id: String { "generic-\(processName)-\(windowTitle.hashValue)" }
    let processName: String
    let windowTitle: String
}
```

## Process Info (Phase 5)

```swift
enum ProcessType {
    case claudeCode
    case devServer(command: String)  // e.g., "npm run dev"
    case idle

    var label: String {
        switch self {
        case .claudeCode: return "Claude"
        case .devServer(let cmd): return cmd
        case .idle: return "Shell: idle"
        }
    }
}

struct ProcessInfo {
    let type: ProcessType
    let duration: TimeInterval?  // nil for idle
    let pid: pid_t
}
```

## Port Status (Phase 5)

```swift
struct PortStatus: Identifiable {
    var id: Int { port }
    let port: Int
    var isListening: Bool
}
```

## AppState

The central `@Observable` model that all views bind to.

```swift
@Observable
final class AppState {
    // From StateMonitor
    var state: WorkstreamsState = WorkstreamsState(projects: [:], currentFocus: nil)
    var stateLoadError: String?

    // From WindowDetector
    var windowsByProject: [String: [WindowMatch]] = [:]

    // From PortChecker
    var portStatusByProject: [String: [PortStatus]] = [:]

    // From CLIBridge
    var cliPath: String?
    var cliError: String?

    // Permissions
    var hasAccessibilityPermission: Bool = false
    var hasAutomationPermission: Bool = false

    // Derived
    var focusedProject: Project? {
        guard let name = state.currentFocus else { return nil }
        return state.projects[name]
    }

    var activeProjects: [Project] {
        state.projects.values
            .filter { $0.status == .active }
            .sorted { $0.name < $1.name }
    }

    var parkedProjects: [Project] {
        state.projects.values
            .filter { $0.status == .parked }
            .sorted { $0.name < $1.name }
    }
}
```

## Design Notes

- **`HistoryAction.unknown(String)`**: Forward-compatible. If the CLI adds a new action type, the macOS app won't crash — it just renders the raw string.
- **`ItermMatch.processInfo` is optional**: Starts as `nil` in Phase 4 (window detection only). Phase 5 enriches it with process classification. Views check for `nil` to decide what to show.
- **`WindowMatch` is an enum, not a protocol**: Enum with associated values gives exhaustive switch, which the compiler enforces. Adding a new app type is a compile error until all views handle it.
- **No `Equatable` conformance on collections**: SwiftUI's `@Observable` diffing handles this. Don't add `Equatable` unless profiling shows unnecessary redraws.

---
*Mirrors CLI types from `src/types.ts` and `~/.workstreams/state.json` schema*
