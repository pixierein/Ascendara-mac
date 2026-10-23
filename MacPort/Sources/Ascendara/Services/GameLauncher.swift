import Foundation
import AppKit
import Combine

@MainActor
final class GameLauncher: ObservableObject {
    @Published private(set) var RunningIds: Set<UUID> = []
    @Published private(set) var ErrorMessage: String?
    var OnSessionEnded: ((UUID, Date, Double) -> Void)?
    let Compatibility: CompatibilityService
    let StorageDirectory: URL
    private var Processes: [UUID: Process] = [:]
    private var Applications: [UUID: NSRunningApplication] = [:]
    private var Starts: [UUID: Date] = [:]
    private var Checkpoints: [UUID: Date] = [:]
    private var StoppingIds: Set<UUID> = []
    private var Games: [UUID: LibraryGame] = [:]
    private var Observer: NSObjectProtocol?
    private var Logs: [UUID: FileHandle] = [:]

    init(Compatibility: CompatibilityService, StorageDirectory: URL = RuntimePaths.Support) {
        self.Compatibility = Compatibility
        self.StorageDirectory = StorageDirectory
        Observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] Notice in
            guard let Application = Notice.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                guard let self, let Id = self.Applications.first(where: { $0.value.processIdentifier == Application.processIdentifier })?.key else { return }
                self.Finished(Id)
            }
        }
    }

    deinit {
        if let Observer { NSWorkspace.shared.notificationCenter.removeObserver(Observer) }
    }

    func Launch(_ Game: LibraryGame) async throws {
        guard !RunningIds.contains(Game.Id) else { throw RuntimeError.Message("This game is already running.") }
        guard FileManager.default.fileExists(atPath: Game.ExecutablePath) else { throw RuntimeError.Message("The game executable is missing. Choose a new executable in Game Settings.") }
        ErrorMessage = nil
        if Game.LaunchMode == .Native && Game.ExecutableURL.pathExtension.lowercased() == "app" {
            guard !Applications.values.contains(where: { $0.bundleURL == Game.ExecutableURL }) else {
                throw RuntimeError.Message("This application already has a running game session. Stop it before launching another game.")
            }
            let Configuration = NSWorkspace.OpenConfiguration()
            Configuration.arguments = Game.LaunchArguments
            Configuration.activates = true
            Configuration.createsNewApplicationInstance = true
            let Application = try await NSWorkspace.shared.openApplication(at: Game.ExecutableURL, configuration: Configuration)
            Applications[Game.Id] = Application
            Started(Game)
            if Application.isTerminated { Finished(Game.Id) }
            return
        }
        let Command = try await Compatibility.LaunchCommand(for: Game)
        let Process = Process()
        Process.executableURL = Command.Executable
        Process.arguments = Command.Arguments
        Process.environment = Command.Environment
        Process.currentDirectoryURL = Game.ExecutableURL.deletingLastPathComponent()
        let LogsDirectory = StorageDirectory.appendingPathComponent("Logs", isDirectory: true)
        try RuntimePaths.CreateDirectory(LogsDirectory)
        let LogURL = LogsDirectory.appendingPathComponent(Game.Id.uuidString + ".log")
        FileManager.default.createFile(atPath: LogURL.path, contents: nil)
        let Log = try FileHandle(forWritingTo: LogURL)
        Process.standardOutput = Log
        Process.standardError = Log
        Process.terminationHandler = { [weak self] Child in
            Task { @MainActor in
                guard let self else { return }
                if Child.terminationStatus != 0 && !self.StoppingIds.contains(Game.Id) {
                    self.ErrorMessage = "\(Game.Name) exited with status \(Child.terminationStatus). See \(LogURL.path) for details."
                }
                self.Finished(Game.Id)
            }
        }
        do { try Process.run() } catch { try? Log.close(); throw error }
        Logs[Game.Id] = Log
        Processes[Game.Id] = Process
        Started(Game)
    }

    private func Started(_ Game: LibraryGame) {
        Games[Game.Id] = Game
        Starts[Game.Id] = Date()
        Checkpoints[Game.Id] = Starts[Game.Id]
        RunningIds.insert(Game.Id)
    }

    private func Finished(_ Id: UUID) {
        guard let Start = Starts.removeValue(forKey: Id) else { return }
        RunningIds.remove(Id)
        StoppingIds.remove(Id)
        Applications.removeValue(forKey: Id)
        Processes.removeValue(forKey: Id)
        Games.removeValue(forKey: Id)
        try? Logs.removeValue(forKey: Id)?.close()
        let Checkpoint = Checkpoints.removeValue(forKey: Id) ?? Start
        OnSessionEnded?(Id, Start, Date().timeIntervalSince(Checkpoint))
    }

    func PrepareForExit() {
        let Now = Date()
        for (Id, Start) in Starts {
            let Checkpoint = Checkpoints[Id] ?? Start
            OnSessionEnded?(Id, Start, max(0, Now.timeIntervalSince(Checkpoint)))
            Checkpoints[Id] = Now
        }
    }

    func Stop(_ Id: UUID) async throws {
        StoppingIds.insert(Id)
        if let Application = Applications[Id] {
            guard Application.terminate() else {
                StoppingIds.remove(Id)
                throw RuntimeError.Message("The application did not accept the quit request. Quit it from its own menu.")
            }
        } else if let Game = Games[Id], Game.LaunchMode == .Highball, let Highball = Compatibility.FindHighball() {
            do { _ = try await NativeProcess.Checked(Highball, ["bottle", "kill", Game.HighballBottle], Environment: Compatibility.Environment) }
            catch { StoppingIds.remove(Id); throw error }
        } else if let Process = Processes[Id], Process.isRunning {
            Process.terminate()
        } else {
            StoppingIds.remove(Id)
        }
    }
}
