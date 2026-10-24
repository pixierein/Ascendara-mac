import AppKit
import Foundation

/// The original Electron process invokes its separate crash reporter for
/// uncaught exceptions. Keep the reporting UI out of the failing process so
/// its diagnostic window can remain open after Ascendara exits.
enum CrashReporterBridge {
    static func Install() {
        NSSetUncaughtExceptionHandler(HandleUncaughtAscendaraException)
    }

    static func Report(Tool: String, Code: Int, Message: String) {
        guard let executable = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("AscendaraCrashReporter"),
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            fputs("Ascendara error \(Code): \(Message)\n", stderr)
            return
        }
        let reporter = Process()
        reporter.executableURL = executable
        reporter.arguments = [Tool, String(Code), Message]
        var environment = ProcessInfo.processInfo.environment
        environment["ASCENDARA_APP_EXECUTABLE"] = Bundle.main.executableURL?.path
        reporter.environment = environment
        reporter.standardOutput = FileHandle.nullDevice
        reporter.standardError = FileHandle.nullDevice
        try? reporter.run()
    }
}

private func HandleUncaughtAscendaraException(_ exception: NSException) {
    let message = "\(exception.name.rawValue): \(exception.reason ?? "Unknown exception")\n"
        + exception.callStackSymbols.joined(separator: "\n")
    CrashReporterBridge.Report(Tool: "toplevel", Code: 1001, Message: message)
}
