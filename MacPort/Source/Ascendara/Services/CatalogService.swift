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
        case .HTTP(401), .HTTP(403): return "The catalogue server refused access. Use the bundled index or import an ascendara_games.json file."
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
    private let LocalRefresh: LocalRefreshService
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
        self.LocalRefresh = LocalRefreshService(Directory: self.CacheDirectory, Session: Session)
    }

    func Load(Source: CatalogSource = .Community, Force: Bool = false) async throws -> CatalogSnapshot {
        if case .Community = Source { return try await LoadCommunity(Force: Force) }
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
            Request.setValue("AscendaraNative/" + AppVersion.Current, forHTTPHeaderField: "User-Agent")
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
            if case .Community = Source, let Bundled = try? ImportBundledIndex(),
               Cached == nil || Bundled.LoadedAt >= Cached!.Snapshot.LoadedAt {
                var Snapshot = Bundled
                Snapshot.Warning = "Using the bundled Ascendara game index because the online index could not be refreshed: \(error.localizedDescription)"
                return Snapshot
            }
            guard let Cached else { throw error }
            var Snapshot = Cached.Snapshot
            Snapshot.IsCached = true
            Snapshot.Warning = "Using the saved catalogue from \(Snapshot.LoadedAt.formatted(date: .abbreviated, time: .shortened)). \(error.localizedDescription)"
            return Snapshot
        }
    }

    private func LoadCommunity(Force: Bool) async throws -> CatalogSnapshot {
        do {
            let Result = try await LocalRefresh.Sync(Force: Force)
            var Snapshot = try Self.Decode(Data: Result.Data, Source: .Community,
                                           ArtworkDirectory: await LocalRefresh.ArtworkDirectory())
            Snapshot.LoadedAt = Result.RefreshedAt
            Snapshot.IsCached = !Result.Updated
            await LocalRefresh.Prefetch(Games: Snapshot.Games)
            return Snapshot
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            let Saved = try? await LocalRefresh.SavedIndex()
            let Bundled = try? ImportBundledIndex()
            if let Saved, Bundled == nil || Saved.RefreshedAt >= Bundled!.LoadedAt {
                var Snapshot = try Self.Decode(Data: Saved.Data, Source: .Community,
                                               ArtworkDirectory: await LocalRefresh.ArtworkDirectory())
                Snapshot.LoadedAt = Saved.RefreshedAt
                Snapshot.IsCached = true
                Snapshot.Warning = "Using the saved game index because the online index could not be refreshed: \(error.localizedDescription)"
                await LocalRefresh.Prefetch(Games: Snapshot.Games)
                return Snapshot
            }
            if var Bundled {
                Bundled.Warning = "Using the bundled Ascendara game index because the online index could not be refreshed: \(error.localizedDescription)"
                return Bundled
            }
            throw error
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

    func ImportBundledIndex() throws -> CatalogSnapshot {
        guard let File = Bundle.main.url(forResource: "ascendara_games", withExtension: "json") else {
            throw CatalogError.InvalidCatalog("This build does not contain a bundled index. Import an ascendara_games.json file in External sources.")
        }
        var Snapshot = try Self.Decode(Data: Data(contentsOf: File), Source: .Community)
        guard !Snapshot.Games.isEmpty else { throw CatalogError.InvalidCatalog("The bundled index is empty.") }
        Snapshot.LoadedAt = Snapshot.Metadata.UpdatedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
            ?? (try? File.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
        Snapshot.Metadata.SourceName = "Bundled Ascendara index"
        return Snapshot
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


struct GameReview: Identifiable, Sendable {
    var Id: String
    var Username: String
    var Comments: String
    var Rating: Double
    var CreatedAt: String?
    var IsGuest: Bool
    var id: String { Id }
}

struct GameRating: Sendable {
    var Average: Double
    var Count: Int
    var Reviews: [GameReview]
}

actor RatingService {
    static let Shared = RatingService()
    private var Cached: [String: (Date, GameRating)] = [:]

    func Load(GameId: String, Force: Bool = false) async throws -> GameRating {
        if !Force, let Entry = Cached[GameId], Date().timeIntervalSince(Entry.0) < 1800 { return Entry.1 }
        let URL = URL(string: "https://api.ascendara.app/app/v2/gamerating")!.appendingPathComponent(GameId)
        let (Data, Response) = try await URLSession.shared.data(for: URLRequest(url: URL, timeoutInterval: 30))
        let Status = (Response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(Status) else { throw CatalogError.HTTP(Status) }
        let Rating = try Self.Decode(Data: Data)
        Cached[GameId] = (Date(), Rating)
        return Rating
    }

    static func Decode(Data: Data) throws -> GameRating {
        guard let Root = try JSONSerialization.jsonObject(with: Data) as? [String: Any], Root["rating"] != nil else { throw CatalogError.InvalidResponse }
        let Average = (Root["rating"] as? NSNumber)?.doubleValue ?? Double(Root["rating"] as? String ?? "") ?? 0
        let Count = (Root["ratingCount"] as? NSNumber)?.intValue ?? Int(Root["ratingCount"] as? String ?? "") ?? 0
        let Reviews = (Root["reviews"] as? [[String: Any]] ?? []).compactMap { Item -> GameReview? in
            guard let Comments = Item["comments"] as? String, !Comments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let Name = (Item["username"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let Account = Item["isAscendAccount"] as? Bool
            let IsGuest = Name.isEmpty || Account == false || (Account != true && Name.range(of: #"^Anonymous(?: \d+)?$"#, options: .regularExpression) != nil)
            let CreatedAt = Item["createdAt"] as? String
            let Id = (Item["id"] as? String) ?? CatalogText.StableId("\(Name):\(CreatedAt ?? ""):\(Comments)")
            let Value = (Item["rating"] as? NSNumber)?.doubleValue ?? Double(Item["rating"] as? String ?? "") ?? 0
            return GameReview(Id: Id, Username: IsGuest ? "Anonymous player" : Name, Comments: Comments, Rating: max(0, min(5, Value)), CreatedAt: CreatedAt, IsGuest: IsGuest)
        }.sorted { !$0.IsGuest && $1.IsGuest }
        return GameRating(Average: max(0, min(5, Average)), Count: max(0, Count), Reviews: Reviews)
    }
}


actor LocalRefreshService {
    struct Result: Sendable {
        let Data: Data
        let Updated: Bool
        let RefreshedAt: Date
    }

    private struct SyncState: Codable {
        var ETag: String?
        var ModificationTime: TimeInterval
    }

    private struct Progress: Codable {
        var status: String
        var phase: String
        var progress: Double
        var lastSuccessfulTimestamp: TimeInterval?
        var error: String?
    }

    private let Directory: URL
    private let Session: URLSession
    private var ActiveSync: Task<Result, Error>?
    private var PrefetchTask: Task<Void, Never>?
    private var MissingCovers: Set<String> = []

    private var IndexFile: URL { Directory.appendingPathComponent("ascendara_games.json") }
    private var StateFile: URL { Directory.appendingPathComponent("sync.json") }
    private var ProgressFile: URL { Directory.appendingPathComponent("progress.json") }
    private var ImagesDirectory: URL { Directory.appendingPathComponent("imgs", isDirectory: true) }

    init(Directory: URL, Session: URLSession) {
        self.Directory = Directory
        self.Session = Session
    }

    func Sync(Force: Bool) async throws -> Result {
        if let ActiveSync { return try await ActiveSync.value }
        let Task = Task { try await PerformSync(Force: Force) }
        ActiveSync = Task
        defer { ActiveSync = nil }
        return try await Task.value
    }

    func SavedIndex() throws -> Result? {
        guard FileManager.default.fileExists(atPath: IndexFile.path) else { return nil }
        let Data = try Data(contentsOf: IndexFile)
        _ = try Self.Validate(Data)
        let Date = try ModificationDate(of: IndexFile)
        return Result(Data: Data, Updated: false, RefreshedAt: Date)
    }

    func ArtworkDirectory() -> URL { ImagesDirectory }

    func Prefetch(Games: [Game]) {
        guard PrefetchTask == nil else { return }
        let Popular = Games.sorted { ($0.Weight ?? 0) > ($1.Weight ?? 0) }.prefix(24)
        var Seen: Set<String> = []
        let IDs = Popular.compactMap(\.ImageId).filter {
            Self.ValidImageID($0) && Seen.insert($0).inserted && !MissingCovers.contains($0)
        }
        let Directory = ImagesDirectory
        let Session = Session
        PrefetchTask = Task {
            await withTaskGroup(of: String?.self) { Group in
                var Iterator = IDs.makeIterator()
                for _ in 0..<min(2, IDs.count) {
                    if let ID = Iterator.next() {
                        Group.addTask { await Self.DownloadCover(ID: ID, Directory: Directory, Session: Session) }
                    }
                }
                while let Missing = await Group.next() {
                    if let Missing { MissingCovers.insert(Missing) }
                    if let ID = Iterator.next() {
                        Group.addTask { await Self.DownloadCover(ID: ID, Directory: Directory, Session: Session) }
                    }
                }
            }
            PrefetchTask = nil
        }
    }

    private func PerformSync(Force: Bool) async throws -> Result {
        try FileManager.default.createDirectory(at: Directory, withIntermediateDirectories: true)
        let Previous = (try? SavedIndex())
        let State = try? ReadState()
        let Untouched = State.flatMap { Saved -> Bool? in
            guard let Modified = try? ModificationDate(of: IndexFile) else { return false }
            return abs(Modified.timeIntervalSince1970 - Saved.ModificationTime) < 0.01
        } ?? false
        WriteProgress(status: "running", phase: "downloading", progress: 0,
                      lastSuccessfulTimestamp: Previous?.RefreshedAt.timeIntervalSince1970)
        do {
            var Request = URLRequest(url: URL(string: "https://api.ascendara.app/json/v2/games")!,
                                     cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
            Request.setValue("application/json", forHTTPHeaderField: "Accept")
            Request.setValue("AscendaraNative/" + AppVersion.Current, forHTTPHeaderField: "User-Agent")
            if !Force, Untouched, Previous != nil, let ETag = State?.ETag {
                Request.setValue(ETag, forHTTPHeaderField: "If-None-Match")
            }
            let (Data, Response) = try await Session.data(for: Request)
            try Task.checkCancellation()
            guard let HTTP = Response as? HTTPURLResponse else { throw CatalogError.InvalidResponse }
            if HTTP.statusCode == 304, let Previous {
                WriteProgress(status: "completed", phase: "done", progress: 1,
                              lastSuccessfulTimestamp: Date().timeIntervalSince1970)
                return Previous
            }
            guard (200..<300).contains(HTTP.statusCode) else { throw CatalogError.HTTP(HTTP.statusCode) }
            let Games = try Self.Validate(Data)
            if !Force, !Untouched, let Previous,
               let Published = Self.PublishedDate(Data), Published <= Previous.RefreshedAt {
                WriteProgress(status: "completed", phase: "done", progress: 1,
                              lastSuccessfulTimestamp: Date().timeIntervalSince1970)
                return Previous
            }
            WriteProgress(status: "running", phase: "saving", progress: 0.8,
                          lastSuccessfulTimestamp: Previous?.RefreshedAt.timeIntervalSince1970)
            try Data.write(to: IndexFile, options: .atomic)
            let Modified = try ModificationDate(of: IndexFile)
            try SaveState(SyncState(ETag: HTTP.value(forHTTPHeaderField: "ETag"),
                                    ModificationTime: Modified.timeIntervalSince1970))
            PruneCovers(Referenced: Set(Games.compactMap(\.ImageId)))
            WriteProgress(status: "completed", phase: "done", progress: 1,
                          lastSuccessfulTimestamp: Date().timeIntervalSince1970)
            return Result(Data: Data, Updated: true, RefreshedAt: Modified)
        } catch {
            WriteProgress(status: "failed", phase: "done", progress: 0,
                          lastSuccessfulTimestamp: Previous?.RefreshedAt.timeIntervalSince1970,
                          error: error.localizedDescription)
            throw error
        }
    }

    private static func Validate(_ Data: Data) throws -> [Game] {
        let Object = try JSONSerialization.jsonObject(with: Data)
        guard let Root = Object as? [String: Any], let RawGames = Root["games"] as? [[String: Any]], !RawGames.isEmpty else {
            throw CatalogError.InvalidCatalog("The published game list is missing or empty.")
        }
        let Snapshot = try CatalogService.Decode(Data: Data)
        guard !Snapshot.Games.isEmpty else { throw CatalogError.InvalidCatalog("The published game list contains no usable games.") }
        return Snapshot.Games
    }

    private static func PublishedDate(_ Data: Data) -> Date? {
        guard let Object = (try? JSONSerialization.jsonObject(with: Data)) as? [String: Any],
              let Metadata = Object["metadata"] as? [String: Any],
              let Text = Metadata["lastUpdated"] as? String else { return nil }
        return ISO8601DateFormatter().date(from: Text)
    }

    private func ReadState() throws -> SyncState {
        try JSONDecoder().decode(SyncState.self, from: Data(contentsOf: StateFile))
    }

    private func SaveState(_ State: SyncState) throws {
        try JSONEncoder().encode(State).write(to: StateFile, options: .atomic)
    }

    private func ModificationDate(of File: URL) throws -> Date {
        let Attributes = try FileManager.default.attributesOfItem(atPath: File.path)
        guard let Date = Attributes[.modificationDate] as? Date else { throw CatalogError.InvalidResponse }
        return Date
    }

    private func WriteProgress(status: String, phase: String, progress: Double,
                               lastSuccessfulTimestamp: TimeInterval?, error: String? = nil) {
        let Value = Progress(status: status, phase: phase, progress: progress,
                             lastSuccessfulTimestamp: lastSuccessfulTimestamp, error: error)
        if let Data = try? JSONEncoder().encode(Value) { try? Data.write(to: ProgressFile, options: .atomic) }
    }

    private func PruneCovers(Referenced: Set<String>) {
        guard let Files = try? FileManager.default.contentsOfDirectory(at: ImagesDirectory,
                                                                        includingPropertiesForKeys: nil) else { return }
        for File in Files where !Referenced.contains(File.deletingPathExtension().lastPathComponent) {
            try? FileManager.default.removeItem(at: File)
        }
        MissingCovers.removeAll()
    }

    private static func ValidImageID(_ ID: String) -> Bool {
        ID.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil
    }

    private static func DownloadCover(ID: String, Directory: URL, Session: URLSession) async -> String? {
        let Destination = Directory.appendingPathComponent("\(ID).jpg")
        if FileManager.default.fileExists(atPath: Destination.path) { return nil }
        guard let URL = URL(string: "https://r2.ascendara.app/covers/\(ID).jpg") else { return ID }
        do {
            let (Data, Response) = try await Session.data(from: URL)
            guard let HTTP = Response as? HTTPURLResponse else { return nil }
            if HTTP.statusCode == 404 { return ID }
            guard HTTP.statusCode == 200, !Data.isEmpty, Data.count <= 8_000_000,
                  HTTP.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("image/") == true else { return nil }
            try FileManager.default.createDirectory(at: Directory, withIntermediateDirectories: true)
            try Data.write(to: Destination, options: .atomic)
            return nil
        } catch { return nil }
    }
}
