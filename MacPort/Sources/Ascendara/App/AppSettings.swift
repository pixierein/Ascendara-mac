import Foundation

struct AppSettings: Codable, Equatable {
    var DisplayName = "Player"
    var Theme = "purple"
    var DownloadDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Games/Ascendara").path
    var CatalogSource = "community"
    var CustomCatalogURL = ""
    var LocalCatalogPath = ""
    var AutoExtract = true
    var ConcurrentDownloads = 2
    var LaunchArguments = ""
    var WinePath = ""
    var HighballPath = ""
    var TorBoxAPIKey = ""
    var QBitTorrentURL = "http://localhost:8080"
    var QBitTorrentUsername = "admin"
    var QBitTorrentPassword = ""
    var DefaultPage = "Home"
    var HasCompletedWelcome = false
    var ShowWorkshop = false
    var ReduceMotion = false
    var FirebaseAPIKey = ""
    var FirebaseProjectId = ""
    var SteamCMDPath = ""
    var RetroEmulatorPath = ""
    var RetroArguments = "{rom}"
    var KeepAwake = true
    var DockScale = 1.0
    var BackupDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Games/Ascendara Backups").path

    static func Load(From URL: URL) throws -> AppSettings {
        let DefaultData = try JSONEncoder().encode(AppSettings())
        var Values = try JSONSerialization.jsonObject(with: DefaultData) as? [String: Any] ?? [:]
        guard let Saved = try JSONSerialization.jsonObject(with: Data(contentsOf: URL)) as? [String: Any] else {
            throw AppFailure.Message("The settings file must contain a JSON object.")
        }
        Values.merge(Saved) { _, New in New }
        return try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: Values))
    }

    func PublicCopy() -> AppSettings {
        var Result = self
        Result.TorBoxAPIKey = ""
        Result.QBitTorrentPassword = ""
        return Result
    }
}

enum AppPaths {
    static var Support: URL {
        if let Override = ProcessInfo.processInfo.environment["ASCENDARA_NATIVE_HOME"] {
            return URL(fileURLWithPath: Override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ascendara Native", isDirectory: true)
    }

    static func Read<Value: Decodable>(_ Type: Value.Type, From URL: URL) throws -> Value {
        try JSONDecoder().decode(Type, from: Data(contentsOf: URL))
    }

    static func Write<Value: Encodable>(_ Value: Value, To URL: URL) throws {
        try FileManager.default.createDirectory(at: URL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let Encoder = JSONEncoder()
        Encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try Encoder.encode(Value).write(to: URL, options: .atomic)
    }
}

enum AppRoute: String, CaseIterable, Identifiable, Codable {
    case Home, Search, Library, Downloads, Wishlist, Profile, Ascend, Settings, Sources, Tools, TorBox, Workshop, Retro
    var id: String { rawValue }
    var Title: String {
        switch self {
        case .Settings: return "Preferences"
        case .Sources: return "External sources"
        case .Tools: return "Tools & dependencies"
        case .TorBox: return "TorBox"
        case .Workshop: return "Workshop"
        default: return rawValue
        }
    }
    var Icon: String {
        switch self {
        case .Home: return "house"
        case .Search: return "magnifyingglass"
        case .Library: return "books.vertical"
        case .Downloads: return "arrow.down.circle"
        case .Wishlist: return "heart"
        case .Profile: return "person.crop.circle"
        case .Ascend: return "at"
        case .Settings: return "slider.horizontal.3"
        case .Sources: return "externaldrive.connected.to.line.below"
        case .Tools: return "wrench.and.screwdriver"
        case .TorBox: return "server.rack"
        case .Workshop: return "shippingbox"
        case .Retro: return "gamecontroller"
        }
    }
}

enum AppFailure: LocalizedError {
    case Message(String)
    var errorDescription: String? {
        switch self { case .Message(let Message): return Message }
    }
}
