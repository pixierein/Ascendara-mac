import Foundation
import Combine

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

@MainActor
final class CompatibilityService: ObservableObject {
    @Published private(set) var Status = CompatibilityStatus()
    var CustomWinePath: String?
    var CustomHighballPath: String?
    let HighballHome = RuntimePaths.Support.appendingPathComponent("Highball", isDirectory: true)

    var Environment: [String: String] {
        var Environment = ProcessInfo.processInfo.environment
        Environment["HIGHBALL_HOME"] = HighballHome.path
        return Environment
    }

    func FindWine() -> URL? {
        FindExecutable([CustomWinePath,
            "/opt/homebrew/bin/wine64", "/opt/homebrew/bin/wine", "/usr/local/bin/wine64", "/usr/local/bin/wine",
            "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64",
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine64",
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"])
    }

    func FindHighball() -> URL? {
        FindExecutable([CustomHighballPath,
            Bundle.main.resourceURL?.appendingPathComponent("Highball/highball").path,
            ProcessInfo.processInfo.environment["ASCENDARA_HIGHBALL_PATH"],
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("BuildTools/Highball/highball").path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("MacPort/BuildTools/Highball/highball").path,
            "/opt/homebrew/bin/highball", "/usr/local/bin/highball"])
    }

    var DefaultManifestURL: URL? {
        FindHighballResource("engine-manifest.json")
    }

    var D3DMetalLicenseText: String? {
        guard let URL = FindHighballResource("d3dmetal-license.txt") else { return nil }
        return try? String(contentsOf: URL, encoding: .utf8)
    }

    private func FindHighballResource(_ Name: String) -> URL? {
        let Candidates = [Bundle.main.resourceURL?.appendingPathComponent("Highball/" + Name),
                          FindHighball()?.deletingLastPathComponent().appendingPathComponent(Name)]
        return Candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func FindExecutable(_ Paths: [String?]) -> URL? {
        Paths.compactMap { $0 }.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    @discardableResult
    func Detect() async -> CompatibilityStatus {
        var Current = CompatibilityStatus()
        Current.WinePath = FindWine()?.path
        Current.HighballPath = FindHighball()?.path
        let Arm = try? await NativeProcess.Run(URL(fileURLWithPath: "/usr/sbin/sysctl"), ["-n", "hw.optional.arm64"])
        Current.AppleSilicon = Arm?.Output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        let Rosetta = try? await NativeProcess.Run(URL(fileURLWithPath: "/usr/bin/arch"), ["-x86_64", "/usr/bin/true"])
        Current.RosettaInstalled = Rosetta?.Status == 0
        if let Highball = FindHighball() {
            do {
                let Engines = try await NativeProcess.Checked(Highball, ["engine", "list"], Environment: Environment)
                Current.Engines = Engines.components(separatedBy: .newlines).filter { $0.contains("\trenderers:") && !$0.contains("INCOMPLETE") }.compactMap { $0.components(separatedBy: "\t").first }
                let Bottles = try await NativeProcess.Checked(Highball, ["bottle", "list"], Environment: Environment)
                Current.Bottles = Bottles.components(separatedBy: .newlines).filter { $0.contains("\tengine=") }.compactMap { $0.components(separatedBy: "\t").first }
            } catch { Current.ErrorMessage = error.localizedDescription }
        }
        Status = Current
        return Current
    }

    func CreateBottle(Name: String, Engine: String) async throws {
        guard let Highball = FindHighball() else { throw RuntimeError.Message("Highball was not found. Choose its executable in Settings.") }
        guard !Name.isEmpty, !Engine.isEmpty else { throw RuntimeError.Message("Choose a bottle name and an installed engine.") }
        _ = try await NativeProcess.Checked(Highball, ["bottle", "create", Name, "--engine", Engine], Environment: Environment)
        await Detect()
    }

    func InstallEngine(ManifestURL: URL) async throws {
        guard let Highball = FindHighball() else { throw RuntimeError.Message("Highball was not found.") }
        _ = try await NativeProcess.Checked(Highball, ["engine", "install", ManifestURL.path], Environment: Environment)
        await Detect()
    }

    func InstallDefaultEngine() async throws {
        guard let Manifest = DefaultManifestURL else { throw RuntimeError.Message("The bundled Highball engine manifest is missing. Choose an engine manifest file instead.") }
        try await InstallEngine(ManifestURL: Manifest)
    }

    func AcceptD3DMetalLicense(Engine: String) async throws {
        guard let Highball = FindHighball(), Status.Engines.contains(Engine) else { throw RuntimeError.Message("Choose an installed Highball engine first.") }
        _ = try await NativeProcess.Checked(Highball, ["engine", "accept", Engine, "apple-gptk-license-2023-08-17"], Environment: Environment)
        await Detect()
    }

    func LaunchCommand(for Game: LibraryGame) async throws -> (Executable: URL, Arguments: [String], Environment: [String: String]) {
        var LaunchEnvironment = ProcessInfo.processInfo.environment
        switch Game.LaunchMode {
        case .Native:
            return (Game.ExecutableURL, Game.LaunchArguments, LaunchEnvironment)
        case .Wine:
            guard let Wine = FindWine() else { throw RuntimeError.Message("Wine is not installed. Choose a Wine executable in Settings, or use a configured Highball bottle.") }
            if let Prefix = Game.WinePrefixPath, !Prefix.isEmpty { LaunchEnvironment["WINEPREFIX"] = Prefix }
            let Extension = Game.ExecutableURL.pathExtension.lowercased()
            let Prefix = Extension == "msi" ? ["msiexec", "/i"] : (["bat", "cmd"].contains(Extension) ? ["cmd", "/c"] : [])
            return (Wine, Prefix + [Game.ExecutablePath] + Game.LaunchArguments, LaunchEnvironment)
        case .Highball:
            let Current = await Detect()
            guard let Path = Current.HighballPath, Current.AppleSilicon else { throw RuntimeError.Message("Highball needs Apple Silicon and its installed command line runtime.") }
            guard Current.RosettaInstalled else { throw RuntimeError.Message("Install Rosetta 2 before launching Windows games through Highball.") }
            guard Current.Bottles.contains(Game.HighballBottle) else { throw RuntimeError.Message("The Highball bottle ‘\(Game.HighballBottle)’ is not installed. Create it in Compatibility settings first.") }
            var Arguments = ["run"]
            if ["dxmt", "d3dmetal", "dxvk", "vkd3d", "wined3d"].contains(Game.Renderer) { Arguments += ["--renderer", Game.Renderer] }
            Arguments += [Game.HighballBottle, Game.ExecutablePath]
            if !Game.LaunchArguments.isEmpty { Arguments += ["--"] + Game.LaunchArguments }
            return (URL(fileURLWithPath: Path), Arguments, Environment)
        }
    }
}
