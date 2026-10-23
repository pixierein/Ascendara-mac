import Foundation
import Combine
import AppKit

@MainActor
final class LibraryService: ObservableObject {
    @Published private(set) var Games: [LibraryGame] = []
    @Published private(set) var ErrorMessage: String?
    let StorageDirectory: URL
    private var MetadataURL: URL { StorageDirectory.appendingPathComponent("library.json") }

    init(StorageDirectory: URL = RuntimePaths.Support) {
        self.StorageDirectory = StorageDirectory
        do { try Load() } catch { ErrorMessage = error.localizedDescription }
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
    func ImportGame(Name: String, ExecutableURL: URL, CatalogId: String? = nil, ImageURL: String? = nil, Version: String? = nil) throws -> LibraryGame {
        let Path = ExecutableURL.resolvingSymlinksInPath().standardizedFileURL
        try ValidateExecutable(Path)
        if let Existing = Games.first(where: { $0.ExecutableURL.resolvingSymlinksInPath() == Path }) { return Existing }
        let CleanName = Name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !CleanName.isEmpty else { throw RuntimeError.Message("Enter a name for this game.") }
        var Game = LibraryGame(Name: CleanName, CatalogId: CatalogId, DirectoryPath: Path.deletingLastPathComponent().path,
                               ExecutablePath: Path.path, ImageURL: ImageURL)
        Game.Version = Version
        Game.LaunchMode = ["exe", "msi", "bat", "cmd"].contains(Path.pathExtension.lowercased()) ? .Wine : .Native
        try Save(Games + [Game])
        return Game
    }

    func Update(_ Game: LibraryGame) throws {
        guard let Index = Games.firstIndex(where: { $0.Id == Game.Id }) else { throw RuntimeError.Message("This game is no longer in the library.") }
        var Updated = Games
        Updated[Index] = Game
        try Save(Updated)
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
            while Ids.contains(Imported.Id) { Imported.Id = UUID() }
            Updated.append(Imported)
            Paths.insert(Executable.path)
            Ids.insert(Imported.Id)
        }
        let Count = Updated.count - Games.count
        if Count > 0 { try Save(Updated) }
        return Count
    }

    func Remove(_ Id: UUID, DeleteFiles: Bool = false) throws {
        guard let Game = Games.first(where: { $0.Id == Id }) else { return }
        if DeleteFiles {
            guard Game.IsManaged, RuntimePaths.IsInside(Game.ExecutableURL, Game.DirectoryURL),
                  Game.DirectoryURL.pathComponents.count > 3 else {
                throw RuntimeError.Message("Imported game files are managed outside Ascendara. Remove the library entry, or move its files to Trash in Finder.")
            }
            try FileManager.default.trashItem(at: Game.DirectoryURL, resultingItemURL: nil)
        }
        try Save(Games.filter { $0.Id != Id })
    }

    func RecordSession(_ Id: UUID, StartedAt: Date, Seconds: Double) throws {
        guard var Game = Games.first(where: { $0.Id == Id }) else { return }
        Game.LastPlayedAt = StartedAt
        Game.PlayTimeSeconds += max(0, Seconds)
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
            if let LastPlayed = Record["lastPlayed"] as? String {
                let Formatter = ISO8601DateFormatter()
                Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                Game.LastPlayedAt = Formatter.date(from: LastPlayed) ?? ISO8601DateFormatter().date(from: LastPlayed)
            }
            Game.LaunchMode = ["exe", "msi", "bat", "cmd"].contains(Path.pathExtension.lowercased()) ? .Wine : .Native
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
            if Candidate.pathExtension.lowercased() == "app" || ["exe", "msi"].contains(Candidate.pathExtension.lowercased()) {
                Results.append(Candidate)
            }
            if Results.count >= 500 { break }
        }
        return Results.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
