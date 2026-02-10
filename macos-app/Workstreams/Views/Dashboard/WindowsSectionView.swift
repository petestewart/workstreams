import SwiftUI

struct WindowsSectionView: View {
    let windows: [WindowMatch]
    let windowDetector: WindowDetector?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Windows")
                .font(.headline)

            ForEach(groupedWindows, id: \.appName) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(group.appName) (\(group.matches.count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(group.matches) { match in
                        WindowCard(match: match, windowDetector: windowDetector)
                    }
                }
            }
        }
    }

    private var groupedWindows: [WindowGroup] {
        var groups: [String: [WindowMatch]] = [:]
        for window in windows {
            groups[window.appName, default: []].append(window)
        }
        return groups.map { WindowGroup(appName: $0.key, matches: $0.value) }
            .sorted { $0.appName < $1.appName }
    }
}

private struct WindowGroup {
    let appName: String
    let matches: [WindowMatch]
}

struct WindowCard: View {
    let match: WindowMatch
    let windowDetector: WindowDetector?

    var body: some View {
        Button {
            Task { await activate() }
        } label: {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.displayTitle)
                        .lineLimit(1)
                    if let detail = detailText {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.forward.square")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .padding(8)
            .background(.quaternary.opacity(0.3))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch match {
        case .iterm: return "terminal"
        case .chrome: return "globe"
        case .generic: return "macwindow"
        }
    }

    private var detailText: String? {
        switch match {
        case .iterm(let m):
            if let info = m.processInfo {
                return info.displayLabel
            }
            return nil
        case .chrome(let m):
            return m.url
        case .generic:
            return nil
        }
    }

    private func activate() async {
        guard let windowDetector else { return }
        switch match {
        case .iterm(let m):
            await windowDetector.activateItermSession(m)
        case .chrome(let m):
            await windowDetector.activateChromeTab(m)
        case .generic(let m):
            await windowDetector.activateGenericWindow(m)
        }
    }
}
