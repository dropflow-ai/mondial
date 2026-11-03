import Foundation

/// Login item support through a small LaunchAgent.
///
/// `SMAppService` would be the modern API, but it insists on a properly signed app bundle in
/// `/Applications`. A LaunchAgent works for locally built, ad-hoc signed bundles too.
enum LoginItem {
    static let label = "ch.dropflow.screenmix.agent"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable()
        }
    }

    private static func enable() {
        guard let executable = Bundle.main.executablePath else { return }
        let payload: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua"
        ]

        guard let data = try? PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0) else {
            return
        }
        let url = plistURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url)

        _ = runLaunchctl(["bootstrap", "gui/\(getuid())", url.path])
    }

    private static func disable() {
        let url = plistURL
        _ = runLaunchctl(["bootout", "gui/\(getuid())", url.path])
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
