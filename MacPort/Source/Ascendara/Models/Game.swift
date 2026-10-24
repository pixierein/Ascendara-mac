import Foundation

struct Game: Codable, Identifiable, Hashable, Sendable {
    var Id: String
    var Name: String
    var ImageId: String?
    var Categories: [String]
    var Version: String?
    var Size: String?
    var Online: Bool
    var Dlc: Bool
    var Description: String?
    var MinimumRequirements: String?
    var ReleasedBy: String?
    var LatestUpdate: String?
    var DownloadLinks: [String: [String]]
    var Weight: Double?
    var HasHistory: Bool
    var SteamId: String?
    var SourceURL: URL?
    var CustomSource: String?
    var LocalArtworkURL: URL?

    var id: String { Id }
    var ArtworkURL: URL? {
        if let LocalArtworkURL, FileManager.default.fileExists(atPath: LocalArtworkURL.path) {
            return LocalArtworkURL
        }
        guard let ImageId, (1...64).contains(ImageId.utf8.count),
              ImageId.utf8.allSatisfy({ Byte in
                  (65...90).contains(Byte) || (97...122).contains(Byte) ||
                  (48...57).contains(Byte) || Byte == 95 || Byte == 45
              }) else { return nil }
        return URL(string: "https://r2.ascendara.app/covers/\(ImageId).jpg")
    }
    var SizeGB: Double {
        guard let Size else { return 0 }
        let Number = Size.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber || $0 == "." }
        guard let Value = Double(Number) else { return 0 }
        let Unit = Size.uppercased()
        if Unit.contains("TB") { return Value * 1024 }
        if Unit.contains("MB") { return Value / 1024 }
        return Unit.contains("GB") ? Value : 0
    }

    init(Id: String, Name: String, ImageId: String? = nil, Categories: [String] = [], Version: String? = nil,
         Size: String? = nil, Online: Bool = false, Dlc: Bool = false, Description: String? = nil,
         MinimumRequirements: String? = nil, ReleasedBy: String? = nil, LatestUpdate: String? = nil,
         DownloadLinks: [String: [String]] = [:], Weight: Double? = nil, HasHistory: Bool = false,
         SteamId: String? = nil, SourceURL: URL? = nil, CustomSource: String? = nil, LocalArtworkURL: URL? = nil) {
        self.Id = Id; self.Name = Name; self.ImageId = ImageId; self.Categories = Categories
        self.Version = Version; self.Size = Size; self.Online = Online; self.Dlc = Dlc
        self.Description = Description; self.MinimumRequirements = MinimumRequirements
        self.ReleasedBy = ReleasedBy; self.LatestUpdate = LatestUpdate; self.DownloadLinks = DownloadLinks
        self.Weight = Weight; self.HasHistory = HasHistory; self.SteamId = SteamId; self.SourceURL = SourceURL
        self.CustomSource = CustomSource; self.LocalArtworkURL = LocalArtworkURL
    }

    enum CodingKeys: String, CodingKey {
        case Id = "gameID", Name = "game", AlternateName = "name", Title = "title"
        case ImageId = "imgID", Categories = "category", Version = "version", Size = "size"
        case Online = "online", Dlc = "dlc", Description = "description", MinimumRequirements = "minReqs"
        case ReleasedBy = "releasedBy", LatestUpdate = "latest_update", DownloadLinks = "download_links"
        case Weight = "weight", HasHistory = "hasHistory", SteamId = "steamID", AlternateSteamId = "appid"
        case SourceURL = "dirlink", CustomSource = "customSource", LocalArtworkURL = "native_artwork"
    }

    init(from Decoder: Decoder) throws {
        let Values = try Decoder.container(keyedBy: CodingKeys.self)
        Name = CatalogText.Clean(Values.Text(.Name) ?? Values.Text(.AlternateName) ?? Values.Text(.Title) ?? "")
        guard !Name.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .Name, in: Values, debugDescription: "The game is missing its title.")
        }
        Id = Values.Text(.Id) ?? CatalogText.StableId(Name)
        ImageId = Values.Text(.ImageId)
        Categories = (try? Values.decode([String].self, forKey: .Categories)) ?? Values.Text(.Categories).map { [$0] } ?? []
        Version = Values.Text(.Version); Size = Values.Text(.Size)
        Online = Values.Flag(.Online); Dlc = Values.Flag(.Dlc)
        Description = Values.Text(.Description).map(CatalogText.Clean)
        if let Requirements = try? Values.decode([String: String].self, forKey: .MinimumRequirements) {
            let Order = ["os", "cpu", "ram", "gpu", "directx", "storage"]
            let Keys = Order.filter { Requirements[$0] != nil } + Requirements.keys.filter { !Order.contains($0) }.sorted()
            MinimumRequirements = Keys.map { "\($0.uppercased()): \(Requirements[$0] ?? "")" }.joined(separator: "\n")
        } else { MinimumRequirements = Values.Text(.MinimumRequirements) }
        ReleasedBy = Values.Text(.ReleasedBy); LatestUpdate = Values.Text(.LatestUpdate)
        DownloadLinks = (try? Values.decode([String: [String]].self, forKey: .DownloadLinks)) ?? [:]
        if DownloadLinks.isEmpty, let Links = try? Values.decode([String: String].self, forKey: .DownloadLinks) {
            DownloadLinks = Links.mapValues { [$0] }
        }
        Weight = Values.Text(.Weight).flatMap(Double.init)
        HasHistory = Values.Flag(.HasHistory)
        SteamId = Values.Text(.SteamId) ?? Values.Text(.AlternateSteamId)
        SourceURL = Values.Text(.SourceURL).flatMap(URL.init(string:))
        CustomSource = Values.Text(.CustomSource)
        LocalArtworkURL = Values.Text(.LocalArtworkURL).flatMap(URL.init(string:))
    }

    func encode(to Encoder: Encoder) throws {
        var Values = Encoder.container(keyedBy: CodingKeys.self)
        try Values.encode(Id, forKey: .Id); try Values.encode(Name, forKey: .Name)
        try Values.encodeIfPresent(ImageId, forKey: .ImageId); try Values.encode(Categories, forKey: .Categories)
        try Values.encodeIfPresent(Version, forKey: .Version); try Values.encodeIfPresent(Size, forKey: .Size)
        try Values.encode(Online, forKey: .Online); try Values.encode(Dlc, forKey: .Dlc)
        try Values.encodeIfPresent(Description, forKey: .Description)
        try Values.encodeIfPresent(MinimumRequirements, forKey: .MinimumRequirements)
        try Values.encodeIfPresent(ReleasedBy, forKey: .ReleasedBy); try Values.encodeIfPresent(LatestUpdate, forKey: .LatestUpdate)
        try Values.encode(DownloadLinks, forKey: .DownloadLinks); try Values.encodeIfPresent(Weight, forKey: .Weight)
        try Values.encode(HasHistory, forKey: .HasHistory); try Values.encodeIfPresent(SteamId, forKey: .SteamId)
        try Values.encodeIfPresent(SourceURL, forKey: .SourceURL); try Values.encodeIfPresent(CustomSource, forKey: .CustomSource)
        try Values.encodeIfPresent(LocalArtworkURL, forKey: .LocalArtworkURL)
    }
}

