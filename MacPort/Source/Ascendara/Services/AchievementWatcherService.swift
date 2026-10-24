import Foundation

struct AchievementUnlock: Sendable {
    let GameId: UUID
    let GameName: String
    let AchievementName: String
}

/// Swift port of the original Achievement Watcher's monitor, Steam schema,
/// tracker, and per-game achievement output. Call Scan while games are running.
actor AchievementWatcherService {
    private struct Entry {
        var Name: String
        var Achieved: Bool
        var UnlockTime: TimeInterval
        var CRC: String?
    }

    private struct SchemaEntry {
        var Name: String
        var DisplayName: String
        var Description: String
        var Icon: String?
    }

    private let StorageDirectory: URL
    private let Session: URLSession
    private var WatchedFiles: [UUID: [URL]] = [:]
    private var LastDiscovery: [UUID: Date] = [:]
    private var ModifiedFiles: [String: Date] = [:]
    private var IsScanning = false

    private static let Filenames: Set<String> = [
        "achievements.ini", "achievements.json", "achiev.ini", "stats.ini",
        "achievements.bin", "achieve.dat", "stats.bin"
    ]

    init(StorageDirectory: URL = RuntimePaths.Support.appendingPathComponent("AchievementWatcher", isDirectory: true),
         Session: URLSession = .shared) {
        self.StorageDirectory = StorageDirectory
        self.Session = Session
    }

    func Scan(Games: [LibraryGame], Catalog: [Game], RunningIds: Set<UUID>) async -> [AchievementUnlock] {
        guard !IsScanning else { return [] }
        IsScanning = true
        defer { IsScanning = false }
        var Unlocked: [AchievementUnlock] = []
        let CatalogById = Dictionary(Catalog.map { ($0.Id, $0) }, uniquingKeysWith: { First, _ in First })
        for Game in Games where RunningIds.contains(Game.Id) {
            if LastDiscovery[Game.Id].map({ Date().timeIntervalSince($0) > 60 }) ?? true {
                WatchedFiles[Game.Id] = Self.DiscoverFiles(for: Game)
                LastDiscovery[Game.Id] = Date()
            }
            for File in WatchedFiles[Game.Id] ?? [] {
                guard let Modified = try? File.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      Modified > (ModifiedFiles[File.path] ?? .distantPast) else { continue }
                // A writer may still be replacing the file. Retry on the next scan
                // instead of treating an incomplete write as empty achievements.
                guard let Entries = try? Self.Parse(File: File), !Entries.isEmpty else { continue }
                let AppId = Self.SteamAppId(for: Game, Catalog: Game.CatalogId.flatMap { CatalogById[$0] }, File: File)
                let Schema: [SchemaEntry]
                if let AppId { Schema = (try? await LoadSchema(AppId: AppId)) ?? [] }
                else { Schema = [] }
                // stats.bin stores CRCs only. Keep retrying until a Steam
                // schema is available to resolve them to achievement names.
                if Schema.isEmpty && Entries.allSatisfy({ $0.Name.isEmpty }) { continue }
                let New = (try? Self.Save(Entries: Entries, Schema: Schema, Game: Game)) ?? []
                Unlocked += New.map { AchievementUnlock(GameId: Game.Id, GameName: Game.Name, AchievementName: $0) }
                ModifiedFiles[File.path] = Modified
            }
        }
        return Unlocked
    }

    private func LoadSchema(AppId: String) async throws -> [SchemaEntry] {
        guard AppId.range(of: "^[0-9]{2,12}$", options: .regularExpression) != nil else { return [] }
        let Cache = StorageDirectory.appendingPathComponent("steam_cache/schema/english/\(AppId).json")
        if let Age = try? Cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           Date().timeIntervalSince(Age) < 180 * 86400,
           let Data = try? Data(contentsOf: Cache), let Cached = Self.DecodeSchema(Data) { return Cached }
        var Components = URLComponents(string: "https://api.ascendara.app/api/proxy/steam/achievements")!
        Components.queryItems = [URLQueryItem(name: "appid", value: AppId), URLQueryItem(name: "lang", value: "english")]
        var Request = URLRequest(url: Components.url!, timeoutInterval: 20)
        Request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (Data, Response) = try await Session.data(for: Request)
            guard let HTTP = Response as? HTTPURLResponse, HTTP.statusCode == 200,
                  let Schema = Self.DecodeSchema(Data), !Schema.isEmpty else { return [] }
            try? FileManager.default.createDirectory(at: Cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data.write(to: Cache, options: .atomic)
            return Schema
        } catch {
            if let Data = try? Data(contentsOf: Cache), let Cached = Self.DecodeSchema(Data) { return Cached }
            throw error
        }
    }

    private static func DecodeSchema(_ Data: Data) -> [SchemaEntry]? {
        guard let Root = (try? JSONSerialization.jsonObject(with: Data)) as? [String: Any] else { return nil }
        let Game = Root["game"] as? [String: Any] ?? Root
        let Stats = Game["availableGameStats"] as? [String: Any]
        let Records = Stats?["achievements"] as? [[String: Any]]
            ?? (Game["achievement"] as? [String: Any])?["list"] as? [[String: Any]]
            ?? []
        return Records.compactMap { Row in
            guard let Name = Row["name"] as? String, !Name.isEmpty else { return nil }
            return SchemaEntry(Name: Name, DisplayName: Row["displayName"] as? String ?? Name,
                               Description: Row["description"] as? String ?? "",
                               Icon: Row["icon"] as? String)
        }
    }

    private static func Save(Entries: [Entry], Schema: [SchemaEntry], Game: LibraryGame) throws -> [String] {
        let Output = Game.DirectoryURL.appendingPathComponent("achievements.ascendara.json")
        let PreviousRoot = (try? JSONSerialization.jsonObject(with: Data(contentsOf: Output))) as? [String: Any]
        let Previous = PreviousRoot?["achievements"] as? [[String: Any]] ?? []
        let PreviousById = Dictionary(Previous.compactMap { Row -> (String, [String: Any])? in
            guard let Id = Row["achID"] as? String else { return nil }
            return (Id, Row)
        }, uniquingKeysWith: { First, _ in First })
        let EntryByName = Dictionary(Entries.filter { !$0.Name.isEmpty }.map { ($0.Name.lowercased(), $0) }, uniquingKeysWith: { First, _ in First })
        let EntryByCRC = Dictionary(Entries.compactMap { Entry -> (String, Entry)? in
            guard let CRC = Entry.CRC else { return nil }
            return (CRC.lowercased(), Entry)
        }, uniquingKeysWith: { First, _ in First })
        let Definitions = Schema.isEmpty
            ? Entries.filter { !$0.Name.isEmpty }.map { SchemaEntry(Name: $0.Name, DisplayName: $0.Name, Description: "", Icon: nil) }
            : Schema
        var Rows: [[String: Any]] = []
        var Unlocks: [String] = []
        for Definition in Definitions {
            let Match = EntryByName[Definition.Name.lowercased()] ?? EntryByCRC[String(format: "%08x", CRC32(Definition.Name))]
            let Old = PreviousById[Definition.Name]
            let OldAchieved = Old?["achieved"] as? Bool ?? false
            let Achieved = OldAchieved || Match?.Achieved == true
            let OldTime = (Old?["unlockTime"] as? String).flatMap(TimeInterval.init) ?? 0
            let Time = OldTime > 0 ? OldTime : (Match?.UnlockTime ?? 0)
            var Row: [String: Any] = ["message": Definition.DisplayName, "achieved": Achieved,
                                      "achID": Definition.Name, "description": Definition.Description]
            Row["icon"] = Definition.Icon ?? NSNull()
            Row["unlockTime"] = Achieved && Time > 0 ? String(Int(Time)) : NSNull()
            Rows.append(Row)
            if !Previous.isEmpty && !OldAchieved && Match?.Achieved == true { Unlocks.append(Definition.DisplayName) }
        }
        guard !Rows.isEmpty else { return [] }
        let Document: [String: Any] = ["achievements": Rows,
                                       "lastUpdated": ISO8601DateFormatter().string(from: Date())]
        let Data = try JSONSerialization.data(withJSONObject: Document, options: [.prettyPrinted, .sortedKeys])
        try Data.write(to: Output, options: .atomic)
        return Unlocks
    }

    private static func DiscoverFiles(for Game: LibraryGame) -> [URL] {
        var Roots = [Game.DirectoryURL]
        if let Prefix = Game.WinePrefixPath, !Prefix.isEmpty { Roots.append(URL(fileURLWithPath: Prefix, isDirectory: true)) }
        let Legacy = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ascendara/compatdata")
        if FileManager.default.fileExists(atPath: Legacy.path) { Roots.append(Legacy) }
        let Highball = RuntimePaths.Support.appendingPathComponent("Highball/bottles/\(Game.HighballBottle)")
        if FileManager.default.fileExists(atPath: Highball.path) { Roots.append(Highball) }
        var Queue = Roots.map { ($0, 0) }
        var Seen: Set<String> = []
        var Result: [URL] = []
        var Visited = 0
        while !Queue.isEmpty && Visited < 6000 && Result.count < 100 {
            let (Directory, Depth) = Queue.removeFirst()
            guard Seen.insert(Directory.standardizedFileURL.path).inserted,
                  let Children = try? FileManager.default.contentsOfDirectory(at: Directory,
                                    includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for Child in Children {
                Visited += 1
                if Self.Filenames.contains(Child.lastPathComponent.lowercased()) {
                    Result.append(Child)
                } else if Depth < 6 && ((try? Child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true) {
                    Queue.append((Child, Depth + 1))
                }
            }
        }
        return Result
    }

    private static func SteamAppId(for Game: LibraryGame, Catalog: Game?, File: URL) -> String? {
        if let Id = Catalog?.SteamId, Id.range(of: "^[0-9]+$", options: .regularExpression) != nil { return Id }
        let SteamIdFile = Game.DirectoryURL.appendingPathComponent("steam_appid.txt")
        if let Text = try? String(contentsOf: SteamIdFile, encoding: .utf8) {
            let Id = Text.trimmingCharacters(in: .whitespacesAndNewlines)
            if Id.range(of: "^[0-9]+$", options: .regularExpression) != nil { return Id }
        }
        for Config in ["ALI213.ini", "valve.ini", "hlm.ini", "ds.ini", "steam_api.ini", "SteamConfig.ini"] {
            let URL = Game.DirectoryURL.appendingPathComponent(Config)
            guard let Text = try? String(contentsOf: URL, encoding: .utf8) else { continue }
            if let Match = FirstMatch(#"(?im)^\s*(?:AppID|AppId)\s*=\s*([0-9]+)\s*$"#, in: Text) { return Match }
        }
        return File.deletingLastPathComponent().pathComponents.reversed().first {
            $0.range(of: "^[0-9]{3,10}$", options: .regularExpression) != nil
        }
    }

    private static func Parse(File: URL) throws -> [Entry] {
        let Data = try Data(contentsOf: File)
        switch File.pathExtension.lowercased() {
        case "json": return ParseJSON(Data)
        case "bin": return ParseStatsBin(Data)
        default: return ParseINI(String(decoding: Data, as: UTF8.self))
        }
    }

    private static func ParseJSON(_ Data: Data) -> [Entry] {
        guard let Root = (try? JSONSerialization.jsonObject(with: Data)) as? [String: Any] else { return [] }
        let Values = Root["ACHIEVE_DATA"] as? [String: Any] ?? Root["Achievements"] as? [String: Any] ?? Root
        let Times = Root["AchievementsUnlockTimes"] as? [String: Any] ?? [:]
        return Values.compactMap { Name, Value -> Entry? in
            if ["SteamAchievements", "Steam64", "Steam"].contains(Name) { return nil }
            let Detail = Value as? [String: Any] ?? [:]
            let State = (Detail["State"] as? String).flatMap(HexUInt32)
            let Achieved = Flag(Value) || State == 1 || ["Achieved", "achieved", "State", "HaveAchieved", "Unlocked", "earned"].contains { Flag(Detail[$0]) }
            let RawTime = Detail["Time"] as? String
            let TimeSource: Any? = State != nil ? RawTime.flatMap(HexUInt32) : Detail["Time"]
            let Time = Timestamp(Detail["UnlockTime"] ?? Detail["unlocktime"]
                                 ?? TimeSource
                                 ?? Detail["earned_time"] ?? Times[Name])
            return Entry(Name: Detail["id"] as? String ?? Detail["apiname"] as? String ?? Detail["name"] as? String ?? Name,
                         Achieved: Achieved, UnlockTime: Achieved ? (Time > 0 ? Time : Date().timeIntervalSince1970) : 0,
                         CRC: Detail["crc"] as? String)
        }
    }

    private static func ParseINI(_ Text: String) -> [Entry] {
        var Sections: [String: [String: String]] = [:]
        var Current = ""
        for Raw in Text.components(separatedBy: .newlines) {
            let Line = Raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if Line.isEmpty || Line.hasPrefix(";") || Line.hasPrefix("#") { continue }
            if Line.hasPrefix("["), Line.hasSuffix("]") {
                Current = String(Line.dropFirst().dropLast())
            } else if let Separator = Line.firstIndex(of: "=") {
                let Key = String(Line[..<Separator]).trimmingCharacters(in: .whitespacesAndNewlines)
                let Value = String(Line[Line.index(after: Separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                Sections[Current, default: [:]][Key] = Value
            }
        }
        let Values = Sections["ACHIEVE_DATA"] ?? Sections["Achievements"] ?? Sections[""] ?? [:]
        let Times = Sections["AchievementsUnlockTimes"] ?? [:]
        var Entries = Values.map { Name, Value in
            Entry(Name: Name, Achieved: Flag(Value), UnlockTime: Timestamp(Times[Name]), CRC: nil)
        }
        for (Name, Detail) in Sections where !["", "ACHIEVE_DATA", "Achievements", "AchievementsUnlockTimes"].contains(Name) {
            let Achieved = Flag(Detail["Achieved"] ?? Detail["achieved"] ?? Detail["State"] ?? Detail["Unlocked"])
                || Detail["State"].flatMap(HexUInt32) == 1
            if Detail.keys.contains(where: { ["Achieved", "achieved", "State", "Unlocked"].contains($0) }) {
                Entries.append(Entry(Name: Detail["id"] ?? Detail["apiname"] ?? Name,
                                     Achieved: Achieved,
                                     UnlockTime: Timestamp(Detail["UnlockTime"] ?? Detail["unlocktime"]
                                                           ?? Detail["Time"].flatMap(HexUInt32)
                                                           ?? Detail["Time"]), CRC: nil))
            }
        }
        return Entries.filter { !$0.Name.isEmpty }.map { Entry in
            var Entry = Entry
            if Entry.Achieved && Entry.UnlockTime == 0 { Entry.UnlockTime = Date().timeIntervalSince1970 }
            return Entry
        }
    }

    private static func ParseStatsBin(_ Data: Data) -> [Entry] {
        let Bytes = [UInt8](Data)
        guard Bytes.count >= 4 else { return [] }
        let Count = UInt32(Bytes[0]) | UInt32(Bytes[1]) << 8 | UInt32(Bytes[2]) << 16 | UInt32(Bytes[3]) << 24
        guard Count <= 100_000, Bytes.count == 4 + Int(Count) * 24 else { return [] }
        var Entries: [Entry] = []
        for Index in 0..<Int(Count) {
            let Start = 4 + Index * 24
            guard Bytes[Start + 20] == 1 else { continue }
            let CRC = UInt32(Bytes[Start]) | UInt32(Bytes[Start + 1]) << 8 | UInt32(Bytes[Start + 2]) << 16 | UInt32(Bytes[Start + 3]) << 24
            let Time = UInt32(Bytes[Start + 8]) | UInt32(Bytes[Start + 9]) << 8 | UInt32(Bytes[Start + 10]) << 16 | UInt32(Bytes[Start + 11]) << 24
            Entries.append(Entry(Name: "", Achieved: true,
                                 UnlockTime: Timestamp(TimeInterval(Time)), CRC: String(format: "%08x", CRC)))
        }
        return Entries
    }

    private static func Flag(_ Value: Any?) -> Bool {
        if let Bool = Value as? Bool { return Bool }
        if let Number = Value as? NSNumber { return Number.intValue == 1 }
        if let Text = Value as? String { return ["1", "true", "yes", "0101"].contains(Text.lowercased()) }
        return false
    }

    private static func Timestamp(_ Value: Any?) -> TimeInterval {
        let Raw: TimeInterval
        if let Number = Value as? NSNumber { Raw = Number.doubleValue }
        else if let Text = Value as? String { Raw = Double(Text) ?? 0 }
        else { return 0 }
        let Seconds = Raw > 1_000_000_000_000 ? Raw / 1000 : Raw
        return Seconds >= 946_684_800 ? Seconds : 0
    }

    private static func HexUInt32(_ Text: String) -> UInt32? {
        guard Text.count == 8 else { return nil }
        var Bytes: [UInt8] = []
        var Position = Text.startIndex
        for _ in 0..<4 {
            let End = Text.index(Position, offsetBy: 2)
            guard let Byte = UInt8(Text[Position..<End], radix: 16) else { return nil }
            Bytes.append(Byte)
            Position = End
        }
        return UInt32(Bytes[0]) | UInt32(Bytes[1]) << 8 | UInt32(Bytes[2]) << 16 | UInt32(Bytes[3]) << 24
    }

    private static func FirstMatch(_ Pattern: String, in Text: String) -> String? {
        guard let Regex = try? NSRegularExpression(pattern: Pattern),
              let Match = Regex.firstMatch(in: Text, range: NSRange(Text.startIndex..., in: Text)),
              let Range = Range(Match.range(at: 1), in: Text) else { return nil }
        return String(Text[Range])
    }

    private static func CRC32(_ Text: String) -> UInt32 {
        var CRC: UInt32 = 0xffffffff
        for Byte in Text.utf8 {
            CRC ^= UInt32(Byte)
            for _ in 0..<8 { CRC = CRC & 1 == 1 ? 0xedb88320 ^ (CRC >> 1) : CRC >> 1 }
        }
        return CRC ^ 0xffffffff
    }
}
