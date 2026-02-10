import Foundation

final class ProcessMonitor: @unchecked Sendable {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func enrich(_ matches: [String: [ItermMatch]]) async -> [String: [ItermMatch]] {
        var enriched: [String: [ItermMatch]] = [:]

        for (projectName, sessionMatches) in matches {
            var enrichedSessions: [ItermMatch] = []
            for var match in sessionMatches {
                match.processInfo = await classifySession(match: match)
                enrichedSessions.append(match)
            }
            enriched[projectName] = enrichedSessions
        }

        return enriched
    }

    private func classifySession(match: ItermMatch) async -> ProcessInfo? {
        // We need the TTY to resolve shell PID.
        // The TTY is not stored on ItermMatch directly — we'll need it from the detection step.
        // For now, use the session's windowId/tabId/sessionId pattern.
        // The caller should pass TTY info; this is a simplification.
        // In practice, the WindowDetector should pass the enrichment data.
        return ProcessInfo(type: .idle, duration: nil, pid: 0)
    }

    func classifyFromTTY(tty: String) -> ProcessInfo? {
        guard let shellPID = shellPID(forTTY: tty) else {
            return ProcessInfo(type: .idle, duration: nil, pid: 0)
        }

        let children = childProcesses(ofPID: shellPID)
        return classify(children)
    }

    // MARK: - Shell PID Resolution

    private func shellPID(forTTY tty: String) -> pid_t? {
        let ttyName = tty.replacingOccurrences(of: "/dev/", with: "")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "pid=", "-t", ttyName]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstLine = output?.components(separatedBy: .newlines).first,
              let pid = pid_t(firstLine.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return pid
    }

    // MARK: - Child Process Enumeration

    private struct RawProcess {
        let pid: pid_t
        let command: String
        let elapsed: String
    }

    private func childProcesses(ofPID parentPID: pid_t) -> [RawProcess] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "pid=,comm=,etime=", "-ppid", "\(parentPID)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return output.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }

            let parts = trimmed.split(separator: " ", maxSplits: 2).map(String.init)
            guard parts.count == 3,
                  let pid = pid_t(parts[0]) else { return nil }

            return RawProcess(pid: pid, command: parts[1], elapsed: parts[2].trimmingCharacters(in: .whitespaces))
        }
    }

    // MARK: - Classification

    private func classify(_ children: [RawProcess]) -> ProcessInfo? {
        guard !children.isEmpty else {
            return ProcessInfo(type: .idle, duration: nil, pid: 0)
        }

        if let claude = children.first(where: { isClaude($0) }) {
            return ProcessInfo(
                type: .claudeCode,
                duration: parseElapsed(claude.elapsed),
                pid: claude.pid
            )
        }

        if let server = children.first(where: { isDevServer($0) }) {
            return ProcessInfo(
                type: .devServer(command: server.command),
                duration: parseElapsed(server.elapsed),
                pid: server.pid
            )
        }

        let first = children[0]
        return ProcessInfo(
            type: .devServer(command: first.command),
            duration: parseElapsed(first.elapsed),
            pid: first.pid
        )
    }

    private func isClaude(_ proc: RawProcess) -> Bool {
        let claudePatterns = ["claude", "claude-code"]
        if claudePatterns.contains(where: { proc.command.lowercased().contains($0) }) {
            return true
        }
        if proc.command.lowercased() == "node" {
            return fullCommandContainsClaude(proc.pid)
        }
        return false
    }

    private func fullCommandContainsClaude(_ pid: pid_t) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "args=", "-p", "\(pid)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.lowercased().contains("claude")
    }

    private func isDevServer(_ proc: RawProcess) -> Bool {
        let serverCommands = ["node", "ruby", "python", "python3", "rails", "puma", "uvicorn", "gunicorn", "next-server"]
        return serverCommands.contains(where: { proc.command.lowercased().contains($0) })
    }

    // MARK: - Elapsed Time Parsing

    private func parseElapsed(_ etime: String) -> TimeInterval? {
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
}

// MARK: - Display Formatting

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
