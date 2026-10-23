import Foundation

enum CatalogError: LocalizedError {
    case InvalidSource
    case InvalidResponse
    case HTTP(Int)
    case InvalidCatalog(String)
    case HistoryBusy

    var errorDescription: String? {
        switch self {
        case .InvalidSource: return "Choose a JSON file or an HTTP or HTTPS catalogue URL."
        case .InvalidResponse: return "The catalogue server returned an invalid response."
        case .HTTP(401), .HTTP(403): return "The source refused access. It may require sign-in or a browser challenge; import its JSON file instead."
        case .HTTP(404): return "The requested catalogue or game was not found."
        case .HTTP(429): return "The server is receiving too many requests. Try again later."
        case .HTTP(let Status): return "The server returned HTTP \(Status)."
        case .InvalidCatalog(let Reason): return "Could not read this catalogue: \(Reason)"
        case .HistoryBusy: return "Time machine history is still being prepared by the server."
        }
    }
}

actor CatalogService {
    static let CommunityURL = URL(string: "https://api.ascendara.app/json/v2/games")!
    private let Session: URLSession
    private let CacheDirectory: URL
    private var Memory: [String: CacheRecord] = [:]
    private var Details: [String: (Date, GameDetails)] = [:]
    private var Verified: (Date, Set<String>)?

    private struct CacheRecord: Codable {
        var Source: String
        var ETag: String?
        var Snapshot: CatalogSnapshot
    }

    init(CacheDirectory: URL? = nil, Session: URLSession = .shared) {
        self.Session = Session
        self.CacheDirectory = CacheDirectory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AscendaraNative/Catalog", isDirectory: true)
    }

    func Load(Source: CatalogSource = .Community, Force: Bool = false) async throws -> CatalogSnapshot {
        if case .Local(let File) = Source { return try Import(File: File) }
        let Address: URL
        let Lifetime: TimeInterval
        switch Source {
        case .Community: Address = Self.CommunityURL; Lifetime = 3600
        case .Custom(let URL, _): Address = URL; Lifetime = 12 * 3600
        case .Local: throw CatalogError.InvalidSource
        }
        guard ["http", "https"].contains(Address.scheme?.lowercased() ?? "") else { throw CatalogError.InvalidSource }
        let Key = Address.absoluteString
        let Cached = Memory[Key] ?? ReadCache(Key: Key)
        if !Force, let Cached, Date().timeIntervalSince(Cached.Snapshot.LoadedAt) < Lifetime {
            var Snapshot = Cached.Snapshot
            Snapshot.IsCached = true
            return Snapshot
        }
        do {
            var Request = URLRequest(url: Address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
            Request.setValue("application/json", forHTTPHeaderField: "Accept")
            Request.setValue("AscendaraNative/1.0", forHTTPHeaderField: "User-Agent")
            if !Force, let ETag = Cached?.ETag { Request.setValue(ETag, forHTTPHeaderField: "If-None-Match") }
            let (Data, Response) = try await Session.data(for: Request)
            guard let Response = Response as? HTTPURLResponse else { throw CatalogError.InvalidResponse }
            if Response.statusCode == 304, var Record = Cached {
                Record.Snapshot.LoadedAt = Date(); Record.Snapshot.IsCached = true; Record.Snapshot.Warning = nil
                SaveCache(Record: Record)
                return Record.Snapshot
            }
            guard (200..<300).contains(Response.statusCode) else { throw CatalogError.HTTP(Response.statusCode) }
            let Snapshot = try Self.Decode(Data: Data, Source: Source)
            if case .Community = Source, Snapshot.Games.isEmpty {
                throw CatalogError.InvalidCatalog("The community server returned an empty game list.")
            }
            let Record = CacheRecord(Source: Key, ETag: Response.value(forHTTPHeaderField: "ETag"), Snapshot: Snapshot)
            SaveCache(Record: Record)
            return Snapshot
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            guard let Cached else { throw error }
            var Snapshot = Cached.Snapshot
            Snapshot.IsCached = true
            Snapshot.Warning = "Using the saved catalogue from \(Snapshot.LoadedAt.formatted(date: .abbreviated, time: .shortened)). \(error.localizedDescription)"
            return Snapshot
        }
    }

    func Import(File: URL) throws -> CatalogSnapshot {
        guard File.isFileURL else { throw CatalogError.InvalidSource }
        var IsDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: File.path, isDirectory: &IsDirectory)
        let Address = IsDirectory.boolValue ? File.appendingPathComponent("ascendara_games.json") : File
        let Data = try Data(contentsOf: Address)
        return try Self.Decode(Data: Data, Source: .Local(Address), ArtworkDirectory: Address.deletingLastPathComponent().appendingPathComponent("imgs"))
    }

    func ClearCache() throws {
        Memory.removeAll(); Details.removeAll(); Verified = nil
        if FileManager.default.fileExists(atPath: CacheDirectory.path) { try FileManager.default.removeItem(at: CacheDirectory) }
    }

    static func Decode(Data: Data, Source: CatalogSource = .Community, ArtworkDirectory: URL? = nil) throws -> CatalogSnapshot {
        let Root = try JSONSerialization.jsonObject(with: Data)
        var Snapshot: CatalogSnapshot
        if let Object = Root as? [String: Any], let Downloads = Object["downloads"] as? [[String: Any]] {
            let Label: String
            if let Name = Object["name"] as? String { Label = Name }
            else if case .Custom(_, let Name) = Source { Label = Name }
            else { Label = "Custom" }
            var Seen: Set<String> = []
            let Games = Downloads.compactMap { Entry -> Game? in
                guard let RawTitle = Entry["title"] as? String, !RawTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                let URIs = (Entry["uris"] as? [String] ?? []).filter { !$0.isEmpty }
                let VersionPattern = #"\(v[^)]+\)|\[v[^\]]+\]|\sv\d[\w.-]*"#
                let BuildPattern = #"Build\s*\d+"#
                var Version: String?
                if let Range = RawTitle.range(of: VersionPattern, options: [.regularExpression, .caseInsensitive]) {
                    Version = String(RawTitle[Range]).trimmingCharacters(in: CharacterSet(charactersIn: " ()[]"))
                    if Version?.lowercased().hasPrefix("v") == true { Version?.removeFirst() }
                } else if let Range = RawTitle.range(of: BuildPattern, options: [.regularExpression, .caseInsensitive]) { Version = String(RawTitle[Range]) }
                var Name = RawTitle
                for Pattern in [VersionPattern, BuildPattern, #"\[[^\]]*\]|\{[^}]*\}"#, #"\s*(free\s+download|full\s+version|repack|pc\s+game|\+\s*all\s+dlcs?|\+\s*\d+\s+dlcs?)\s*"#] {
                    Name = Name.replacingOccurrences(of: Pattern, with: " ", options: [.regularExpression, .caseInsensitive])
                }
                Name = CatalogText.Clean(Name.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \t\n-–—:|")))
                var Links: [String: [String]] = [:]
                for URI in URIs {
                    if URI.lowercased().hasPrefix("magnet:") { Links["torrent", default: []].append(URI); continue }
                    guard let Address = URL(string: URI), let Host = Address.host?.lowercased() else { continue }
                    let Parts = Host.split(separator: ".")
                    let Provider = Parts.count > 1 ? String(Parts[Parts.count - 2]) : Host
                    Links[Provider, default: []].append(URI)
                }
                var Id = CatalogText.StableId("\(Label)::\(RawTitle)::\(URIs.joined(separator: "|"))")
                if Seen.contains(Id) { Id = CatalogText.StableId("\(Id)-\(Seen.count)-\(Name)") }
                Seen.insert(Id)
                let UploadDate = Entry["uploadDate"] as? String
                return Game(Id: Id, Name: Name.isEmpty ? CatalogText.Clean(RawTitle) : Name, Version: Version,
                            Size: Entry["fileSize"] as? String, ReleasedBy: Label, LatestUpdate: UploadDate.map { String($0.prefix(10)) },
                            DownloadLinks: Links, CustomSource: Label)
            }
            var Metadata = CatalogMetadata()
            Metadata.Source = Label.uppercased(); Metadata.SourceName = Label; Metadata.IsCustom = true
            if case .Custom(let URL, _) = Source { Metadata.SourceURL = URL.absoluteString }
            Snapshot = CatalogSnapshot(Games: Games, Metadata: Metadata)
        } else if let Object = Root as? [String: Any], Object["games"] is [Any] {
            struct Document: Decodable {
                var Games: [Game]
                var Metadata: CatalogMetadata?
                enum CodingKeys: String, CodingKey { case Games = "games", Metadata = "metadata" }
            }
            let Decoded = try JSONDecoder().decode(Document.self, from: Data)
            Snapshot = CatalogSnapshot(Games: Decoded.Games, Metadata: Decoded.Metadata ?? CatalogMetadata())
        } else if Root is [Any] {
            Snapshot = CatalogSnapshot(Games: try JSONDecoder().decode([Game].self, from: Data), Metadata: CatalogMetadata())
        } else { throw CatalogError.InvalidCatalog("Expected a games array or a Hydra downloads array.") }

        var Seen: Set<String> = []
        Snapshot.Games = Snapshot.Games.filter { Seen.insert($0.Id).inserted }.map { Entry in
            var Entry = Entry
            if let ArtworkDirectory, let ImageId = Entry.ImageId,
               ImageId.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil {
                Entry.LocalArtworkURL = ArtworkDirectory.appendingPathComponent("\(ImageId).jpg")
            }
            return Entry
        }
        if case .Local = Source { Snapshot.Metadata.IsLocal = true }
        Snapshot.Metadata.GameCount = Snapshot.Games.count
        return Snapshot
    }

    func LoadVerifiedIds() async throws -> Set<String> {
        if let Verified, Date().timeIntervalSince(Verified.0) < 86400 { return Verified.1 }
        let Data = try await Fetch(URL: URL(string: "https://api.ascendara.app/v3/verifiedgames")!)
        let Ids = Set(try JSONDecoder().decode([String].self, from: Data))
        Verified = (Date(), Ids)
        return Ids
    }

    func LoadDetails(Game: Game) async throws -> GameDetails? {
        if let Cached = Details[Game.Id], Date().timeIntervalSince(Cached.0) < 86400 { return Cached.1 }
        var SteamId = Game.SteamId
        if SteamId == nil {
            let Target = Self.NormalizedTitle(Game.Name)
            for (Index, Term) in Self.SearchVariations(Game.Name).enumerated() {
                if Index > 0 { try await Task.sleep(nanoseconds: 300_000_000) }
                var Components = URLComponents(string: "https://api.ascendara.app/api/proxy/steam/search")!
                Components.queryItems = [URLQueryItem(name: "term", value: Term)]
                let Data = try await Fetch(URL: Components.url!)
                let Object = try JSONSerialization.jsonObject(with: Data) as? [String: Any]
                let Items = Object?["items"] as? [[String: Any]] ?? []
                let Ranked = Items.compactMap { Item -> (String, Double)? in
                    guard let Name = Item["name"] as? String, let Id = Item["id"] else { return nil }
                    let Score = Self.MatchScore(Target, Self.NormalizedTitle(Name))
                    return Score > 0.5 ? (String(describing: Id), Score) : nil
                }.sorted { $0.1 > $1.1 }
                if let Match = Ranked.first { SteamId = Match.0; break }
            }
        }
        guard let SteamId else { return nil }
        var Components = URLComponents(string: "https://api.ascendara.app/api/proxy/steam/appdetails")!
        Components.queryItems = [URLQueryItem(name: "appids", value: SteamId)]
        let Data = try await Fetch(URL: Components.url!)
        guard let Detail = try Self.DecodeDetails(Data: Data, SteamId: SteamId) else { return nil }
        Details[Game.Id] = (Date(), Detail)
        return Detail
    }

    static func DecodeDetails(Data: Data, SteamId: String) throws -> GameDetails? {
        guard let Root = try JSONSerialization.jsonObject(with: Data) as? [String: Any] else { throw CatalogError.InvalidResponse }
        guard let Entry = Root.values.compactMap({ $0 as? [String: Any] }).first(where: {
            guard $0["success"] as? Bool == true, let Payload = $0["data"] as? [String: Any], let Id = Payload["steam_appid"] else { return false }
            return String(describing: Id) == SteamId
        }), let Payload = Entry["data"] as? [String: Any] else { return nil }
        let PlatformData = Payload["platforms"] as? [String: Bool] ?? [:]
        let Requirements = Payload["pc_requirements"] as? [String: String] ?? [:]
        let Platforms = [("windows", "Windows"), ("mac", "Mac"), ("linux", "Linux")].compactMap { PlatformData[$0.0] == true ? $0.1 : nil }
        return GameDetails(SteamId: SteamId, Name: Payload["name"] as? String ?? "",
            Summary: CatalogText.Clean(Payload["short_description"] as? String ?? ""),
            Description: CatalogText.Clean(Payload["about_the_game"] as? String ?? Payload["detailed_description"] as? String ?? ""),
            Developers: Payload["developers"] as? [String] ?? [], Publishers: Payload["publishers"] as? [String] ?? [],
            ReleaseDate: (Payload["release_date"] as? [String: Any])?["date"] as? String,
            Genres: (Payload["genres"] as? [[String: Any]] ?? []).compactMap { $0["description"] as? String },
            Platforms: Platforms,
            Screenshots: (Payload["screenshots"] as? [[String: Any]] ?? []).compactMap { ($0["path_full"] as? String).flatMap(URL.init(string:)) },
            HeaderURL: (Payload["header_image"] as? String).flatMap(URL.init(string:)),
            WebsiteURL: URL(string: "https://store.steampowered.com/app/\(SteamId)"),
            MinimumRequirements: Requirements["minimum"].map(CatalogText.Clean),
            RecommendedRequirements: Requirements["recommended"].map(CatalogText.Clean))
    }

    func LoadReleases(Game: Game) async throws -> [GameRelease] {
        let URL = URL(string: "https://api.ascendara.app/json/v2/timemachine")!.appendingPathComponent(Game.Id)
        do {
            let Data = try await Fetch(URL: URL)
            struct Response: Decodable {
                var Releases: [GameRelease]
                enum CodingKeys: String, CodingKey { case Releases = "releases" }
            }
            return try JSONDecoder().decode(Response.self, from: Data).Releases
        } catch CatalogError.HTTP(404) { return [] }
        catch CatalogError.HTTP(503) { throw CatalogError.HistoryBusy }
    }

    func CheckUpdate(GameId: String, Version: String?) async throws -> GameUpdate? {
        let Address = URL(string: "https://api.ascendara.app/v3/game/checkupdate")!.appendingPathComponent(GameId)
        var Components = URLComponents(url: Address, resolvingAgainstBaseURL: false)!
        Components.queryItems = [URLQueryItem(name: "local_version", value: Version ?? "")]
        do { return try JSONDecoder().decode(GameUpdate.self, from: await Fetch(URL: Components.url!)) }
        catch CatalogError.HTTP(404) { return nil }
    }

    private func Fetch(URL: URL) async throws -> Data {
        var Request = URLRequest(url: URL, timeoutInterval: 30)
        Request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (Data, Response) = try await Session.data(for: Request)
        guard let Response = Response as? HTTPURLResponse else { throw CatalogError.InvalidResponse }
        guard (200..<300).contains(Response.statusCode) else { throw CatalogError.HTTP(Response.statusCode) }
        return Data
    }

    private func CacheURL(Key: String) -> URL {
        var Hash: UInt64 = 14695981039346656037
        for Byte in Key.utf8 { Hash = (Hash ^ UInt64(Byte)) &* 1099511628211 }
        return CacheDirectory.appendingPathComponent(String(Hash, radix: 16) + ".json")
    }
    private func ReadCache(Key: String) -> CacheRecord? {
        guard let Data = try? Data(contentsOf: CacheURL(Key: Key)),
              let Record = try? JSONDecoder().decode(CacheRecord.self, from: Data), Record.Source == Key else { return nil }
        Memory[Key] = Record
        return Record
    }
    private func SaveCache(Record: CacheRecord) {
        Memory[Record.Source] = Record
        do {
            try FileManager.default.createDirectory(at: CacheDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(Record).write(to: CacheURL(Key: Record.Source), options: .atomic)
        } catch { }
    }
    private static func NormalizedTitle(_ Name: String) -> String {
        Name.lowercased().replacingOccurrences(of: "[™®©]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[:\\-–—]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(edition|remastered|demo|dlc|goty|complete|definitive|enhanced|ultimate|deluxe|premium|gold|standard)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func SearchVariations(_ Name: String) -> [String] {
        var Variations = [Name]
        for Pattern in [#"\s*[-–—]\s*.+$"#, #":\s*.+$"#] {
            Variations.append(Name.replacingOccurrences(of: Pattern, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        Variations += [NormalizedTitle(Name), Name.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)]
        var Seen: Set<String> = []
        return Variations.filter { !$0.isEmpty && Seen.insert($0).inserted }
    }
    private static func MatchScore(_ Left: String, _ Right: String) -> Double {
        if Left == Right { return 1 }
        if Left.isEmpty || Right.isEmpty { return 0 }
        if Left.replacingOccurrences(of: " ", with: "") == Right.replacingOccurrences(of: " ", with: "") { return 0.9 }
        if Left.contains(Right) || Right.contains(Left) { return 0.8 }
        let LeftWords = Left.split(separator: " ").filter { $0.count > 2 }
        let RightWords = Right.split(separator: " ").filter { $0.count > 2 }
        guard !LeftWords.isEmpty, !RightWords.isEmpty else { return 0 }
        return Double(LeftWords.filter { Word in RightWords.contains { $0.contains(Word) || Word.contains($0) } }.count)
            / Double(max(LeftWords.count, RightWords.count))
    }
}
