import Foundation
import Combine
import Darwin

private struct GameHandlerJob: Codable {
    let Id: UUID
    let GameId: UUID
    let Name: String
    let Executable: String
    let Arguments: [String]
    let Environment: [String: String]
    let WorkingDirectory: String
    let TrackingRoot: String
    let WatchDirectory: Bool
    let HighballExecutable: String?
    let HighballBottle: String?
}

private struct GameHandlerStatus: Codable {
    var Phase: String
    var HandlerPid: Int32
    var ProcessId: Int32?
    var StartedAt: Date?
    var EndedAt: Date?
    var ObservedSeconds: Int
    var Crashed: Bool
    var ExitCode: Int32?
    var Error: String?
    var DetailLogPath: String?
    var RelatedProcessCount: Int
    var UpdatedAt: Date
}

struct GameFailureReport: Identifiable {
    let id: UUID
    let GameName: String
    let Summary: String
    let LaunchLog: URL
    let DetailLog: URL?

    var FullLog: String {
        func Contents(_ URL: URL) -> String {
            guard let Data = try? Data(contentsOf: URL) else { return "Log file is unavailable.\n" }
            return String(decoding: Data, as: UTF8.self)
        }
        var Result = "Launch log: \(LaunchLog.path)\n\n\(Contents(LaunchLog))"
        if let DetailLog {
            Result += "\n\nHighball / Wine log: \(DetailLog.path)\n\n\(Contents(DetailLog))"
        }
        return Result
    }
}

enum GameLaunchFailure: Error { case Reported }

@MainActor
final class GameLauncher: ObservableObject {
    @Published private(set) var RunningIds: Set<UUID> = []
    @Published private(set) var ErrorMessage: String?
    @Published private(set) var Failure: GameFailureReport?
    /// Used by Retro and other callers that only need an elapsed-time delta.
    var OnSessionEnded: ((UUID, Date, Double) -> Void)?
    /// Cumulative, replayable session progress from the detached handler.
    var OnSessionProgress: ((UUID, UUID, Date, Int, GameSession?) -> Void)?
    var OnSessionSummary: ((UUID, GameSession) -> Void)?
    let Compatibility: CompatibilityService
    let StorageDirectory: URL
    private var Sessions: [UUID: GameHandlerJob] = [:]
    private var AppliedSeconds: [UUID: Int] = [:]
    private var ProcessedFinal: Set<UUID> = []
    private var PollTask: Task<Void, Never>?
    private var StartingIds: Set<UUID> = []
    private var StoppingIds: Set<UUID> = []
    private var SessionsDirectory: URL { StorageDirectory.appendingPathComponent("GameSessions", isDirectory: true) }

    init(Compatibility: CompatibilityService, StorageDirectory: URL = RuntimePaths.Support) {
        self.Compatibility = Compatibility
        self.StorageDirectory = StorageDirectory
    }

    private func HandlerExecutable() throws -> URL {
        guard let Main = Bundle.main.executableURL else { throw RuntimeError.Message("Ascendara executable was not found.") }
        let Handler = Main.deletingLastPathComponent().appendingPathComponent("AscendaraGameHandler")
        guard FileManager.default.isExecutableFile(atPath: Handler.path) else {
            throw RuntimeError.Message("The Swift game handler is missing from this build.")
        }
        return Handler
    }

    private func Directory(for SessionId: UUID) -> URL { SessionsDirectory.appendingPathComponent(SessionId.uuidString, isDirectory: true) }
    private func StatusURL(for SessionId: UUID) -> URL { Directory(for: SessionId).appendingPathComponent("status.json") }
    private func HandledURL(for SessionId: UUID) -> URL { Directory(for: SessionId).appendingPathComponent("handled") }

    private func ReadStatus(_ SessionId: UUID) -> GameHandlerStatus? {
        guard let Data = try? Data(contentsOf: StatusURL(for: SessionId)) else { return nil }
        return try? JSONDecoder().decode(GameHandlerStatus.self, from: Data)
    }

    private func ReportFailure(_ SessionId: UUID, Job: GameHandlerJob, Status: GameHandlerStatus) {
        let Message = Status.Error ?? "Game exited with status \(Status.ExitCode ?? -1)."
        let LaunchLog = Directory(for: SessionId).appendingPathComponent("game.log")
        let DetailLog = Status.DetailLogPath.map { URL(fileURLWithPath: $0) }
            ?? FindLegacyHighballLog(in: LaunchLog)
        Failure = GameFailureReport(id: SessionId, GameName: Job.Name, Summary: Message,
            LaunchLog: LaunchLog, DetailLog: DetailLog)
    }

