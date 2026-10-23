import Foundation

enum CatalogSource: Hashable, Sendable {
    case Community
    case Local(URL)
    case Custom(URL, String)
}

struct CatalogMetadata: Codable, Hashable, Sendable {
    var Source: String = "Community"
    var SourceName: String?
    var SourceURL: String?
    var UpdatedAt: String?
    var GetDate: String?
    var GameCount: Int = 0
    var IsLocal: Bool = false
    var IsCustom: Bool = false
    var TracksHistory: Bool = false

    enum CodingKeys: String, CodingKey {
        case Source = "source", SourceName = "sourceName", SourceURL = "sourceUrl", UpdatedAt = "lastUpdated"
        case GetDate = "getDate", GameCount = "games", IsLocal = "local", IsCustom = "customSource", TracksHistory = "timemachine"
    }
    init() {}
    init(from Decoder: Decoder) throws {
        let Values = try Decoder.container(keyedBy: CodingKeys.self)
        Source = Values.Text(.Source) ?? "Community"; SourceName = Values.Text(.SourceName)
        SourceURL = Values.Text(.SourceURL); UpdatedAt = Values.Text(.UpdatedAt); GetDate = Values.Text(.GetDate)
        GameCount = Values.Text(.GameCount).flatMap(Int.init) ?? 0
        IsLocal = Values.Flag(.IsLocal); IsCustom = Values.Flag(.IsCustom); TracksHistory = Values.Flag(.TracksHistory)
    }
}

struct CatalogSnapshot: Codable, Sendable {
    var Games: [Game]
    var Metadata: CatalogMetadata
    var LoadedAt: Date = Date()
    var IsCached: Bool = false
    var Warning: String?
}

struct GameDetails: Codable, Hashable, Sendable {
    var SteamId: String
    var Name: String
    var Summary: String
    var Description: String
    var Developers: [String]
    var Publishers: [String]
    var ReleaseDate: String?
    var Genres: [String]
    var Platforms: [String]
    var Screenshots: [URL]
    var HeaderURL: URL?
    var WebsiteURL: URL?
    var MinimumRequirements: String?
    var RecommendedRequirements: String?
}

struct GameRelease: Codable, Identifiable, Sendable {
    var Version: String
    var FirstSeen: String?
    var LastSeen: String?
    var IsLive: Bool
    var Game: Game
    var id: String { "\(Game.Id)-\(Version)-\(FirstSeen ?? "")" }
    enum CodingKeys: String, CodingKey {
        case Version = "version", FirstSeen = "firstSeen", LastSeen = "lastSeen", IsLive = "live", Game = "game"
    }
}

struct GameUpdate: Codable, Sendable {
    var Id: String
    var Name: String
    var LatestVersion: String?
    var LocalVersion: String?
    var UpdateAvailable: Bool
    var AutoUpdateSupported: Bool
    var DownloadLinks: [String: [String]]
    enum CodingKeys: String, CodingKey {
        case Id = "gameID", Name = "gameName", LatestVersion = "latestVersion", LocalVersion = "localVersion"
        case UpdateAvailable = "updateAvailable", AutoUpdateSupported = "autoUpdateSupported", DownloadLinks = "downloadLinks"
    }
}
