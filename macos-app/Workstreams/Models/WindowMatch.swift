import Foundation

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
    let id: String
    let windowId: String
    let tabId: String
    let sessionId: String
    let title: String
    let tty: String?
    var processInfo: ProcessInfo?
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

enum ProcessType {
    case claudeCode
    case devServer(command: String)
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
    let duration: TimeInterval?
    let pid: pid_t
}

struct PortStatus: Identifiable {
    var id: Int { port }
    let port: Int
    var isListening: Bool
}
