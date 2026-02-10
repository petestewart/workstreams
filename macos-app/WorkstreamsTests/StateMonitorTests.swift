import Testing
import Foundation
@testable import Workstreams

@Suite("StateMonitor")
struct StateMonitorTests {

    @Test("loadState decodes valid state.json content")
    @MainActor
    func decodesValidState() async throws {
        // Verify decoder setup matches what StateMonitor uses
        let json = """
        {
          "projects": {
            "test-proj": {
              "name": "test-proj",
              "path": "/tmp/test",
              "color": "blue",
              "status": "active",
              "parked_note": null,
              "parked_at": null,
              "signatures": {"git_remote": null, "ports": [3000], "database": null, "url_patterns": []},
              "history": [{"action": "added", "at": "2026-02-01T10:00:00.000Z"}]
            }
          },
          "current_focus": "test-proj"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(WorkstreamsState.self, from: json)

        #expect(state.currentFocus == "test-proj")
        #expect(state.projects.count == 1)

        let proj = try #require(state.projects["test-proj"])
        #expect(proj.color == .blue)
        #expect(proj.signatures.ports == [3000])
        #expect(proj.history.count == 1)
    }

    @Test("AppState starts with empty state")
    @MainActor
    func appStateStartsEmpty() {
        let appState = AppState()
        #expect(appState.state.projects.isEmpty)
        #expect(appState.state.currentFocus == nil)
        #expect(appState.stateLoadError == nil)
        #expect(appState.focusedProject == nil)
        #expect(appState.activeProjects.isEmpty)
        #expect(appState.parkedProjects.isEmpty)
    }

    @Test("AppState derived properties update correctly")
    @MainActor
    func appStateDerivedProperties() throws {
        let json = """
        {
          "projects": {
            "alpha": {
              "name": "alpha", "path": "/tmp/a", "color": "red", "status": "active",
              "parked_note": null, "parked_at": null,
              "signatures": {"git_remote": null, "ports": [], "database": null, "url_patterns": []},
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
              "signatures": {"git_remote": null, "ports": [], "database": null, "url_patterns": []},
              "history": []
            }
          },
          "current_focus": "alpha"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(WorkstreamsState.self, from: json)

        let appState = AppState()
        appState.state = state

        #expect(appState.focusedProject?.name == "alpha")
        #expect(appState.activeProjects.count == 2)
        #expect(appState.activeProjects.map(\.name) == ["alpha", "gamma"]) // sorted
        #expect(appState.parkedProjects.count == 1)
        #expect(appState.parkedProjects.first?.name == "beta")
    }
}
