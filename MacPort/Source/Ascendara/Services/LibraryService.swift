import Foundation
import Combine
import AppKit
import Darwin
import AscendaraCore

@MainActor
final class LibraryService: ObservableObject {
    @Published private(set) var Games: [LibraryGame] = []
    @Published private(set) var ErrorMessage: String?
    let StorageDirectory: URL
    private var MetadataURL: URL { StorageDirectory.appendingPathComponent("library.json") }

    init(StorageDirectory: URL = RuntimePaths.Support) {
        self.StorageDirectory = StorageDirectory
        do { try Load(); try RecoverInstallations() } catch { ErrorMessage = error.localizedDescription }
    }

    private struct InstallationJournal: Codable {
        let Game: LibraryGame
        let Staged: URL
        let Destination: URL
        let Previous: URL
    }

    private var TransactionsDirectory: URL { StorageDirectory.appendingPathComponent("InstallTransactions", isDirectory: true) }

    private func RecoverInstallations() throws {
        guard let Files = try? FileManager.default.contentsOfDirectory(at: TransactionsDirectory, includingPropertiesForKeys: nil) else { return }
        for File in Files where File.pathExtension == "json" {
            let Journal = try AppPaths.Read(InstallationJournal.self, From: File)
            if !FileManager.default.fileExists(atPath: Journal.Staged.path), FileManager.default.fileExists(atPath: Journal.Destination.path) {
                if Games.contains(where: { $0.Id == Journal.Game.Id }) { try Update(Journal.Game) }
            } else if !FileManager.default.fileExists(atPath: Journal.Destination.path), FileManager.default.fileExists(atPath: Journal.Previous.path) {
                try FileManager.default.moveItem(at: Journal.Previous, to: Journal.Destination)
            }
            try FileManager.default.removeItem(at: File)
        }
    }

    func Load() throws {
        guard FileManager.default.fileExists(atPath: MetadataURL.path) else { return }
        Games = try JSONDecoder().decode([LibraryGame].self, from: Data(contentsOf: MetadataURL))
        ErrorMessage = nil
    }

    private func Save(_ NewGames: [LibraryGame]) throws {
        if let ErrorMessage { throw RuntimeError.Message(ErrorMessage) }
        try RuntimePaths.CreateDirectory(StorageDirectory)
        let Encoder = JSONEncoder()
        Encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try Encoder.encode(NewGames).write(to: MetadataURL, options: .atomic)
        Games = NewGames
    }

    @discardableResult
    func ImportGame(Name: String, ExecutableURL: URL, CatalogId: String? = nil, ImageURL: String? = nil, Version: String? = nil, ManagedDirectory: URL? = nil) throws -> LibraryGame {
        let Path = ExecutableURL.resolvingSymlinksInPath().standardizedFileURL
        try ValidateExecutable(Path)
        if let ManagedDirectory {
            guard RuntimePaths.IsInside(Path, ManagedDirectory), ManagedDirectory.pathComponents.count > 3 else {
                throw RuntimeError.Message("The managed game folder does not contain its executable.")
            }
        }
        if var Existing = Games.first(where: { $0.ExecutableURL.resolvingSymlinksInPath() == Path }) {
            if let ManagedDirectory, Existing.ManagedFilesPath == nil {
                Existing.ManagedFilesPath = ManagedDirectory.standardizedFileURL.path
                Existing.IsManaged = true
                try Update(Existing)
            }
            return Existing
        }
        let CleanName = Name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !CleanName.isEmpty else { throw RuntimeError.Message("Enter a name for this game.") }
        var Game = LibraryGame(Name: CleanName, CatalogId: CatalogId, DirectoryPath: Path.deletingLastPathComponent().path,
                               ExecutablePath: Path.path, ImageURL: ImageURL)
        Game.Version = Version
        Game.LaunchMode = Self.DefaultLaunchMode(for: Path)
        if let ManagedDirectory {
            Game.ManagedFilesPath = ManagedDirectory.standardizedFileURL.path
            Game.IsManaged = true
        }
        try Save(Games + [Game])
        Task { try? await MeasureSize(Game.Id) }
        return Game
    }