extension KeyedDecodingContainer {
    func Text(_ Key: Key) -> String? {
        if let Value = try? decode(String.self, forKey: Key) { return Value }
        if let Value = try? decode(Int.self, forKey: Key) { return String(Value) }
        if let Value = try? decode(Double.self, forKey: Key) { return String(Value) }
        return nil
    }
    func Flag(_ Key: Key) -> Bool {
        if let Value = try? decode(Bool.self, forKey: Key) { return Value }
        return ["true", "1", "yes"].contains(Text(Key)?.lowercased() ?? "")
    }
}

enum CatalogText {
    static func Clean(_ Text: String) -> String {
        var Result = Text.replacingOccurrences(of: "<br\\s*/?>|</p>|</li>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (Entity, Character) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            Result = Result.replacingOccurrences(of: Entity, with: Character)
        }
        return Result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func StableId(_ Seed: String) -> String {
        let Characters = Array("ABCDEFGHJKMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz")
        var Hash: Int32 = 0
        for Character in Seed.utf16 { Hash = Hash &* 31 &+ Int32(Character) }
        var Number = abs(Int64(Hash))
        var Result = ""
        for Index in 0..<6 {
            Result = String(Characters[Int(Number % Int64(Characters.count))]) + Result
            Number = Number / Int64(Characters.count) + Int64((Index + 1) * 2971)
        }
        return Result
    }
}
