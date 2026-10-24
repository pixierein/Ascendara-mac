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

enum CatalogSort: String, CaseIterable, Identifiable, Sendable {
    case Popular = "Most popular"
    case Name = "Name A–Z"
    case Recent = "Recently updated"
    case Smallest = "Smallest size"
    var id: String { rawValue }
}

enum GameSearch {
    static func Filter(Games: [Game], Query: String = "", Categories: Set<String> = [], Sort: CatalogSort = .Popular,
                       OnlineOnly: Bool = false, DlcOnly: Bool = false, MaximumSizeGB: Double? = nil,
                       Provider: String? = nil, VerifiedIds: Set<String>? = nil) -> [Game] {
        let Search = Query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Games.filter { Game in
            (Search.isEmpty || Matches(Text: Game.Name, Query: Search)) &&
            (Categories.isEmpty || Categories.isSubset(of: Set(Game.Categories))) &&
            (!OnlineOnly || Game.Online) && (!DlcOnly || Game.Dlc) &&
            (MaximumSizeGB.map { Game.SizeGB <= $0 } ?? true) &&
            (Provider.map { Game.DownloadLinks[$0] != nil } ?? true) &&
            (VerifiedIds.map { $0.contains(Game.Id) } ?? true)
        }.sorted { Left, Right in
            switch Sort {
            case .Popular:
                if Left.Weight != Right.Weight { return (Left.Weight ?? 0) > (Right.Weight ?? 0) }
            case .Recent:
                if Left.LatestUpdate != Right.LatestUpdate { return (Left.LatestUpdate ?? "") > (Right.LatestUpdate ?? "") }
            case .Smallest:
                if Left.SizeGB != Right.SizeGB { return Left.SizeGB < Right.SizeGB }
            case .Name: break
            }
            return Left.Name.localizedStandardCompare(Right.Name) == .orderedAscending
        }
    }

    static func Matches(Text: String, Query: String) -> Bool {
        let Text = Text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let Query = Query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if Text.contains(Query) { return true }
        let Words = Text.split(whereSeparator: { $0.isWhitespace })
        return Query.split(whereSeparator: { $0.isWhitespace }).allSatisfy { QueryWord in
            if QueryWord.contains(where: { $0.isNumber }) { return Text.contains(QueryWord) }
            return Words.contains { Word in
                if Word.contains(QueryWord) { return true }
                if Word.contains(where: { $0.isNumber }) { return false }
                var Position = Word.startIndex
                var Count = 0
                for Character in QueryWord {
                    if Position < Word.endIndex, let Found = Word[Position...].firstIndex(of: Character) {
                        Count += 1; Position = Word.index(after: Found)
                    }
                }
                return Double(Count) >= Double(QueryWord.count) * 0.8
            }
        }
    }
}

struct MacCompatibility: Hashable, Sendable {
    enum Status: Hashable, Sendable {
        case Works
        case Likely
    }

    var Kind: Status
    var Evidence: String
    var SourceURL: URL
    var IsPrediction: Bool

    var Label: String { Kind == .Works ? "Mac: Works" : "Mac: Likely" }

    static let Attribution = "Mac compatibility data: Highball. Predictions are derived from ProtonDB community reports and anti-cheat data (ODbL 1.0); they are not Mac test results."
    static let AttributionURL = URL(string: "https://gethighball.com/docs/data/")!
}
