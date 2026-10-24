import Foundation
import Darwin

// A standalone Swift counterpart to AscendaraGameHandler. The UI can quit while
// this process continues to own the game session and its durable status journal.
private struct Job: Codable {
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

private struct Status: Codable {
    var Phase: String
    var HandlerPid = getpid()
    var ProcessId: Int32?
    var StartedAt: Date?
    var EndedAt: Date?
    var ObservedSeconds = 0
    var Crashed = false
    var ExitCode: Int32?
    var Error: String?
    var DetailLogPath: String?
    var RelatedProcessCount = 0
    var UpdatedAt = Date()
}

private struct ProcessIdentity: Hashable {
    let Pid: pid_t
    let StartedSeconds: UInt64
    let StartedMicroseconds: UInt64
}

private struct ProcessEntry {
    let Identity: ProcessIdentity
    let Parent: pid_t
    let Path: String
}

private enum ProcessScanner {
    static func All() -> [ProcessEntry] {
        let Count = proc_listallpids(nil, 0)
        guard Count > 0 else { return [] }
        var Pids = [pid_t](repeating: 0, count: Int(Count) + 128)
        let Found = Pids.withUnsafeMutableBytes { Buffer in
            proc_listallpids(Buffer.baseAddress, Int32(Buffer.count))
        }
        guard Found > 0 else { return [] }
        var Result: [ProcessEntry] = []
        Result.reserveCapacity(Int(Found))
        for Pid in Pids.prefix(Int(Found)) where Pid > 0 {
            var Info = proc_bsdinfo()
            let Size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(Pid, PROC_PIDTBSDINFO, 0, &Info, Size) == Size else { continue }
            var PathBuffer = [CChar](repeating: 0, count: 4096)
            let Length = PathBuffer.withUnsafeMutableBytes { Buffer in
                proc_pidpath(Pid, Buffer.baseAddress, UInt32(Buffer.count))
            }
            Result.append(ProcessEntry(
                Identity: ProcessIdentity(Pid: Pid,
                    StartedSeconds: UInt64(Info.pbi_start_tvsec),
                    StartedMicroseconds: UInt64(Info.pbi_start_tvusec)),
                Parent: pid_t(Info.pbi_ppid),
                Path: Length > 0 ? String(cString: PathBuffer) : ""))
        }
        return Result
    }

    static func InDirectory(_ Entries: [ProcessEntry], Root: String) -> Set<ProcessIdentity> {
        Set(Entries.filter { $0.Path == Root || $0.Path.hasPrefix(Root + "/") }.map(\.Identity))
    }

    static func Related(_ Entries: [ProcessEntry], DirectPid: pid_t, Root: String,
                        Baseline: Set<ProcessIdentity>, Known: Set<ProcessIdentity>,
                        WatchDirectory: Bool) -> Set<ProcessIdentity> {
        let ByPid = Dictionary(uniqueKeysWithValues: Entries.map { ($0.Identity.Pid, $0) })
        var Tracked = Known.filter { ByPid[$0.Pid]?.Identity == $0 }
        var Parents = Set(Tracked.map(\.Pid))
        Parents.insert(DirectPid)
        var Changed = true
        while Changed {
            Changed = false
            for Entry in Entries where Entry.Identity.Pid != getpid() && Entry.Identity.Pid != DirectPid {
                let InDirectory = WatchDirectory && !Baseline.contains(Entry.Identity)
                    && (Entry.Path == Root || Entry.Path.hasPrefix(Root + "/"))
                if (Parents.contains(Entry.Parent) || InDirectory) && Tracked.insert(Entry.Identity).inserted {
                    Parents.insert(Entry.Identity.Pid)
                    Changed = true
                }
            }
        }
        return Tracked
    }

