import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum PollingRate {
    case fullRate      // 7s — dashboard or dropdown visible
    case reducedRate   // 30s — menu-bar-only mode

    var interval: TimeInterval {
        switch self {
        case .fullRate: return 7
        case .reducedRate: return 30
        }
    }
}

final class WindowDetector: @unchecked Sendable {
    private let appState: AppState
    private let processMonitor: ProcessMonitor
    private let portChecker: PortChecker
    private var pollingTask: Task<Void, Never>?
    private var isPolling: Bool = false
    private var currentRate: PollingRate?

    private static let it2apiPath = "/Applications/iTerm.app/Contents/Resources/utilities/it2api"
    private var hasIt2api: Bool = false
    private var permissionCheckCounter: Int = 0

    init(appState: AppState, processMonitor: ProcessMonitor, portChecker: PortChecker) {
        self.appState = appState
        self.processMonitor = processMonitor
        self.portChecker = portChecker
        self.hasIt2api = FileManager.default.isExecutableFile(atPath: Self.it2apiPath)
    }

    func startPolling(interval rate: PollingRate) {
        guard currentRate != rate || !isPolling else { return }
        stopPolling()
        currentRate = rate
        isPolling = true
        permissionCheckCounter = 0

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.detectOnce()

                // Re-check permissions every ~30s: every cycle for reducedRate, every 4th for fullRate
                self.permissionCheckCounter += 1
                let checkInterval = rate == .reducedRate ? 1 : 4
                if self.permissionCheckCounter >= checkInterval {
                    self.permissionCheckCounter = 0
                    await self.recheckPermissions()
                }

                try? await Task.sleep(for: .seconds(rate.interval))
            }
        }
    }

    func stopPolling() {
        isPolling = false
        currentRate = nil
        pollingTask?.cancel()
        pollingTask = nil
    }

    func detectOnce() async {
        let projects = await MainActor.run { Array(appState.state.projects.values) }
        guard !projects.isEmpty else { return }

        let validProjects = projects.filter { $0.pathExists }

        #if canImport(AppKit)
        let runningApps = checkRunningApps()

        async let itermMatches = runningApps.contains("iTerm2") && hasIt2api
            ? detectIterm(projects: validProjects)
            : [:]
        async let chromeMatches = runningApps.contains("Google Chrome")
            ? detectChrome(projects: validProjects)
            : [:]
        async let genericMatches = detectGeneric(projects: validProjects, exclude: ["iTerm2", "Google Chrome"])
        async let portResults: Void = portChecker.checkAll()

        var iterm = await itermMatches
        let chrome = await chromeMatches
        let generic = await genericMatches
        await portResults

        // Enrich iTerm matches with process info
        iterm = await enrichItermMatches(iterm)

        var merged: [String: [WindowMatch]] = [:]
        for project in projects {
            var matches: [WindowMatch] = []
            if let im = iterm[project.name] { matches += im.map { .iterm($0) } }
            if let cm = chrome[project.name] { matches += cm.map { .chrome($0) } }
            if let gm = generic[project.name] { matches += gm.map { .generic($0) } }
            if !matches.isEmpty {
                merged[project.name] = matches
            }
        }

        await MainActor.run {
            appState.windowsByProject = merged
        }
        #endif
    }

    private func enrichItermMatches(_ matches: [String: [ItermMatch]]) async -> [String: [ItermMatch]] {
        var enriched: [String: [ItermMatch]] = [:]
        for (name, sessions) in matches {
            enriched[name] = sessions.map { match in
                var enrichedMatch = match
                if let tty = match.tty {
                    enrichedMatch.processInfo = processMonitor.classifyFromTTY(tty: tty)
                }
                return enrichedMatch
            }
        }
        return enriched
    }

    // MARK: - Permission Check

    static func checkPermissions() async -> (accessibility: Bool, automation: Bool) {
        #if canImport(AppKit)
        let accessibility = AXIsProcessTrusted()

        let testScript = """
        tell application "System Events"
            return name of first process whose frontmost is true
        end tell
        """
        let automation = await AppleScriptRunner.executeAsync(testScript) != nil

        return (accessibility, automation)
        #else
        return (false, false)
        #endif
    }

    private func recheckPermissions() async {
        let bothGranted = await MainActor.run {
            appState.hasAccessibilityPermission && appState.hasAutomationPermission
        }
        guard !bothGranted else { return }

        let perms = await Self.checkPermissions()
        let hadAccessibility = await MainActor.run { appState.hasAccessibilityPermission }
        let hadAutomation = await MainActor.run { appState.hasAutomationPermission }

        let transitioned = (!hadAccessibility && perms.accessibility) || (!hadAutomation && perms.automation)

        await MainActor.run {
            appState.hasAccessibilityPermission = perms.accessibility
            appState.hasAutomationPermission = perms.automation
        }

        // Trigger immediate detection on permission grant
        if transitioned {
            await detectOnce()
        }
    }

    // MARK: - Running Apps

    #if canImport(AppKit)
    private func checkRunningApps() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications
            .filter { !$0.isHidden }
            .compactMap { $0.localizedName })
    }
    #endif

    // MARK: - iTerm Detection

    private func detectIterm(projects: [Project]) async -> [String: [ItermMatch]] {
        guard let hierarchyJSON = runProcess(Self.it2apiPath, arguments: ["show-hierarchy"]) else {
            return [:]
        }

        guard let data = hierarchyJSON.data(using: .utf8),
              let windows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }

        var matches: [String: [ItermMatch]] = [:]

        for window in windows {
            guard let windowId = window["id"] as? String,
                  let tabs = window["tabs"] as? [[String: Any]] else { continue }

            for tab in tabs {
                guard let tabId = tab["id"] as? String,
                      let sessions = tab["sessions"] as? [[String: Any]] else { continue }

                for session in sessions {
                    guard let sessionId = session["id"] as? String,
                          let tty = session["tty"] as? String else { continue }

                    let title = session["name"] as? String ?? "Session"

                    guard let cwd = resolveCWD(tty: tty) else { continue }

                    for project in projects {
                        if matchesProject(cwd, project: project) {
                            let match = ItermMatch(
                                id: "\(windowId)-\(tabId)-\(sessionId)",
                                windowId: windowId,
                                tabId: tabId,
                                sessionId: sessionId,
                                title: title,
                                tty: tty
                            )
                            matches[project.name, default: []].append(match)
                        }
                    }
                }
            }
        }

        return matches
    }

    private func resolveCWD(tty: String) -> String? {
        // Get shell PID from TTY
        let ttyShort = tty.replacingOccurrences(of: "/dev/", with: "")
        guard let pidStr = runProcess("/bin/ps", arguments: ["-o", "pid=", "-t", ttyShort]),
              let pid = pidStr.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first?
                .trimmingCharacters(in: .whitespaces) else {
            return nil
        }

        // Get CWD via lsof
        guard let lsofOutput = runProcess("/usr/sbin/lsof", arguments: ["-a", "-p", pid, "-d", "cwd", "-Fn"]) else {
            return nil
        }

        for line in lsofOutput.components(separatedBy: .newlines) {
            if line.hasPrefix("n") && line.count > 1 {
                return String(line.dropFirst())
            }
        }

        return nil
    }

    private func matchesProject(_ cwd: String, project: Project) -> Bool {
        let normalizedCWD = (cwd as NSString).standardizingPath
        let normalizedPath = (project.path as NSString).standardizingPath
        return normalizedCWD.hasPrefix(normalizedPath)
    }

    // MARK: - Chrome Detection

    private func detectChrome(projects: [Project]) async -> [String: [ChromeMatch]] {
        #if canImport(AppKit)
        let script = """
        tell application "Google Chrome"
            set allTabs to ""
            repeat with w from 1 to (count of windows)
                repeat with t from 1 to (count of tabs of window w)
                    set tabURL to URL of tab t of window w
                    set tabTitle to title of tab t of window w
                    set allTabs to allTabs & w & "\\t" & t & "\\t" & tabURL & "\\t" & tabTitle & "\\n"
                end repeat
            end repeat
            return allTabs
        end tell
        """

        guard let result = await AppleScriptRunner.executeAsync(script),
              let output = result.stringValue else {
            return [:]
        }

        var matches: [String: [ChromeMatch]] = [:]

        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 4,
                  let windowIndex = Int(parts[0]),
                  let tabIndex = Int(parts[1]) else { continue }

            let url = parts[2]
            let title = parts[3]

            for project in projects {
                for pattern in project.signatures.urlPatterns {
                    let normalized = normalizeURLPattern(pattern)
                    if url.contains(normalized) {
                        let match = ChromeMatch(
                            windowIndex: windowIndex,
                            tabIndex: tabIndex,
                            title: title,
                            url: url
                        )
                        matches[project.name, default: []].append(match)
                        break
                    }
                }
            }
        }

        return matches
        #else
        return [:]
        #endif
    }

    private func normalizeURLPattern(_ pattern: String) -> String {
        var normalized = pattern
        if normalized.hasSuffix("/**") {
            normalized = String(normalized.dropLast(3))
        }
        return normalized
    }

    // MARK: - Generic Detection

    private func detectGeneric(projects: [Project], exclude: [String]) async -> [String: [GenericMatch]] {
        #if canImport(AppKit)
        let script = """
        tell application "System Events"
            set results to ""
            repeat with proc in (every process whose background only is false)
                set procName to name of proc
                try
                    repeat with w in (every window of proc)
                        set winTitle to name of w
                        set results to results & procName & "\\t" & winTitle & "\\n"
                    end repeat
                end try
            end repeat
            return results
        end tell
        """

        guard let result = await AppleScriptRunner.executeAsync(script),
              let output = result.stringValue else {
            return [:]
        }

        var matches: [String: [GenericMatch]] = [:]

        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }

            let processName = parts[0]
            let windowTitle = parts[1]

            guard !exclude.contains(processName) else { continue }

            for project in projects {
                if windowTitle.localizedCaseInsensitiveContains(project.name) {
                    let match = GenericMatch(processName: processName, windowTitle: windowTitle)
                    matches[project.name, default: []].append(match)
                }
            }
        }

        return matches
        #else
        return [:]
        #endif
    }

    // MARK: - Activation

    func activateItermSession(_ match: ItermMatch) async {
        guard hasIt2api else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.it2apiPath)
        process.arguments = ["activate", match.sessionId]
        try? process.run()
        process.waitUntilExit()

        #if canImport(AppKit)
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/iTerm.app"))
        #endif
    }

    func activateChromeTab(_ match: ChromeMatch) async {
        #if canImport(AppKit)
        let script = """
        tell application "Google Chrome"
            set active tab index of window \(match.windowIndex) to \(match.tabIndex)
            set index of window \(match.windowIndex) to 1
            activate
        end tell
        """
        _ = await AppleScriptRunner.executeAsync(script)
        #endif
    }

    func activateGenericWindow(_ match: GenericMatch) async {
        #if canImport(AppKit)
        let escaped = escapeAppleScript(match.processName)
        let script = """
        tell application "System Events"
            set frontmost of process "\(escaped)" to true
        end tell
        """
        _ = await AppleScriptRunner.executeAsync(script)
        #endif
    }

    // MARK: - Process Helper

    private func runProcess(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
