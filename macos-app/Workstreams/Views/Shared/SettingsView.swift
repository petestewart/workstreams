import SwiftUI

struct SettingsView: View {
    @AppStorage("cliPath") private var cliPath: String = ""

    var body: some View {
        Form {
            Section("CLI Binary") {
                TextField("Path to ws", text: $cliPath)
                Text("Leave empty to auto-detect")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
    }
}