    static func IsAlive(_ Identity: ProcessIdentity) -> Bool {
        var Info = proc_bsdinfo()
        let Size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(Identity.Pid, PROC_PIDTBSDINFO, 0, &Info, Size) == Size else { return false }
        return UInt64(Info.pbi_start_tvsec) == Identity.StartedSeconds
            && UInt64(Info.pbi_start_tvusec) == Identity.StartedMicroseconds
    }
}

private func Write<T: Encodable>(_ Value: T, to URL: URL) throws {
    let Data = try JSONEncoder().encode(Value)
    try Data.write(to: URL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: URL.path)
}

private func DetailLogPath(_ Job: Job, LogURL: URL) -> String? {
    guard let Home = Job.Environment["HIGHBALL_HOME"],
          let Output = try? String(contentsOf: LogURL, encoding: .utf8) else { return nil }
    // Highball prints its Wine log path in the launch output. Keep the complete
    // log on disk and validate the path before exposing it to the UI.
    let LogRoot = URL(fileURLWithPath: Home, isDirectory: true)
        .appendingPathComponent("logs", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
    for Line in Output.components(separatedBy: .newlines).reversed() {
        guard let Range = Line.range(of: "log: ") else { continue }
        let Path = Line[Range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard Path.hasPrefix("/") else { continue }
        let URL = URL(fileURLWithPath: Path).resolvingSymlinksInPath().standardizedFileURL
        if URL.path.hasPrefix(LogRoot.path + "/") && FileManager.default.fileExists(atPath: URL.path) {
            return URL.path
        }
    }
    return nil
}

private func LaunchFailure(_ Status: Status, DetailLogPath: String?) -> String {
    if Status.Crashed { return "Game process crashed with signal \(Status.ExitCode ?? -1). See the complete launch log." }
    if let Path = DetailLogPath,
       let Detail = try? String(contentsOfFile: Path, encoding: .utf8),
       Detail.localizedCaseInsensitiveContains("c0000135") {
        return "Windows could not load a required DLL or runtime (c0000135). Check the game files and prerequisites. The complete logs are available below."
    }
    return "Game exited with status \(Status.ExitCode ?? -1). See the complete launch log for the cause."
}

private func Stop(_ Game: Process, Related: Set<ProcessIdentity>, Job: Job) {
    if let Highball = Job.HighballExecutable, let Bottle = Job.HighballBottle {
        let Killer = Process()
        Killer.executableURL = URL(fileURLWithPath: Highball)
        Killer.arguments = ["bottle", "kill", Bottle]
        Killer.environment = Job.Environment
        Killer.standardOutput = FileHandle.nullDevice
        Killer.standardError = FileHandle.nullDevice
        try? Killer.run()
        let Deadline = Date().addingTimeInterval(30)
        while Killer.isRunning && Date() < Deadline { Thread.sleep(forTimeInterval: 0.1) }
        if Killer.isRunning { _ = kill(Killer.processIdentifier, SIGKILL) }
    }
    for Identity in Related where ProcessScanner.IsAlive(Identity) { _ = kill(Identity.Pid, SIGTERM) }
    if Game.isRunning { Game.terminate() }
    Thread.sleep(forTimeInterval: 2)
    for Identity in Related where ProcessScanner.IsAlive(Identity) { _ = kill(Identity.Pid, SIGKILL) }
    if Game.isRunning { _ = kill(Game.processIdentifier, SIGKILL) }
    if Game.isRunning { Game.waitUntilExit() }
}

private func Run(_ JobURL: URL) throws {
    let Directory = JobURL.deletingLastPathComponent()
    let Job = try JSONDecoder().decode(Job.self, from: Data(contentsOf: JobURL))
    let StatusURL = Directory.appendingPathComponent("status.json")
    let StopURL = Directory.appendingPathComponent("stop")
    let LogURL = Directory.appendingPathComponent("game.log")
    let Root = URL(fileURLWithPath: Job.TrackingRoot).resolvingSymlinksInPath().standardizedFileURL.path
    let Baseline = Job.WatchDirectory ? ProcessScanner.InDirectory(ProcessScanner.All(), Root: Root) : []
    var Status = Status(Phase: "launching")
    try Write(Status, to: StatusURL)
    FileManager.default.createFile(atPath: LogURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
    let Log = try FileHandle(forWritingTo: LogURL)
    defer { try? Log.close() }

    let Game = Process()
    Game.executableURL = URL(fileURLWithPath: Job.Executable)
    Game.arguments = Job.Arguments
    Game.environment = Job.Environment
    Game.currentDirectoryURL = URL(fileURLWithPath: Job.WorkingDirectory, isDirectory: true)
    Game.standardOutput = Log
    Game.standardError = Log
    do { try Game.run() }
    catch {
        Status.Phase = "failed"
        Status.Error = error.localizedDescription
        Status.EndedAt = Date()
        Status.UpdatedAt = Date()
        try Write(Status, to: StatusURL)
        throw error
    }

    let Started = Date()
    Status.ProcessId = Game.processIdentifier
    Status.StartedAt = Started
    Status.UpdatedAt = Date()
    try Write(Status, to: StatusURL)
    var Related = Set<ProcessIdentity>()
    var DirectEndedAt: Date?
    var TrackedRelated = false
    var Stopped = false
    var StoppedAt: Date?
    while true {
        let Entries = ProcessScanner.All()
        Related = ProcessScanner.Related(Entries, DirectPid: Game.processIdentifier,
            Root: Root, Baseline: Baseline, Known: Related, WatchDirectory: Job.WatchDirectory)
        Status.RelatedProcessCount = Related.count
        if !Related.isEmpty { TrackedRelated = true }

        if FileManager.default.fileExists(atPath: StopURL.path) {
            Stopped = true
            StoppedAt = Date()
            Stop(Game, Related: Related, Job: Job)
            Related.removeAll()
        }
        let Now = Date()
        Status.ObservedSeconds = max(0, Int(Now.timeIntervalSince(Started)))
        if Game.isRunning || !Related.isEmpty {
            DirectEndedAt = nil
            if Status.Phase != "running" || Status.ObservedSeconds % 3 == 0 {
                Status.Phase = "running"
                Status.UpdatedAt = Now
                try Write(Status, to: StatusURL)
            }
        } else {
            if DirectEndedAt == nil { DirectEndedAt = Now }
            if Now.timeIntervalSince(DirectEndedAt!) >= 1 || Stopped { break }
        }
        Thread.sleep(forTimeInterval: 1)
    }

    let Ended = StoppedAt ?? Date()
    Status.ObservedSeconds = max(0, Int(Ended.timeIntervalSince(Started)))
    Status.EndedAt = Ended
    Status.ExitCode = Game.terminationStatus
    Status.Crashed = !Stopped && Game.terminationReason == .uncaughtSignal
        && ![SIGHUP, SIGINT, SIGTERM].contains(Game.terminationStatus)
    Status.RelatedProcessCount = 0
    Status.Phase = Stopped ? "stopped" : "completed"
    if !Stopped {
        Status.DetailLogPath = DetailLogPath(Job, LogURL: LogURL)
        if Game.terminationStatus != 0 {
            Status.Error = LaunchFailure(Status, DetailLogPath: Status.DetailLogPath)
        } else if Status.ObservedSeconds < 2 && !TrackedRelated {
            Status.Error = "Game closed immediately. See the complete launch log for the cause."
        }
    }
    Status.UpdatedAt = Ended
    try Write(Status, to: StatusURL)
}

guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--job" else {
    fputs("Usage: AscendaraGameHandler --job /path/to/job.json\n", stderr)
    exit(2)
}
do { try Run(URL(fileURLWithPath: CommandLine.arguments[2])) }
catch { fputs("AscendaraGameHandler: \(error.localizedDescription)\n", stderr); exit(1) }
