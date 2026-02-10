import Foundation
import Network

final class PortChecker: @unchecked Sendable {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func checkAll() async {
        let projects = await MainActor.run { Array(appState.state.projects.values) }

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
                self.appState.portStatusByProject = results
            }
        }
    }

    func check(project: Project) async -> [PortStatus] {
        await withTaskGroup(of: PortStatus.self) { group in
            for port in project.signatures.ports {
                guard port > 0 && port <= 65535 else { continue }
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

    private func probe(port: Int, timeout: TimeInterval = 0.5) async -> Bool {
        let endpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(integerLiteral: UInt16(clamping: port))
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
                    resumed = true
                    connection.cancel()
                    continuation.resume(returning: false)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                continuation.resume(returning: false)
            }
        }
    }
}
