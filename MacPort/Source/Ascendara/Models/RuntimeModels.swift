import Foundation

enum LaunchMode: String, Codable, CaseIterable, Identifiable {
    case Native, Wine, Highball
    var id: String { rawValue }
}

struct GameSession: Codable, Equatable {
    var Seconds: Int
    var Crashed: Bool
    var EndedAt: Date
}

struct LibraryGame: Codable, Identifiable, Equatable {
    var Id = UUID()
    var Name: String
    var CatalogId: String?
    var Version: String?
    var DirectoryPath: String
    var ExecutablePath: String
    var ImageURL: String?
    var AddedAt = Date()
    var LastPlayedAt: Date?
    var LastSession: GameSession?
    var LastSessionId: UUID?
    var LastSessionRecordedSeconds = 0
    var RecordedSessionSecondsById: [UUID: Int] = [:]
    var PlayTimeSeconds: Double = 0
    var LaunchCount: Int = 0
    var Completed = false
    var Favorite = false
    var Notes = ""
    var Collection = ""
    var SaveDirectory: String?
    var LaunchArguments: [String] = []
    var LaunchMode: LaunchMode = .Native
    var WinePrefixPath: String?
    var Renderer = "auto"
    var HighballBottle = "ascendara"
    var IsManaged = false
    var ManagedFilesPath: String?
    var InstalledSizeBytes: Int64?
    var SizeMeasuredAt: Date?
    var AutomaticallyUpdate = false
    var id: UUID { Id }
    var ExecutableURL: URL { URL(fileURLWithPath: ExecutablePath) }
    var DirectoryURL: URL { URL(fileURLWithPath: DirectoryPath, isDirectory: true) }
    var ArtworkURL: URL? { ImageURL.flatMap(URL.init(string:)) }
    var IsInstalled: Bool { FileManager.default.fileExists(atPath: ExecutablePath) }

    private enum CodingKeys: String, CodingKey {
        case Id, Name, CatalogId, Version, DirectoryPath, ExecutablePath, ImageURL, AddedAt, LastPlayedAt, LastSession, LastSessionId, LastSessionRecordedSeconds, RecordedSessionSecondsById, PlayTimeSeconds, LaunchCount, Completed
        case Favorite, Notes, Collection, SaveDirectory, LaunchArguments, LaunchMode, WinePrefixPath, Renderer, HighballBottle, IsManaged, ManagedFilesPath
        case InstalledSizeBytes, SizeMeasuredAt, AutomaticallyUpdate
    }
}

