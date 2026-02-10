import SwiftUI

struct PortStatusView: View {
    let ports: [PortStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ports")
                .font(.headline)

            ForEach(ports) { port in
                HStack(spacing: 8) {
                    Circle()
                        .fill(port.isListening ? .green : .red.opacity(0.5))
                        .frame(width: 8, height: 8)
                    Text("localhost:\(port.port)")
                        .font(.system(.caption, design: .monospaced))
                    Text(port.isListening ? "Listening" : "Not listening")
                        .font(.caption)
                        .foregroundStyle(port.isListening ? .primary : .secondary)
                }
            }
        }
    }
}