    func Update(_ Game: LibraryGame) throws {
        guard let Index = Games.firstIndex(where: { $0.Id == Game.Id }) else { throw RuntimeError.Message("This game is no longer in the library.") }
        var Updated = Games
        Updated[Index] = Game
        try Save(Updated)
    }

    func MeasureSize(_ Id: UUID) async throws {
        guard let Game = Games.first(where: { $0.Id == Id }) else { return }
        let Root = Game.ManagedFilesPath.map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: LibraryDiskSpace.GamePath(Executable: Game.ExecutablePath, Directory: Game.DirectoryPath))
        let Bytes = try await Task.detached(priority: .utility) { try StorageBudget.Measure(Root) }.value
        guard var Current = Games.first(where: { $0.Id == Id }), Current.ExecutablePath == Game.ExecutablePath else { return }
        Current.InstalledSizeBytes = Bytes
        Current.SizeMeasuredAt = Date()
        try Update(Current)
    }

    func ReplaceInstallation(_ Plan: InstallationPlan, From Staged: URL, Executable: URL, Version: String?) throws -> LibraryGame {
        guard var Game = Games.first(where: { $0.Id == Plan.ReplaceGameId }), RuntimePaths.IsInside(Executable, Staged) else {
            throw RuntimeError.Message("The game or its new executable is no longer available.")
        }
        let Destination = URL(fileURLWithPath: Plan.DestinationPath).standardizedFileURL
        guard Destination.pathComponents.count > 3, !RuntimePaths.IsInside(Destination, Staged),
              !RuntimePaths.IsInside(Staged, Destination) else { throw RuntimeError.Message("Choose a separate installation folder.") }
        let PreviousRoot = Game.ManagedFilesPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
        let Existing = FileManager.default.fileExists(atPath: Destination.path)
        guard !Existing || (Game.IsManaged && PreviousRoot == Destination) else {
            throw RuntimeError.Message("The chosen installation folder already contains other files. Choose an empty folder name.")
        }
        if let PreviousRoot, PreviousRoot != Destination,
           RuntimePaths.IsInside(Destination, PreviousRoot) || RuntimePaths.IsInside(PreviousRoot, Destination) {
            throw RuntimeError.Message("The old and new installation folders cannot contain one another.")
        }
        guard !Games.contains(where: { $0.Id != Game.Id && RuntimePaths.IsInside($0.ExecutableURL, Destination) }) else {
            throw RuntimeError.Message("Another game uses the selected installation folder.")
        }
        let Relative = String(Executable.path.dropFirst(Staged.path.count + 1))
        let NewExecutable = Destination.appendingPathComponent(Relative)
        let OldAchievements = Game.ExecutableURL.deletingLastPathComponent().appendingPathComponent("achievements.ascendara.json")
        let NewAchievements = Executable.deletingLastPathComponent().appendingPathComponent("achievements.ascendara.json")
        if FileManager.default.fileExists(atPath: NewAchievements.path) { try FileManager.default.removeItem(at: NewAchievements) }
        if Plan.KeepAchievements, FileManager.default.fileExists(atPath: OldAchievements.path) {
            try FileManager.default.copyItem(at: OldAchievements, to: NewAchievements)
        }
        let Rollback = Destination.deletingLastPathComponent().appendingPathComponent(".ascendara-previous-" + UUID().uuidString)
        try RuntimePaths.CreateDirectory(Destination.deletingLastPathComponent())
        Game.ExecutablePath = NewExecutable.path
        Game.DirectoryPath = NewExecutable.deletingLastPathComponent().path
        Game.ManagedFilesPath = Destination.path
        Game.IsManaged = true
        Game.Version = Version
        Game.InstalledSizeBytes = nil
        Game.SizeMeasuredAt = nil
        if !Plan.KeepPlaytime {
            Game.PlayTimeSeconds = 0; Game.LaunchCount = 0; Game.LastPlayedAt = nil
            Game.LastSession = nil; Game.LastSessionId = nil; Game.LastSessionRecordedSeconds = 0
            Game.RecordedSessionSecondsById = [:]
        }
        let JournalURL = TransactionsDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try AppPaths.Write(InstallationJournal(Game: Game, Staged: Staged, Destination: Destination, Previous: Rollback), To: JournalURL)
        do {
            if Existing { try FileManager.default.moveItem(at: Destination, to: Rollback) }
            try FileManager.default.moveItem(at: Staged, to: Destination)
            try Update(Game)
        } catch {
            if !FileManager.default.fileExists(atPath: Staged.path), FileManager.default.fileExists(atPath: Destination.path) {
                try? FileManager.default.moveItem(at: Destination, to: Staged)
            }
            if Existing, FileManager.default.fileExists(atPath: Rollback.path) {
                try? FileManager.default.moveItem(at: Rollback, to: Destination)
            }
            if FileManager.default.fileExists(atPath: Staged.path), (!Existing || FileManager.default.fileExists(atPath: Destination.path)) {
                try? FileManager.default.removeItem(at: JournalURL)
            }
            throw error
        }
        try? FileManager.default.removeItem(at: JournalURL)
        if Existing { try? FileManager.default.trashItem(at: Rollback, resultingItemURL: nil) }
        Task { try? await MeasureSize(Game.Id) }
        return Game
    }

    func MoveInstallation(_ Id: UUID, To Destination: URL) async throws {
        guard var Game = Games.first(where: { $0.Id == Id }), Game.IsManaged, let Path = Game.ManagedFilesPath else {
            throw RuntimeError.Message("Only installations managed by Ascendara can be moved here.")
        }
        let Source = URL(fileURLWithPath: Path).standardizedFileURL
        let Destination = Destination.standardizedFileURL
        guard !FileManager.default.fileExists(atPath: Destination.path),
              !RuntimePaths.IsInside(Destination, Source), !RuntimePaths.IsInside(Source, Destination), Source != Destination,
              RuntimePaths.IsInside(Game.ExecutableURL, Source) else { throw RuntimeError.Message("Choose a new, separate installation folder.") }
        let OriginalExecutable = Game.ExecutablePath
        let Relative = String(OriginalExecutable.dropFirst(Source.path.count + 1))
        let Bytes = try await Task.detached(priority: .utility) { try StorageBudget.Measure(Source) }.value
        try StorageBudget.Check(at: Destination.deletingLastPathComponent(), Remaining: Bytes)
        let Staging = Destination.deletingLastPathComponent().appendingPathComponent(".ascendara-move-" + UUID().uuidString)
        var Moved = false
        do {
            try await Task.detached(priority: .utility) { try FileManager.default.copyItem(at: Source, to: Staging) }.value
            guard let Current = Games.first(where: { $0.Id == Id }), Current.ExecutablePath == OriginalExecutable else {
                throw RuntimeError.Message("This game changed while its files were being moved.")
            }
            try FileManager.default.moveItem(at: Staging, to: Destination)
            Moved = true
            Game = Current
            Game.ExecutablePath = Destination.appendingPathComponent(Relative).path
            Game.DirectoryPath = URL(fileURLWithPath: Game.ExecutablePath).deletingLastPathComponent().path
            Game.ManagedFilesPath = Destination.path
            Game.InstalledSizeBytes = Bytes; Game.SizeMeasuredAt = Date()
            try Update(Game)
        } catch {
            try? FileManager.default.removeItem(at: Staging)
            if Moved { try? FileManager.default.removeItem(at: Destination) }
            throw error
        }
        try FileManager.default.trashItem(at: Source, resultingItemURL: nil)
    }

    @discardableResult
    func ImportRecords(_ Records: [LibraryGame]) throws -> Int {
        var Updated = Games
        var Paths = Set(Games.map { $0.ExecutableURL.resolvingSymlinksInPath().standardizedFileURL.path })
        var Ids = Set(Games.map(\.Id))
        for Record in Records {
            let Executable = Record.ExecutableURL.resolvingSymlinksInPath().standardizedFileURL
            guard !Paths.contains(Executable.path) else { continue }
            try ValidateExecutable(Executable)
            guard !Record.Name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RuntimeError.Message("An imported game is missing its name.")
            }
            var Imported = Record
            Imported.ExecutablePath = Executable.path
            Imported.IsManaged = false
            Imported.ManagedFilesPath = nil
            while Ids.contains(Imported.Id) { Imported.Id = UUID() }
            Updated.append(Imported)
            Paths.insert(Executable.path)
            Ids.insert(Imported.Id)
        }
        let Count = Updated.count - Games.count
        if Count > 0 { try Save(Updated) }
        return Count
    }

    func RemovableFilesURL(for Game: LibraryGame, Downloads: [DownloadItem]) -> URL? {
        let Candidates: [URL] = {
            if let Path = Game.ManagedFilesPath { return [URL(fileURLWithPath: Path, isDirectory: true)] }
            if Game.IsManaged { return [Game.DirectoryURL] }
            return Downloads.compactMap { Download in
                guard Download.State == .Extracted, let Path = Download.ExtractedPath else { return nil }
                let Root = URL(fileURLWithPath: Path, isDirectory: true).standardizedFileURL
                let Expected = Download.DestinationDirectory
                    .appendingPathComponent(RuntimePaths.SafeName(Download.Name), isDirectory: true).standardizedFileURL
                return Root == Expected ? Root : nil
            }
        }()
        return Candidates.first { Root in
            Root.pathComponents.count > 3 &&
            FileManager.default.fileExists(atPath: Root.path) &&
            RuntimePaths.IsInside(Game.ExecutableURL, Root)
        }
    }

    func Remove(_ Id: UUID, DeleteFiles: Bool = false, Downloads: [DownloadItem] = []) throws {
        guard let Game = Games.first(where: { $0.Id == Id }) else { return }
        if DeleteFiles {
            guard let Root = RemovableFilesURL(for: Game, Downloads: Downloads) else {
                throw RuntimeError.Message("Imported game files are managed outside Ascendara. Remove the library entry, or move its files to Trash in Finder.")
            }
            guard !Games.contains(where: { $0.Id != Id && RuntimePaths.IsInside($0.ExecutableURL, Root) }) else {
                throw RuntimeError.Message("Another library game uses this folder. Remove its library entry before moving the shared files to Trash.")
            }
            try FileManager.default.trashItem(at: Root, resultingItemURL: nil)
        }
        try Save(Games.filter { $0.Id != Id })
    }

    func RecordSession(_ Id: UUID, StartedAt: Date, Seconds: Double) throws {
        guard var Game = Games.first(where: { $0.Id == Id }) else { return }
        Game.LastPlayedAt = StartedAt
        Game.PlayTimeSeconds += max(0, Seconds)
        try Update(Game)
    }

    func RecordManagedSession(_ Id: UUID, SessionId: UUID, StartedAt: Date,
                              TotalSeconds: Int, Summary: GameSession?) throws {
        guard var Game = Games.first(where: { $0.Id == Id }) else { return }
        let Previous = Game.RecordedSessionSecondsById[SessionId]
            ?? (Game.LastSessionId == SessionId ? Game.LastSessionRecordedSeconds : 0)
        let Total = max(0, TotalSeconds)
        let Delta = max(0, Total - Previous)
        let NewerSummary = Summary != nil && (Game.LastSession == nil || Summary!.EndedAt >= Game.LastSession!.EndedAt)
        guard Delta > 0 || (NewerSummary && Game.LastSession != Summary) else { return }
        Game.PlayTimeSeconds += Double(Delta)
        if Game.LastPlayedAt == nil || StartedAt > Game.LastPlayedAt! { Game.LastPlayedAt = StartedAt }
        Game.RecordedSessionSecondsById[SessionId] = max(Previous, Total)
        if let Summary, NewerSummary {
            Game.LastSession = Summary
            Game.LastSessionId = SessionId
            Game.LastSessionRecordedSeconds = max(Previous, Total)
        }
        try Update(Game)
    }

    func RecordLaunch(_ Id: UUID) throws {
        guard var Game = Games.first(where: { $0.Id == Id }) else { return }
        Game.LaunchCount += 1
        try Update(Game)
    }

    func ValidateExecutable(_ URL: URL) throws {
        var IsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: URL.path, isDirectory: &IsDirectory) else {
            throw RuntimeError.Message("The game executable could not be found: \(URL.path)")
        }
        if IsDirectory.boolValue {
            guard URL.pathExtension.lowercased() == "app", Bundle(url: URL)?.executableURL != nil else {
                throw RuntimeError.Message("Choose a macOS .app, a Windows executable, or an executable file.")
            }
        } else if !["exe", "msi", "bat", "cmd"].contains(URL.pathExtension.lowercased()) && !FileManager.default.isExecutableFile(atPath: URL.path) {
            throw RuntimeError.Message("This file is not executable.")
        }
    }

    @discardableResult
    func ImportLegacyLibrary(_ Directory: URL) throws -> Int {
        let Manager = FileManager.default
        let Children = try Manager.contentsOfDirectory(at: Directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        var Records: [([String: Any], URL)] = []
        let Custom = Directory.appendingPathComponent("games.json")
        if Manager.fileExists(atPath: Custom.path) {
            let Data = try Data(contentsOf: Custom)
            let Object = try JSONSerialization.jsonObject(with: Data) as? [String: Any]
            Records += ((Object?["games"] as? [[String: Any]]) ?? []).map { ($0, Directory) }
        }
        for Child in Children where (try? Child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let Metadata = Child.appendingPathComponent(Child.lastPathComponent + ".ascendara.json")
            if Manager.fileExists(atPath: Metadata.path) {
                guard let Object = try JSONSerialization.jsonObject(with: Data(contentsOf: Metadata)) as? [String: Any] else { continue }
                Records.append((Object, Child))
            }
        }
        var Updated = Games
        let Before = Updated.count
        for (Record, Root) in Records {
            guard Record["_isDeleted"] as? Bool != true, let Executable = Record["executable"] as? String, !Executable.isEmpty else { continue }
            let URL = Executable.hasPrefix("/") ? URL(fileURLWithPath: Executable) : Root.appendingPathComponent(Executable)
            let Path = URL.resolvingSymlinksInPath().standardizedFileURL
            guard !Updated.contains(where: { $0.ExecutableURL.resolvingSymlinksInPath() == Path }) else { continue }
            var Game = LibraryGame(Name: Record["game"] as? String ?? Record["name"] as? String ?? Root.lastPathComponent,
                                   CatalogId: Record["gameID"] as? String ?? Record["gameId"] as? String ?? Record["id"] as? String,
                                   DirectoryPath: Root.path, ExecutablePath: Path.path,
                                   ImageURL: Record["image"] as? String)
            Game.Favorite = Record["favorite"] as? Bool ?? false
            Game.Version = Record["version"] as? String
            Game.Notes = Record["notes"] as? String ?? ""
            Game.PlayTimeSeconds = Record["playTime"] as? Double ?? 0
            Game.LaunchCount = Record["launchCount"] as? Int ?? 0
            Game.Completed = Record["completed"] as? Bool ?? false
            if let LastPlayed = Record["lastPlayed"] as? String {
                let Formatter = ISO8601DateFormatter()
                Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                Game.LastPlayedAt = Formatter.date(from: LastPlayed) ?? ISO8601DateFormatter().date(from: LastPlayed)
            }
            Game.LaunchMode = Self.DefaultLaunchMode(for: Path)
            if Record["macRunner"] as? String == "highball" { Game.LaunchMode = .Highball }
            Game.Renderer = Record["highballRenderer"] as? String ?? "auto"
            Updated.append(Game)
        }
        try Save(Updated)
        return Updated.count - Before
    }

    func FindExecutables(in Directory: URL) throws -> [URL] {
        guard let Enumerator = FileManager.default.enumerator(at: Directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var Results: [URL] = []
        for case let Candidate as URL in Enumerator {
            if (try? Candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
            if Candidate.pathExtension.lowercased() == "app" || ["exe", "msi", "bat", "cmd"].contains(Candidate.pathExtension.lowercased()) {
                Results.append(Candidate)
            }
            if Results.count >= 500 { break }
        }
        return Results.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func DefaultLaunchMode(for Executable: URL) -> LaunchMode {
        guard ["exe", "msi", "bat", "cmd"].contains(Executable.pathExtension.lowercased()) else { return .Native }
        var Arm64: Int32 = 0
        var Size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &Arm64, &Size, nil, 0) == 0 && Arm64 == 1 ? .Highball : .Wine
    }

    func BestExecutable(in Directory: URL, GameName: String) throws -> URL? {
        let Candidates = try FindExecutables(in: Directory).filter { Candidate in
            let Name = Candidate.deletingPathExtension().lastPathComponent.lowercased()
            let Components = Candidate.pathComponents.map { $0.lowercased() }
            let BlockedDirectories = ["_commonredist", "redist", "redistributables", "prerequisites", "directx", "support", "__macosx"]
            let BlockedNames = ["setup", "install", "installer", "uninstall", "unins000", "unitycrashhandler", "crashreporter", "dxsetup", "vcredist"]
            return !Components.contains(where: { BlockedDirectories.contains($0) })
                && !BlockedNames.contains(where: { Name == $0 || Name.hasPrefix($0 + "_") || Name.hasPrefix($0 + "-") })
                && Candidate.pathExtension.lowercased() != "msi"
        }
        guard !Candidates.isEmpty else { return nil }
        if Candidates.count == 1 { return Candidates[0] }
        let Target = GameName.lowercased().filter(\.isLetter)
        let Scored = Candidates.map { Candidate -> (URL, Int) in
            let Name = Candidate.deletingPathExtension().lastPathComponent.lowercased().filter(\.isLetter)
            let Score = (Name == Target ? 100 : 0)
                + (Target.count >= 4 && Name.contains(Target) ? 40 : 0)
                + (Candidate.pathExtension.lowercased() == "app" ? 20 : 0)
                + (Candidate.pathComponents.map { $0.lowercased() }.contains("win64") ? 5 : 0)
            return (Candidate, Score)
        }.sorted { $0.1 > $1.1 }
        guard Scored[0].1 >= 40, Scored[0].1 > Scored[1].1 else { return nil }
        return Scored[0].0
    }
}


struct LibraryDiskSpace: Sendable {
    var Available: Int64 = 0
    var Total: Int64 = 0
    var Games: Int64 = 0

    static func Drive(at Path: String) -> LibraryDiskSpace {
        let Files = FileManager.default
        var Directory = URL(fileURLWithPath: Path.isEmpty ? NSHomeDirectory() : Path, isDirectory: true).standardizedFileURL
        while !Files.fileExists(atPath: Directory.path) && Directory.path != "/" {
            Directory.deleteLastPathComponent()
        }
        guard let Values = try? Files.attributesOfFileSystem(forPath: Directory.path) else { return .init() }
        let Volume = try? Directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return LibraryDiskSpace(
            Available: Volume?.volumeAvailableCapacityForImportantUsage ?? (Values[.systemFreeSize] as? NSNumber)?.int64Value ?? 0,
            Total: Int64(Volume?.volumeTotalCapacity ?? 0) > 0 ? Int64(Volume?.volumeTotalCapacity ?? 0) : (Values[.systemSize] as? NSNumber)?.int64Value ?? 0
        )
    }

    static func GameBytes(Paths: [String]) async -> Int64 {
        await Task.detached(priority: .utility) {
            MeasureGameBytes(Paths: Paths, IsCancelled: { Task.isCancelled })
        }.value
    }

    private static func MeasureGameBytes(Paths: [String], IsCancelled: () -> Bool) -> Int64 {
            let Files = FileManager.default
            let Paths = Set(Paths.map { $0.standardizedPath }).sorted { $0.count < $1.count }
            var Roots: [String] = []
            for Path in Paths where Files.fileExists(atPath: Path) {
                if !Roots.contains(where: { Path == $0 || Path.hasPrefix($0 + "/") }) { Roots.append(Path) }
            }
            var Bytes: Int64 = 0
            for Root in Roots {
                guard let Walker = Files.enumerator(at: URL(fileURLWithPath: Root, isDirectory: true),
                                                    includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey],
                                                    options: [.skipsHiddenFiles]) else { continue }
                for case let File as URL in Walker {
                    if IsCancelled() { return Bytes }
                    guard let Values = try? File.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]),
                          Values.isRegularFile == true else { continue }
                    Bytes += Int64(Values.totalFileAllocatedSize ?? Values.fileAllocatedSize ?? Values.fileSize ?? 0)
                }
            }
            return Bytes
    }

    static func GamePath(Executable: String, Directory: String) -> String {
        let ExecutableURL = URL(fileURLWithPath: Executable)
        if ExecutableURL.pathExtension.lowercased() == "app" { return ExecutableURL.path }
        var Parent = ExecutableURL.deletingLastPathComponent()
        while Parent.path != "/" {
            if Parent.pathExtension.lowercased() == "app" { return Parent.path }
            Parent.deleteLastPathComponent()
        }
        return Directory
    }
}

