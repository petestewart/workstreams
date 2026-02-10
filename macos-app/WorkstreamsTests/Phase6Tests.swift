import Testing
import Foundation
@testable import Workstreams

@Suite("Phase 6 — Overview Grid, Park Action, Permissions")
struct Phase6Tests {

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - TimeFormatting

    @Test("timeAgo returns 'just now' for recent dates")
    func timeAgoJustNow() {
        let result = timeAgo(from: Date())
        #expect(result == "just now")
    }

    @Test("timeAgo returns minutes for dates less than an hour ago")
    func timeAgoMinutes() {
        let result = timeAgo(from: Date().addingTimeInterval(-300)) // 5 minutes ago
        #expect(result == "5m ago")
    }

    @Test("timeAgo returns hours for dates less than a day ago")
    func timeAgoHours() {
        let result = timeAgo(from: Date().addingTimeInterval(-7200)) // 2 hours ago
        #expect(result == "2h ago")
    }

    @Test("timeAgo returns 'yesterday' for dates 24-48 hours ago")
    func timeAgoYesterday() {
        let result = timeAgo(from: Date().addingTimeInterval(-90000)) // 25 hours ago
        #expect(result == "yesterday")
    }

    @Test("timeAgo returns days for dates more than 48 hours ago")
    func timeAgoDays() {
        let result = timeAgo(from: Date().addingTimeInterval(-259200)) // 3 days ago
        #expect(result == "3d ago")
    }

    // MARK: - ProcessInfo displayLabel

    @Test("ProcessInfo displayLabel shows Claude active with duration")
    func displayLabelClaude() {
        let info = ProcessInfo(type: .claudeCode, duration: 720, pid: 1234) // 12 minutes
        #expect(info.displayLabel == "Claude: active (12m)")
    }

    @Test("ProcessInfo displayLabel shows dev server command")
    func displayLabelDevServer() {
        let info = ProcessInfo(type: .devServer(command: "node"), duration: 2700, pid: 5678) // 45 minutes
        #expect(info.displayLabel == "node (45m)")
    }

    @Test("ProcessInfo displayLabel shows idle with duration")
    func displayLabelIdle() {
        let info = ProcessInfo(type: .idle, duration: 120, pid: 9999) // 2 minutes
        #expect(info.displayLabel == "Shell: idle (2m)")
    }

    @Test("ProcessInfo displayLabel handles hours")
    func displayLabelHours() {
        let info = ProcessInfo(type: .devServer(command: "ruby"), duration: 5400, pid: 1000) // 1h 30m
        #expect(info.displayLabel == "ruby (1h 30m)")
    }

    @Test("ProcessInfo displayLabel handles nil duration")
    func displayLabelNoDuration() {
        let info = ProcessInfo(type: .idle, duration: nil, pid: 1000)
        #expect(info.displayLabel == "Shell: idle")
    }

    // MARK: - WindowMatch properties

    @Test("WindowMatch appName returns correct app names")
    func windowMatchAppNames() {
        let iterm = WindowMatch.iterm(ItermMatch(
            id: "w-t-s", windowId: "w", tabId: "t", sessionId: "s", title: "Test", tty: nil
        ))
        let chrome = WindowMatch.chrome(ChromeMatch(
            windowIndex: 1, tabIndex: 1, title: "Test", url: "http://localhost"
        ))
        let generic = WindowMatch.generic(GenericMatch(
            processName: "VS Code", windowTitle: "project"
        ))

        #expect(iterm.appName == "iTerm")
        #expect(chrome.appName == "Chrome")
        #expect(generic.appName == "VS Code")
    }

    @Test("WindowMatch displayTitle returns correct titles")
    func windowMatchDisplayTitles() {
        let iterm = WindowMatch.iterm(ItermMatch(
            id: "w-t-s", windowId: "w", tabId: "t", sessionId: "s", title: "my-project — zsh", tty: nil
        ))
        let chrome = WindowMatch.chrome(ChromeMatch(
            windowIndex: 1, tabIndex: 1, title: "Pull Request #42", url: "http://github.com/pr/42"
        ))

        #expect(iterm.displayTitle == "my-project — zsh")
        #expect(chrome.displayTitle == "Pull Request #42")
    }

    // MARK: - AppState with overview scenario

