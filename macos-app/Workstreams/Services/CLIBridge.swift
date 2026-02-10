import Foundation

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

final class CLIBridge: @unchecked Sendable {
    private let appState: AppState
    private var resolvedPath: String?

    init(appState: AppState) {
        self.appState = appState
    }

    func discoverCLI() async {
        // 1. UserDefaults override
        if let userPath = UserDefaults.standard.string(forKey: "cliPath"),
           !userPath.isEmpty,
           FileManager.default.isExecutableFile(atPath: userPath) {
            resolvedPath = userPath
            await publish(path: userPath)
            return
        }

        // 2. `which ws` via login shell
        if let whichResult = try? shellWhich("ws") {
            resolvedPath = whichResult
            await publish(path: whichResult)
            return
        }

        // 3. Common locations
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
            self.appState.cliPath = nil
            self.appState.cliError = "Could not find 'ws' CLI. Install it or set the path in Settings."
        }
    }

    func retryDiscovery() async {
        await MainActor.run {
            self.appState.cliError = nil
        }
        await discoverCLI()
    }

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

    // MARK: - Convenience Methods

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

    // MARK: - Private

    private func publish(path: String) async {
        await MainActor.run {
            self.appState.cliPath = path
            self.appState.cliError = nil
        }
    }

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
}