private extension String {
    var standardizedPath: String { URL(fileURLWithPath: self).standardizedFileURL.path }
}


enum LibraryUpdateStatus: String {
    case Current = "Up to date"
    case Available = "Update available"
    case Different = "Catalogue version differs"
    case Unknown = "Installed version unknown"
    case Unavailable = "Latest version unavailable"
    case NoMatch = "No catalogue match"
    case Failed = "Check failed"
}

struct LibraryUpdateResult {
    var Status: LibraryUpdateStatus
    var LatestGame: Game?
    var LatestVersion: String?
    var Message: String?
}

enum LibraryUpdateService {
    static func Check(Installed: LibraryGame, Games: [Game], Catalog: CatalogService) async throws -> LibraryUpdateResult {
        let Match = Games.first { Game in
            if let Id = Installed.CatalogId { return Game.Id == Id }
            return Game.Name.caseInsensitiveCompare(Installed.Name) == .orderedSame
        }
        guard let Match else { return LibraryUpdateResult(Status: .NoMatch, Message: "Choose a catalogue containing this game to compare releases.") }
        guard let Version = Installed.Version?.trimmingCharacters(in: .whitespacesAndNewlines), !Version.isEmpty else {
            return LibraryUpdateResult(Status: .Unknown, LatestGame: Match, LatestVersion: Match.Version,
                                       Message: "Enter the version shown by your installed game to compare it with the catalogue.")
        }
        guard let LatestVersion = Match.Version?.trimmingCharacters(in: .whitespacesAndNewlines), !LatestVersion.isEmpty else {
            return LibraryUpdateResult(Status: .Unavailable, LatestGame: Match, Message: "The active index does not publish a version for this game.")
        }
        let Status: LibraryUpdateStatus = Normalize(Version) == Normalize(LatestVersion) ? .Current
            : VersionComparison.IsNewer(LatestVersion, than: Version) ? .Available : .Different
        return LibraryUpdateResult(Status: Status, LatestGame: Match, LatestVersion: LatestVersion,
            Message: Status == .Different ? "The index version differs, but cannot be confirmed as newer. Review it before reinstalling." : "Compared with the active game index.")
    }

    static func Normalize(_ Version: String) -> String {
        var Value = Version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if Value.hasPrefix("v"), Value.dropFirst().first?.isNumber == true { Value.removeFirst() }
        return Value
    }
}