extension LibraryGame {
    init(from Decoder: Decoder) throws {
        let Values = try Decoder.container(keyedBy: CodingKeys.self)
        Id = try Values.decodeIfPresent(UUID.self, forKey: .Id) ?? UUID()
        Name = try Values.decode(String.self, forKey: .Name)
        ExecutablePath = try Values.decode(String.self, forKey: .ExecutablePath)
        DirectoryPath = try Values.decodeIfPresent(String.self, forKey: .DirectoryPath) ?? URL(fileURLWithPath: ExecutablePath).deletingLastPathComponent().path
        CatalogId = try Values.decodeIfPresent(String.self, forKey: .CatalogId)
        Version = try Values.decodeIfPresent(String.self, forKey: .Version)
        ImageURL = try Values.decodeIfPresent(String.self, forKey: .ImageURL)
        AddedAt = try Values.decodeIfPresent(Date.self, forKey: .AddedAt) ?? Date()
        LastPlayedAt = try Values.decodeIfPresent(Date.self, forKey: .LastPlayedAt)
        LastSession = try Values.decodeIfPresent(GameSession.self, forKey: .LastSession)
        LastSessionId = try Values.decodeIfPresent(UUID.self, forKey: .LastSessionId)
        LastSessionRecordedSeconds = try Values.decodeIfPresent(Int.self, forKey: .LastSessionRecordedSeconds) ?? 0
        RecordedSessionSecondsById = try Values.decodeIfPresent([UUID: Int].self, forKey: .RecordedSessionSecondsById) ?? [:]
        PlayTimeSeconds = try Values.decodeIfPresent(Double.self, forKey: .PlayTimeSeconds) ?? 0
        LaunchCount = try Values.decodeIfPresent(Int.self, forKey: .LaunchCount) ?? 0
        Completed = try Values.decodeIfPresent(Bool.self, forKey: .Completed) ?? false
        Favorite = try Values.decodeIfPresent(Bool.self, forKey: .Favorite) ?? false
        Notes = try Values.decodeIfPresent(String.self, forKey: .Notes) ?? ""
        Collection = try Values.decodeIfPresent(String.self, forKey: .Collection) ?? ""
        SaveDirectory = try Values.decodeIfPresent(String.self, forKey: .SaveDirectory)
        LaunchArguments = try Values.decodeIfPresent([String].self, forKey: .LaunchArguments) ?? []
        LaunchMode = try Values.decodeIfPresent(Ascendara.LaunchMode.self, forKey: .LaunchMode) ?? .Native
        WinePrefixPath = try Values.decodeIfPresent(String.self, forKey: .WinePrefixPath)
        Renderer = try Values.decodeIfPresent(String.self, forKey: .Renderer) ?? "auto"
        HighballBottle = try Values.decodeIfPresent(String.self, forKey: .HighballBottle) ?? "ascendara"
        IsManaged = try Values.decodeIfPresent(Bool.self, forKey: .IsManaged) ?? false
        ManagedFilesPath = try Values.decodeIfPresent(String.self, forKey: .ManagedFilesPath)
        InstalledSizeBytes = try Values.decodeIfPresent(Int64.self, forKey: .InstalledSizeBytes)
        SizeMeasuredAt = try Values.decodeIfPresent(Date.self, forKey: .SizeMeasuredAt)
        AutomaticallyUpdate = try Values.decodeIfPresent(Bool.self, forKey: .AutomaticallyUpdate) ?? false
    }
}

enum DownloadState: String, Codable {
    case Queued, Downloading, Paused, Completed, Extracting, Extracted, Failed, Cancelled
}

struct DownloadCookie: Codable {
    var Name: String
    var Value: String
    var Domain: String
    var Path: String
    var Secure: Bool
    var HTTPOnly: Bool
    var ExpiresAt: Date?

    init?(_ Cookie: HTTPCookie) {
        let Unsafe = CharacterSet(charactersIn: "\r\n\t\0")
        guard !Cookie.name.isEmpty, Cookie.name.rangeOfCharacter(from: Unsafe) == nil,
              Cookie.value.rangeOfCharacter(from: Unsafe) == nil,
              Cookie.domain.rangeOfCharacter(from: Unsafe) == nil,
              Cookie.path.rangeOfCharacter(from: Unsafe) == nil else { return nil }
        Name = Cookie.name
        Value = Cookie.value
        Domain = Cookie.domain.lowercased()
        Path = Cookie.path.isEmpty ? "/" : Cookie.path
        Secure = Cookie.isSecure
        HTTPOnly = Cookie.isHTTPOnly
        ExpiresAt = Cookie.expiresDate
    }
}

struct InstallationPlan: Codable, Equatable {
    var ReplaceGameId: UUID
    var DestinationPath: String
    var KeepPlaytime = true
    var KeepAchievements = true
}

struct ReinstallRequest: Identifiable {
    let Id = UUID()
    var id: UUID { Id }
    let Game: Game
    let Installed: LibraryGame
    let Link: String
}

struct DownloadItem: Codable, Identifiable, Equatable {
    var Id = UUID()
    var Name: String
    var SourceURL: URL
    var DestinationDirectory: URL
    var FileName: String
    var State: DownloadState = .Queued
    var ReceivedBytes: Int64 = 0
    var TotalBytes: Int64 = 0
    var BytesPerSecond: Double = 0
    var ErrorMessage: String?
    var CreatedAt = Date()
    var CatalogId: String?
    var BatchId: UUID?
    var Version: String?
    var ExtractedPath: String?
    var ResumeData: Data?
    var RequestHeaders: [String: String] = [:]
    var EstimatedBytes: Int64?
    var Installation: InstallationPlan?
    var ImportCompleted = false
    var id: UUID { Id }
    var Progress: Double { TotalBytes > 0 ? min(1, max(0, Double(ReceivedBytes) / Double(TotalBytes))) : 0 }
    var FileURL: URL { DestinationDirectory.appendingPathComponent(FileName) }
    var IsActive: Bool { State == .Downloading || State == .Queued || State == .Extracting }

