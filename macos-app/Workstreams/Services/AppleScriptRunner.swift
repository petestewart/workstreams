import Foundation

func escapeAppleScript(_ string: String) -> String {
    string
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}

#if canImport(AppKit)
import AppKit

enum AppleScriptRunner {
    static func execute(_ source: String) -> NSAppleEventDescriptor? {
        let script = NSAppleScript(source: source)
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)

        if let error {
            print("AppleScript error: \(error)")
        }

        return result
    }

    static func executeAsync(_ source: String) async -> NSAppleEventDescriptor? {
        await Task.detached(priority: .utility) {
            execute(source)
        }.value
    }
}
#endif
