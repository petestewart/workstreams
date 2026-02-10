import Foundation

final class StateMonitor: @unchecked Sendable {
    private let filePath: String
    private let appState: AppState
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var fallbackTimer: DispatchSourceTimer?
    private var lastGoodState: WorkstreamsState?
    private var fileDescriptor: Int32 = -1

    init(appState: AppState) {
        self.filePath = NSHomeDirectory() + "/.workstreams/state.json"
        self.appState = appState
    }

    func start() {
        loadState()

        fileDescriptor = open(filePath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            startPollingFallback()
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .global(qos: .utility)
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data

            if flags.contains(.delete) || flags.contains(.rename) {
                self.reopenFileWatch()
            } else {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.1) {
                    self.loadState()
                }
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }

        source.resume()
        dispatchSource = source
    }

    func stop() {
        dispatchSource?.cancel()
        dispatchSource = nil
        fallbackTimer?.cancel()
        fallbackTimer = nil
    }

    private func reopenFileWatch() {
        dispatchSource?.cancel()
        dispatchSource = nil

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.start()
        }
    }

    private func startPollingFallback() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            self?.loadState()
        }
        timer.resume()
        fallbackTimer = timer
    }

    private func loadState() {
        let maxRetries = 3
        let retryDelay: UInt64 = 50_000_000 // 50ms

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            for attempt in 0..<maxRetries {
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: self.filePath))
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let state = try decoder.decode(WorkstreamsState.self, from: data)

                    self.lastGoodState = state
                    await MainActor.run {
                        self.appState.state = state
                        self.appState.stateLoadError = nil
                    }
                    return
                } catch {
                    if attempt < maxRetries - 1 {
                        try? await Task.sleep(nanoseconds: retryDelay)
                    } else {
                        await MainActor.run {
                            if self.lastGoodState != nil {
                                self.appState.stateLoadError = "State file read error (showing cached): \(error.localizedDescription)"
                            } else {
                                self.appState.stateLoadError = "Cannot read state file: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
        }
    }
}
