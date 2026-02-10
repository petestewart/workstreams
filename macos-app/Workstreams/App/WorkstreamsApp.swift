import SwiftUI

@main
struct WorkstreamsApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            Text("Workstreams")
                .padding()
        } label: {
            Image(systemName: "circle.fill")
                .foregroundStyle(.gray)
        }
        .menuBarExtraStyle(.window)

        Window("Workstreams", id: "dashboard") {
            Text("Dashboard — coming soon")
                .frame(minWidth: 400, minHeight: 300)
        }
        .defaultSize(width: 900, height: 600)
    }
}