    private enum CodingKeys: String, CodingKey {
        case Id, Name, SourceURL, DestinationDirectory, FileName, State, ReceivedBytes, TotalBytes, BytesPerSecond
        case ErrorMessage, CreatedAt, CatalogId, BatchId, Version, ExtractedPath, ResumeData, RequestHeaders, EstimatedBytes, Installation, ImportCompleted
    }
}

extension DownloadItem {
    init(from Decoder: Decoder) throws {
        let Values = try Decoder.container(keyedBy: CodingKeys.self)
        Id = try Values.decode(UUID.self, forKey: .Id)
        Name = try Values.decode(String.self, forKey: .Name)
        SourceURL = try Values.decode(URL.self, forKey: .SourceURL)
        DestinationDirectory = try Values.decode(URL.self, forKey: .DestinationDirectory)
        FileName = try Values.decode(String.self, forKey: .FileName)
        State = try Values.decodeIfPresent(DownloadState.self, forKey: .State) ?? .Paused
        ReceivedBytes = try Values.decodeIfPresent(Int64.self, forKey: .ReceivedBytes) ?? 0
        TotalBytes = try Values.decodeIfPresent(Int64.self, forKey: .TotalBytes) ?? 0
        BytesPerSecond = 0
        ErrorMessage = try Values.decodeIfPresent(String.self, forKey: .ErrorMessage)
        CreatedAt = try Values.decodeIfPresent(Date.self, forKey: .CreatedAt) ?? Date()
        CatalogId = try Values.decodeIfPresent(String.self, forKey: .CatalogId)
        BatchId = try Values.decodeIfPresent(UUID.self, forKey: .BatchId)
        Version = try Values.decodeIfPresent(String.self, forKey: .Version)
        ExtractedPath = try Values.decodeIfPresent(String.self, forKey: .ExtractedPath)
        ResumeData = try Values.decodeIfPresent(Data.self, forKey: .ResumeData)
        RequestHeaders = try Values.decodeIfPresent([String: String].self, forKey: .RequestHeaders) ?? [:]
        EstimatedBytes = try Values.decodeIfPresent(Int64.self, forKey: .EstimatedBytes)
        Installation = try Values.decodeIfPresent(InstallationPlan.self, forKey: .Installation)
        ImportCompleted = try Values.decodeIfPresent(Bool.self, forKey: .ImportCompleted) ?? false
    }
}

struct CompatibilityStatus: Equatable {
    var AppleSilicon = false
    var RosettaInstalled = false
    var WinePath: String?
    var HighballPath: String?
    var Engines: [String] = []
    var Bottles: [String] = []
    var BottleEngines: [String: String] = [:]
    var ErrorMessage: String?
    var WineAvailable: Bool { WinePath != nil }
    var HighballAvailable: Bool { HighballPath != nil && AppleSilicon }
}

struct GameBackup: Codable, Identifiable {
    var Id = UUID()
    var GameId: UUID
    var Name: String
    var CreatedAt = Date()
    var SourcePath: String
    var StoredPath: String
    var id: UUID { Id }
}

enum RuntimeError: LocalizedError {
    case Message(String)
    var errorDescription: String? {
        switch self { case .Message(let Message): return Message }
    }
}

enum RuntimePaths {
    static var Support: URL {
        AppPaths.Support
    }

    static func CreateDirectory(_ URL: URL) throws {
        try FileManager.default.createDirectory(at: URL, withIntermediateDirectories: true)
    }

    static func IsInside(_ Child: URL, _ Parent: URL) -> Bool {
        let Root = Parent.resolvingSymlinksInPath().standardizedFileURL.path
        let Path = Child.resolvingSymlinksInPath().standardizedFileURL.path
        return Path.hasPrefix(Root.hasSuffix("/") ? Root : Root + "/")
    }

    static func SafeName(_ Name: String) -> String {
        let Clean = Name.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\0").union(.controlCharacters)).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Clean.isEmpty || Clean == "." || Clean == ".." ? "Game" : String(Clean.prefix(160))
    }
}
