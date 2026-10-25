import Foundation

struct ProcessResult {
    var Output: String
    var ErrorOutput: String
    var Status: Int32
}

enum NativeProcess {
    static func Run(_ Executable: URL, _ Arguments: [String], Environment: [String: String]? = nil) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { Continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let Process = Process()
                Process.executableURL = Executable
                Process.arguments = Arguments
                Process.environment = Environment
                let Output = Pipe()
                let ErrorOutput = Pipe()
                Process.standardOutput = Output
                Process.standardError = ErrorOutput
                let Group = DispatchGroup()
                let Capture = ProcessCapture()
                do {
                    try Process.run()
                    Group.enter()
                    DispatchQueue.global().async {
                        Capture.Output = Output.fileHandleForReading.readDataToEndOfFile()
                        Group.leave()
                    }
                    Group.enter()
                    DispatchQueue.global().async {
                        Capture.ErrorOutput = ErrorOutput.fileHandleForReading.readDataToEndOfFile()
                        Group.leave()
                    }
                    Process.waitUntilExit()
                    Group.wait()
                    Continuation.resume(returning: ProcessResult(Output: String(decoding: Capture.Output, as: UTF8.self),
                                                                 ErrorOutput: String(decoding: Capture.ErrorOutput, as: UTF8.self),
                                                                 Status: Process.terminationStatus))
                } catch { Continuation.resume(throwing: error) }
            }
        }
    }

    static func Checked(_ Executable: URL, _ Arguments: [String], Environment: [String: String]? = nil) async throws -> String {
        let Result = try await Run(Executable, Arguments, Environment: Environment)
        guard Result.Status == 0 else {
            let Message = Result.ErrorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RuntimeError.Message(Message.isEmpty ? "\(Executable.lastPathComponent) exited with status \(Result.Status). \(Result.Output)" : Message)
        }
        return Result.Output
    }
}

private final class ProcessCapture: @unchecked Sendable {
    var Output = Data()
    var ErrorOutput = Data()
}