    @Test("AppState provides correct project lists for overview grid")
    @MainActor
    func appStateOverviewGrid() throws {
        let json = """
        {
          "projects": {
            "alpha": {
              "name": "alpha", "path": "/tmp/a", "color": "red", "status": "active",
              "parked_note": null, "parked_at": null,
              "signatures": {"git_remote": null, "ports": [3000], "database": null, "url_patterns": []},
              "history": []
            },
            "beta": {
              "name": "beta", "path": "/tmp/b", "color": "green", "status": "parked",
              "parked_note": "on hold", "parked_at": "2026-02-08T12:00:00.000Z",
              "signatures": {"git_remote": null, "ports": [], "database": null, "url_patterns": []},
              "history": []
            },
            "gamma": {
              "name": "gamma", "path": "/tmp/g", "color": "blue", "status": "active",
              "parked_note": null, "parked_at": null,
              "signatures": {"git_remote": null, "ports": [8080, 5432], "database": null, "url_patterns": []},
              "history": []
            }
          },
          "current_focus": "alpha"
        }
        """.data(using: .utf8)!

        let state = try makeDecoder().decode(WorkstreamsState.self, from: json)
        let appState = AppState()
        appState.state = state

        // Overview grid iterates active + parked
        let allProjects = appState.activeProjects + appState.parkedProjects
        #expect(allProjects.count == 3)
        #expect(allProjects.map(\.name) == ["alpha", "gamma", "beta"])

        // Focused project identified correctly
        #expect(appState.focusedProject?.name == "alpha")

        // Parked project has note
        let parked = appState.parkedProjects.first
        #expect(parked?.parkedNote == "on hold")
    }

    @Test("AppState window and port data available for overview card signals")
    @MainActor
    func appStateSignalData() {
        let appState = AppState()

        // Set up window data like WindowDetector would
        appState.windowsByProject = [
            "alpha": [
                .iterm(ItermMatch(
                    id: "w1-t1-s1", windowId: "w1", tabId: "t1", sessionId: "s1",
                    title: "alpha — zsh", tty: "/dev/ttys001",
                    processInfo: ProcessInfo(type: .claudeCode, duration: 600, pid: 1234)
                )),
                .iterm(ItermMatch(
                    id: "w1-t1-s2", windowId: "w1", tabId: "t1", sessionId: "s2",
                    title: "alpha — server", tty: "/dev/ttys002",
                    processInfo: ProcessInfo(type: .devServer(command: "node"), duration: 3600, pid: 5678)
                )),
            ]
        ]
        appState.portStatusByProject = [
            "alpha": [
                PortStatus(port: 3000, isListening: true),
                PortStatus(port: 5432, isListening: false),
            ]
        ]

        // Card would check: window count
        let windows = appState.windowsByProject["alpha"]!
        #expect(windows.count == 2)

        // Card would check: Claude active
        let hasClaudeActive = windows.contains { match in
            if case .iterm(let m) = match, let info = m.processInfo {
                if case .claudeCode = info.type { return true }
            }
            return false
        }
        #expect(hasClaudeActive)

        // Card would check: listening ports
        let listeningPorts = appState.portStatusByProject["alpha"]!.filter(\.isListening)
        #expect(listeningPorts.count == 1)
        #expect(listeningPorts.first?.port == 3000)
    }

    // MARK: - Permission state

    @Test("AppState permission defaults are false")
    @MainActor
    func defaultPermissions() {
        let appState = AppState()
        #expect(appState.hasAccessibilityPermission == false)
        #expect(appState.hasAutomationPermission == false)
    }

    // MARK: - PortStatus

    @Test("PortStatus isListening correctly identifies listening ports")
    func portStatusListening() {
        let listening = PortStatus(port: 3000, isListening: true)
        let notListening = PortStatus(port: 5432, isListening: false)

        #expect(listening.isListening == true)
        #expect(notListening.isListening == false)
    }

    @Test("PortStatus Identifiable uses port as id")
    func portStatusIdentifiable() {
        let status = PortStatus(port: 8080, isListening: true)
        #expect(status.id == 8080)
    }

    // MARK: - ProcessType label

    @Test("ProcessType label returns correct strings")
    func processTypeLabels() {
        #expect(ProcessType.claudeCode.label == "Claude")
        #expect(ProcessType.devServer(command: "node").label == "node")
        #expect(ProcessType.idle.label == "Shell: idle")
    }
}
