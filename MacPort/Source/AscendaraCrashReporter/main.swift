import AppKit
import Foundation

private enum ReportTool {
    static let names: [String: String] = [
        "gofilehelper": "Ascendara GoFile Helper",
        "maindownloader": "Ascendara Downloader",
        "gamehandler": "Ascendara Game Handler",
        "toplevel": "Ascendara",
        "languagetranslation": "Ascendara Language Translation",
        "torrenthandler": "Ascendara Torrent Handler",
        "notificationhelper": "Ascendara Notification Helper",
        "achievementwatcher": "Ascendara Achievement Watcher",
        "localrefresh": "Ascendara Local Refresh"
    ]
    static let descriptions: [Int: String] = [
        1000: "An unknown error occurred", 1001: "An unhandled exception occurred",
        1002: "An unhandled rejection occurred", 1003: "A network error occurred",
        1004: "Invalid data received", 1100: "Game not found",
        1101: "Failed to launch game", 1102: "Game configuration error",
        1103: "Game process error", 1104: "Settings file error",
        1105: "Download directory error",
        1200: "Language Translation API error occurred",
        1201: "Language Translation rate limit exceeded",
        1202: "Error processing file for Language Translation operation",
        1300: "GoFile API error occurred", 1301: "Failed to upload file to GoFile",
        1302: "Failed to download file from GoFile", 1303: "GoFile authentication failed",
        1304: "GoFile rate limit exceeded", 1305: "Error processing file for GoFile operation",
        1400: "Failed to initialize download",
        1401: "Error updating download progress", 1402: "Failed to cancel download",
        1403: "Download verification failed", 1404: "Failed to extract downloaded files",
        1405: "Error during cleanup", 1406: "Settings file error",
        1407: "Library file error", 1408: "Failed to launch helper process",
        1500: "Torrent API error occurred", 1501: "Failed to add torrent",
        1502: "Failed to remove torrent", 1503: "Failed to get torrent status",
        1504: "Torrent configuration error", 1505: "Error processing torrent file",
        1506: "Failed to install torrent content",
        1600: "Failed to initialize notification", 1601: "Failed to display notification",
        1602: "Invalid or unsupported theme", 1603: "Failed to load notification resources",
        1604: "Error during notification animation"
    ]
}

@MainActor
private final class Reporter: NSObject, NSApplicationDelegate {
    private let tool: String
    private let code: Int
    private let detail: String

    init(tool: String, code: Int, detail: String) {
        self.tool = tool.lowercased()
        self.code = code
        self.detail = detail
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let title = tool == "toplevel" ? "Ascendara stopped working" : "An Ascendara utility stopped working"
        let toolName = ReportTool.names[tool] ?? "Ascendara utility"
        let description = ReportTool.descriptions[code] ?? "An error occurred"
        let report = "\(toolName) · Error \(code)\n\(description)\n\n\(detail)"
        persist(report)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = "\(toolName): \(description)\n\n\(detail)"
        alert.addButton(withTitle: "Copy Details")
        alert.addButton(withTitle: "Get Support")
        alert.addButton(withTitle: "Restart Ascendara")
        alert.addButton(withTitle: "Close")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        case .alertSecondButtonReturn:
            if let supportURL = URL(string: "https://ascendara.app/discord") {
                NSWorkspace.shared.open(supportURL)
            }
        case .alertThirdButtonReturn:
            let app = Bundle.main.bundleURL
            if app.pathExtension == "app" { NSWorkspace.shared.open(app) }
            else if let executable = ProcessInfo.processInfo.environment["ASCENDARA_APP_EXECUTABLE"] {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                try? process.run()
            }
        default: break
        }
        NSApp.terminate(nil)
    }

    private func persist(_ report: String) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ascendara Native/Crash Reports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let formatter = ISO8601DateFormatter()
            let file = folder.appendingPathComponent(formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-") + ".txt")
            let data = Data(report.utf8)
            guard FileManager.default.createFile(atPath: file.path, contents: data,
                                                 attributes: [.posixPermissions: 0o600]) else { return }
        } catch { fputs("Could not save crash report: \(error)\n", stderr) }
    }
}

@main
private enum Main {
    static func main() {
        guard CommandLine.arguments.count >= 4, let code = Int(CommandLine.arguments[2]) else {
            fputs("Usage: AscendaraCrashReporter TOOL ERROR_CODE MESSAGE\n", stderr)
            exit(2)
        }
        let app = NSApplication.shared
        let reporter = Reporter(tool: CommandLine.arguments[1], code: code,
                                detail: CommandLine.arguments.dropFirst(3).joined(separator: " "))
        app.delegate = reporter
        app.run()
    }
}
