import Testing
import Foundation
@testable import Workstreams

@Suite("Model Decoding")
struct ModelDecodingTests {

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test("Decodes a full state.json with active and parked projects")
    func decodeFullState() throws {
        let json = """
        {
          "projects": {
            "workstreams": {
              "name": "workstreams",
              "path": "/Users/pete/Projects/workstreams",
              "color": "cyan",
              "status": "active",
              "parked_note": null,
              "parked_at": null,
              "signatures": {
                "git_remote": "git@github.com:pete/workstreams.git",
                "ports": [3000, 3001],
                "database": null,
                "url_patterns": ["github.com/pete/workstreams/**"]
              },
              "history": [
                {"action": "added", "at": "2026-02-01T10:00:00.000Z"},
                {"action": "focused", "note": "starting work", "at": "2026-02-09T14:30:00.000Z"}
              ]
            },
            "side-project": {
              "name": "side-project",
              "path": "/Users/pete/Projects/side-project",
              "color": "yellow",
              "status": "parked",
              "parked_note": "waiting on design review",
              "parked_at": "2026-02-08T18:00:00.000Z",
              "signatures": {
                "git_remote": null,
                "ports": [],
                "database": "side_project_dev",
                "url_patterns": []
              },
              "history": [
                {"action": "added", "at": "2026-01-15T09:00:00.000Z"},
                {"action": "parked", "note": "waiting on design review", "at": "2026-02-08T18:00:00.000Z"}
              ]
            }
          },
          "current_focus": "workstreams"
        }
        """.data(using: .utf8)!

        let state = try makeDecoder().decode(WorkstreamsState.self, from: json)

        #expect(state.currentFocus == "workstreams")
        #expect(state.projects.count == 2)

        let ws = try #require(state.projects["workstreams"])
        #expect(ws.name == "workstreams")
        #expect(ws.path == "/Users/pete/Projects/workstreams")
        #expect(ws.color == .cyan)
        #expect(ws.status == .active)
        #expect(ws.parkedNote == nil)
        #expect(ws.parkedAt == nil)
        #expect(ws.signatures.gitRemote == "git@github.com:pete/workstreams.git")
        #expect(ws.signatures.ports == [3000, 3001])
        #expect(ws.signatures.database == nil)
        #expect(ws.signatures.urlPatterns == ["github.com/pete/workstreams/**"])
        #expect(ws.history.count == 2)

        let sp = try #require(state.projects["side-project"])
        #expect(sp.status == .parked)
        #expect(sp.parkedNote == "waiting on design review")
        #expect(sp.parkedAt != nil)
        #expect(sp.signatures.database == "side_project_dev")
    }

    @Test("Decodes empty state")
    func decodeEmptyState() throws {
        let json = """
        {
          "projects": {},
          "current_focus": null
        }
        """.data(using: .utf8)!

        let state = try makeDecoder().decode(WorkstreamsState.self, from: json)
        #expect(state.projects.isEmpty)
        #expect(state.currentFocus == nil)
    }

    @Test("HistoryAction decodes known actions")
    func decodeKnownHistoryActions() throws {
        for (raw, expected): (String, HistoryAction) in [
            ("added", .added), ("focused", .focused),
            ("parked", .parked), ("unparked", .unparked)
        ] {
            let json = "\"\(raw)\"".data(using: .utf8)!
            let action = try makeDecoder().decode(HistoryAction.self, from: json)
            switch (action, expected) {
            case (.added, .added), (.focused, .focused),
                 (.parked, .parked), (.unparked, .unparked):
                break // matches
            default:
                Issue.record("Expected \(expected) but got \(action) for raw value '\(raw)'")
            }
        }
    }

    @Test("HistoryAction falls back to unknown for new action types")
    func decodeUnknownHistoryAction() throws {
        let json = """
        {"action": "archived", "at": "2026-02-09T10:00:00.000Z"}
        """.data(using: .utf8)!

        let entry = try makeDecoder().decode(HistoryEntry.self, from: json)
        if case .unknown(let raw) = entry.action {
            #expect(raw == "archived")
        } else {
            Issue.record("Expected .unknown(\"archived\") but got \(entry.action)")
        }
    }

    @Test("HistoryEntry note field is optional")
    func decodeHistoryEntryWithoutNote() throws {
        let json = """
        {"action": "added", "at": "2026-02-01T10:00:00.000Z"}
        """.data(using: .utf8)!

        let entry = try makeDecoder().decode(HistoryEntry.self, from: json)
        #expect(entry.note == nil)
    }

    @Test("ProjectColor includes all expected cases")
    func allProjectColors() {
        let expected: Set<String> = ["red", "blue", "green", "yellow", "magenta", "cyan", "white"]
        let actual = Set(ProjectColor.allCases.map { $0.rawValue })
        #expect(actual == expected)
    }

    @Test("Project conforms to Identifiable with name as id")
    func projectIdentifiable() throws {
        let json = """
        {
          "name": "test-proj",
          "path": "/tmp/test",
          "color": "red",
          "status": "active",
          "parked_note": null,
          "parked_at": null,
          "signatures": {"git_remote": null, "ports": [], "database": null, "url_patterns": []},
          "history": []
        }
        """.data(using: .utf8)!

        let project = try makeDecoder().decode(Project.self, from: json)
        #expect(project.id == "test-proj")
        #expect(project.name == "test-proj")
    }

    @Test("HistoryAction round-trips through encode/decode")
    func historyActionRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = makeDecoder()

        let cases: [HistoryAction] = [.added, .focused, .parked, .unparked, .unknown("custom")]
        for action in cases {
            let data = try encoder.encode(action)
            let decoded = try decoder.decode(HistoryAction.self, from: data)
            switch (action, decoded) {
            case (.added, .added), (.focused, .focused),
                 (.parked, .parked), (.unparked, .unparked):
                break
            case (.unknown(let a), .unknown(let b)):
                #expect(a == b)
            default:
                Issue.record("Round-trip failed for \(action)")
            }
        }
    }
}