    private func FindLegacyHighballLog(in LaunchLog: URL) -> URL? {
        guard let Output = try? String(contentsOf: LaunchLog, encoding: .utf8) else { return nil }
        let Root = Compatibility.HighballHome.appendingPathComponent("logs", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL.path
        for Line in Output.components(separatedBy: .newlines).reversed() {
            guard let Range = Line.range(of: "log: ") else { continue }
            let Path = Line[Range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard Path.hasPrefix("/") else { continue }
            let Candidate = URL(fileURLWithPath: Path).resolvingSymlinksInPath().standardizedFileURL
            if Candidate.path.hasPrefix(Root + "/") && FileManager.default.fileExists(atPath: Candidate.path) {
                return Candidate
            }
        }
        return nil
    }

    private func HandlerAlive(_ Pid: pid_t) -> Bool {
        Pid > 0 && (kill(Pid, 0) == 0 || errno == EPERM)
    }

    func Launch(_ Game: LibraryGame) async throws {
        guard !RunningIds.contains(Game.Id), StartingIds.insert(Game.Id).inserted else {
            throw RuntimeError.Message("This game is already running.")
        }
        defer { StartingIds.remove(Game.Id) }
        guard FileManager.default.fileExists(atPath: Game.ExecutablePath) else {
            throw RuntimeError.Message("The game executable is missing. Choose a new executable in Game Settings.")
        }
        ErrorMessage = nil
        Failure = nil
        let Handler = try HandlerExecutable()
        let Command = try await Compatibility.LaunchCommand(for: Game)
        var Executable = Command.Executable
        var Arguments = Command.Arguments
        let IsMacApp = Game.LaunchMode == .Native && Game.ExecutableURL.pathExtension.lowercased() == "app"
        if IsMacApp {
            guard Bundle(url: Game.ExecutableURL)?.executableURL != nil else {
                throw RuntimeError.Message("The macOS app does not contain a launchable executable.")
            }
            // LaunchServices supplies the app's normal environment and handles
            // activation; invoking Contents/MacOS directly breaks some games.
            Executable = URL(fileURLWithPath: "/usr/bin/open")
            Arguments = ["-W", Game.ExecutablePath]
            if !Command.Arguments.isEmpty { Arguments += ["--args"] + Command.Arguments }
        }
        let SessionId = UUID()
        let Root = IsMacApp ? Game.ExecutableURL : Game.DirectoryURL
        let WatchDirectory = Game.IsManaged || Game.ExecutableURL.pathExtension.lowercased() == "app"
            || (Root.pathComponents.count >= 4 && !Set(["Applications", "Downloads", "Desktop", "Documents", "Utilities"]).contains(Root.lastPathComponent))
        let Job = GameHandlerJob(Id: SessionId, GameId: Game.Id, Name: Game.Name,
                                 Executable: Executable.path, Arguments: Arguments,
                                 Environment: Command.Environment,
                                 WorkingDirectory: Game.ExecutableURL.deletingLastPathComponent().path,
                                 TrackingRoot: Root.path, WatchDirectory: WatchDirectory,
                                 HighballExecutable: Game.LaunchMode == .Highball ? Command.Executable.path : nil,
                                 HighballBottle: Game.LaunchMode == .Highball ? Game.HighballBottle : nil)
        let Directory = Directory(for: SessionId)
        try RuntimePaths.CreateDirectory(Directory)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Directory.path)
        let JobURL = Directory.appendingPathComponent("job.json")
        try JSONEncoder().encode(Job).write(to: JobURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: JobURL.path)
        let Process = Process()
        Process.executableURL = Handler
        Process.arguments = ["--job", JobURL.path]
        Process.currentDirectoryURL = Directory
        Process.standardOutput = FileHandle.nullDevice
        Process.standardError = FileHandle.nullDevice
        do { try Process.run() }
        catch { try? FileManager.default.removeItem(at: Directory); throw error }
        Sessions[SessionId] = Job
        RunningIds.insert(Game.Id)
        StartPolling()
        // Highball can spend several seconds preparing Wine before it discovers
        // that the game cannot load. Do not record a play or hide the UI yet.
        let Grace = Game.LaunchMode == .Highball ? 18.0 : 2.0
        let Deadline = Date().addingTimeInterval(Grace)
        repeat {
            if let Status = ReadStatus(SessionId) {
                if Status.Phase == "failed" || Status.Phase == "completed" && Status.ExitCode != 0 {
                    ReportFailure(SessionId, Job: Job, Status: Status)
                    Sessions.removeValue(forKey: SessionId)
                    RunningIds.remove(Game.Id)
                    try? Data().write(to: HandledURL(for: SessionId), options: .atomic)
                    throw GameLaunchFailure.Reported
                }
                if Status.Phase == "stopped" {
                    Sessions.removeValue(forKey: SessionId)
                    RunningIds.remove(Game.Id)
                    try? Data().write(to: HandledURL(for: SessionId), options: .atomic)
                    throw RuntimeError.Message("\(Game.Name) was stopped before it opened.")
                }
            } else if !Process.isRunning {
                Sessions.removeValue(forKey: SessionId)
                RunningIds.remove(Game.Id)
                throw RuntimeError.Message("The game handler exited before reporting launch status.")
            }
            if Date() >= Deadline { break }
            try await Task.sleep(for: .milliseconds(250))
        } while true
        if let Status = ReadStatus(SessionId), Status.Phase == "completed", Status.ObservedSeconds < 2 {
            ReportFailure(SessionId, Job: Job, Status: Status)
            Sessions.removeValue(forKey: SessionId)
            RunningIds.remove(Game.Id)
            try? Data().write(to: HandledURL(for: SessionId), options: .atomic)
            throw GameLaunchFailure.Reported
        }
    }

    private func StartPolling() {
        guard PollTask == nil else { return }
        PollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                self.PollSessions()
                if self.Sessions.isEmpty { self.PollTask = nil; return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func PollSessions() {
        for (SessionId, Job) in Array(Sessions) {
            guard var Status = ReadStatus(SessionId) else {
                if let Modified = try? FileManager.default.attributesOfItem(atPath: Directory(for: SessionId).appendingPathComponent("job.json").path)[.modificationDate] as? Date,
                   Date().timeIntervalSince(Modified) > 10 {
                    ErrorMessage = "\(Job.Name): the game handler did not write a status journal."
                    Sessions.removeValue(forKey: SessionId)
                    RunningIds.remove(Job.GameId)
                    try? Data().write(to: HandledURL(for: SessionId), options: .atomic)
                }
                continue
            }
            guard let StartedAt = Status.StartedAt else {
                if Status.Phase == "failed" {
                    ReportFailure(SessionId, Job: Job, Status: Status)
                    Sessions.removeValue(forKey: SessionId)
                    RunningIds.remove(Job.GameId)
                    try? Data().write(to: HandledURL(for: SessionId), options: .atomic)
                }
                continue
            }
            if ["launching", "running"].contains(Status.Phase) && !HandlerAlive(Status.HandlerPid)
                && Date().timeIntervalSince(Status.UpdatedAt) > 5 {
                Status.Phase = "failed"
                Status.EndedAt = Status.UpdatedAt
                Status.Error = "The game handler stopped unexpectedly. Check the game log."
                Status.UpdatedAt = Date()
                if let Data = try? JSONEncoder().encode(Status) { try? Data.write(to: StatusURL(for: SessionId), options: .atomic) }
            }
            let Terminal = ["completed", "stopped", "failed"].contains(Status.Phase)
            let Summary: GameSession? = Terminal && Status.Phase != "failed"
                ? GameSession(Seconds: Status.ObservedSeconds, Crashed: Status.Crashed, EndedAt: Status.EndedAt ?? Date()) : nil
            let Previous = AppliedSeconds[SessionId] ?? -1
            if Previous != Status.ObservedSeconds || (Terminal && !ProcessedFinal.contains(SessionId)) {
                if let OnSessionProgress {
                    OnSessionProgress(Job.GameId, SessionId, StartedAt, Status.ObservedSeconds, Summary)
                } else if Status.ObservedSeconds > max(0, Previous) {
                    OnSessionEnded?(Job.GameId, StartedAt, Double(Status.ObservedSeconds - max(0, Previous)))
                }
                AppliedSeconds[SessionId] = Status.ObservedSeconds
            }
            if Terminal {
                if !ProcessedFinal.contains(SessionId) {
                    if let Summary { OnSessionSummary?(Job.GameId, Summary) }
                    if Status.Error != nil, Status.Phase != "stopped" {
                        ReportFailure(SessionId, Job: Job, Status: Status)
                    }
                    ProcessedFinal.insert(SessionId)
                }
                Sessions.removeValue(forKey: SessionId)
                RunningIds.remove(Job.GameId)
                StoppingIds.remove(Job.GameId)
                try? Data().write(to: HandledURL(for: SessionId), options: .atomic)
            } else {
                RunningIds.insert(Job.GameId)
            }
        }
    }

    /// Replays durable journals and reconnects to handlers that survived a UI
    /// restart. Call after installing OnSessionProgress, with this library's IDs.
    func RestoreSessions(KnownGameIds: Set<UUID>) {
        guard let Directories = try? FileManager.default.contentsOfDirectory(at: SessionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
        for Directory in Directories {
            let URL = Directory.appendingPathComponent("job.json")
            guard !FileManager.default.fileExists(atPath: Directory.appendingPathComponent("handled").path) else { continue }
            guard let Data = try? Data(contentsOf: URL),
                  let Job = try? JSONDecoder().decode(GameHandlerJob.self, from: Data),
                  KnownGameIds.contains(Job.GameId) else { continue }
            Sessions[Job.Id] = Job
        }
        PollSessions()
        if !Sessions.isEmpty { StartPolling() }
    }

    func PrepareForExit() { PollSessions() }

    func Stop(_ Id: UUID) async throws {
        guard let (SessionId, _) = Sessions.first(where: { $0.value.GameId == Id }) else {
            throw RuntimeError.Message("This game has no running session.")
        }
        guard StoppingIds.insert(Id).inserted else { return }
        let StopURL = Directory(for: SessionId).appendingPathComponent("stop")
        do { try Data().write(to: StopURL, options: .atomic) }
        catch { StoppingIds.remove(Id); throw error }
    }
}
