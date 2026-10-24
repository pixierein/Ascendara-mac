import Foundation

actor BackupService {
    let StorageDirectory: URL

    init(StorageDirectory: URL = RuntimePaths.Support.appendingPathComponent("Backups", isDirectory: true)) {
        self.StorageDirectory = StorageDirectory
    }

    func List(GameId: UUID? = nil) throws -> [GameBackup] {
        guard FileManager.default.fileExists(atPath: StorageDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: StorageDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .compactMap { Directory -> GameBackup? in
                let Manifest = Directory.appendingPathComponent("backup.json")
                guard FileManager.default.fileExists(atPath: Manifest.path) else { return nil }
                return try JSONDecoder().decode(GameBackup.self, from: Data(contentsOf: Manifest))
            }.filter { GameId == nil || $0.GameId == GameId }.sorted { $0.CreatedAt > $1.CreatedAt }
    }

    @discardableResult
    func Create(_ Game: LibraryGame, SourceURL: URL? = nil) throws -> GameBackup {
        let Source = (SourceURL ?? (Game.ExecutableURL.pathExtension.lowercased() == "app" ? Game.ExecutableURL : Game.DirectoryURL)).standardizedFileURL
        guard Self.IsSafeSource(Source), FileManager.default.fileExists(atPath: Source.path) else { throw RuntimeError.Message("Choose an existing game or save directory to back up.") }
        guard !RuntimePaths.IsInside(StorageDirectory, Source), Source.resolvingSymlinksInPath() != StorageDirectory.resolvingSymlinksInPath() else { throw RuntimeError.Message("The backup destination cannot be inside its source.") }
        var Backup = GameBackup(GameId: Game.Id, Name: Game.Name, SourcePath: Source.path, StoredPath: "")
        let Directory = StorageDirectory.appendingPathComponent(Backup.Id.uuidString, isDirectory: true)
        let Stored = Directory.appendingPathComponent("Files")
        Backup.StoredPath = Stored.path
        try RuntimePaths.CreateDirectory(Directory)
        do {
            try FileManager.default.copyItem(at: Source, to: Stored)
            try JSONEncoder().encode(Backup).write(to: Directory.appendingPathComponent("backup.json"), options: .atomic)
            return Backup
        } catch {
            try? FileManager.default.removeItem(at: Directory)
            throw error
        }
    }

    @discardableResult
    func Restore(_ Backup: GameBackup) throws -> URL? {
        let Stored = URL(fileURLWithPath: Backup.StoredPath)
        let Target = URL(fileURLWithPath: Backup.SourcePath)
        guard RuntimePaths.IsInside(Stored, StorageDirectory), FileManager.default.fileExists(atPath: Stored.path), Self.IsSafeSource(Target) else { throw RuntimeError.Message("This backup has an invalid source or destination.") }
        let Parent = Target.deletingLastPathComponent()
        let Staging = Parent.appendingPathComponent(".ascendara-restore-" + UUID().uuidString)
        let Previous = Parent.appendingPathComponent(Target.lastPathComponent + ".before-restore-" + UUID().uuidString)
        try FileManager.default.copyItem(at: Stored, to: Staging)
        var Retained: URL?
        do {
            if FileManager.default.fileExists(atPath: Target.path) {
                try FileManager.default.moveItem(at: Target, to: Previous)
                Retained = Previous
            }
            try FileManager.default.moveItem(at: Staging, to: Target)
            return Retained
        } catch {
            if let Retained, !FileManager.default.fileExists(atPath: Target.path) { try? FileManager.default.moveItem(at: Retained, to: Target) }
            try? FileManager.default.removeItem(at: Staging)
            throw error
        }
    }

    func Delete(_ Backup: GameBackup) throws {
        let Directory = StorageDirectory.appendingPathComponent(Backup.Id.uuidString)
        guard RuntimePaths.IsInside(Directory, StorageDirectory) else { throw RuntimeError.Message("Invalid backup path.") }
        try FileManager.default.removeItem(at: Directory)
    }

    nonisolated static func IsSafeSource(_ URL: URL) -> Bool {
        let Path = URL.resolvingSymlinksInPath().standardizedFileURL
        return Path.pathComponents.count >= 3 && Path != FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().standardizedFileURL
    }
}
