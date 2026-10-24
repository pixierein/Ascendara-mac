import AppKit
import Combine
import CryptoKit
import Foundation

struct RetroPlatform: Decodable, Identifiable {
    let Id: String
    let Name: String
    let Adapter: String
    let Extensions: [String]
    var id: String { Id }
    enum CodingKeys: String, CodingKey { case Id = "id", Name = "name", Adapter = "adapter", Extensions = "extensions" }
}

struct RetroEmulatorPreset: Decodable, Identifiable {
    let Id: String
    let Name: String
    let Platforms: [String]
    let Website: String
    let Arguments: [String]?
    let FullscreenArguments: [String]?
    var id: String { Id }
    enum CodingKeys: String, CodingKey {
        case Id = "id", Name = "name", Platforms = "platforms", Website = "website", Arguments = "args", FullscreenArguments = "fullscreen"
    }
}

struct RetroProfile: Codable {
    var PlatformId: String
    var ExecutablePath = ""
    var Adapter = "custom"
    var CorePath = ""
    var Fullscreen = false
    var Arguments: [String] = []
    var Folders: [String] = []
}

struct RetroGame: Codable, Identifiable {
    var Id: UUID
    var Name: String
    var PlatformId: String
    var FilePaths: [String]
    var MissingDependencies: [String] = []
    var Favorite = false
    var PlayTimeSeconds: Double = 0
    var LastPlayedAt: Date?
    var id: UUID { Id }
    var IsInstalled: Bool { FilePaths.first.map { FileManager.default.fileExists(atPath: $0) } ?? false }
}

private struct RetroCatalog: Decodable {
    var Platforms: [RetroPlatform]
    var Emulators: [RetroEmulatorPreset]
    enum CodingKeys: String, CodingKey { case Platforms = "platforms", Emulators = "emulators" }
}

private struct RetroLibrary: Codable {
    var Games: [RetroGame] = []
    var Profiles: [String: RetroProfile] = [:]
}

@MainActor
final class RetroService: ObservableObject {
    static let Shared = RetroService()
    @Published private(set) var Games: [RetroGame] = []
    @Published private(set) var Profiles: [String: RetroProfile] = [:]
    @Published private(set) var RunningIds: Set<UUID> = []
    @Published private(set) var Scanning = false
    @Published private(set) var ErrorMessage: String?
    private(set) var Platforms: [RetroPlatform] = []
    private(set) var Emulators: [RetroEmulatorPreset] = []
    let StorageDirectory: URL
    private let Launcher = GameLauncher(Compatibility: CompatibilityService())
    private var Subscriptions: Set<AnyCancellable> = []
    private var LoadFailed = false

    init(StorageDirectory: URL = RuntimePaths.Support) {
        self.StorageDirectory = StorageDirectory
        Platforms = Self.BasePlatforms
        Emulators = Self.BaseEmulators
        do {
            if let Resource = AppResources.Bundle.url(forResource: "RetroCatalog", withExtension: "json") {
                let Catalog = try JSONDecoder().decode(RetroCatalog.self, from: Data(contentsOf: Resource))
                Platforms += Catalog.Platforms
                Emulators += Catalog.Emulators.filter { $0.Arguments != nil }
            }
            let Path = StorageDirectory.appendingPathComponent("retro-library.json")
            if FileManager.default.fileExists(atPath: Path.path) {
                let Library = try JSONDecoder().decode(RetroLibrary.self, from: Data(contentsOf: Path))
                Games = Library.Games
                Profiles = Library.Profiles
            }
        } catch { LoadFailed = true; ErrorMessage = error.localizedDescription }
        Platforms.sort { $0.Name.localizedStandardCompare($1.Name) == .orderedAscending }
        Launcher.$RunningIds.sink { [weak self] Ids in self?.RunningIds = Ids }.store(in: &Subscriptions)
        Launcher.$ErrorMessage.compactMap { $0 }.sink { [weak self] Error in self?.ErrorMessage = Error }.store(in: &Subscriptions)
        Launcher.OnSessionEnded = { [weak self] Id, Date, Seconds in
            guard let self, let Index = self.Games.firstIndex(where: { $0.Id == Id }) else { return }
            self.Games[Index].LastPlayedAt = Date
            self.Games[Index].PlayTimeSeconds += Seconds
            do { try self.Save() } catch { self.ErrorMessage = error.localizedDescription }
        }
    }

    func Profile(for Platform: RetroPlatform) -> RetroProfile {
        Profiles[Platform.Id] ?? RetroProfile(PlatformId: Platform.Id, Adapter: Platform.Adapter)
    }

    func SaveProfile(_ Profile: RetroProfile) throws {
        guard Platforms.contains(where: { $0.Id == Profile.PlatformId }) else { throw RuntimeError.Message("Unknown console.") }
        _ = try Self.CustomArguments(Profile.Arguments.joined(separator: "\n"))
        Profiles[Profile.PlatformId] = Profile
        try Save()
    }

    func ToggleFavorite(_ Game: RetroGame) throws {
        guard let Index = Games.firstIndex(where: { $0.Id == Game.Id }) else { return }
        Games[Index].Favorite.toggle()
        try Save()
    }

    func Remove(_ Game: RetroGame) throws {
        guard !RunningIds.contains(Game.Id) else { throw RuntimeError.Message("Stop this game before removing it.") }
        Games.removeAll { $0.Id == Game.Id }
        try Save()
    }

    @discardableResult
    func Scan(Platform: RetroPlatform, Folder: URL) async throws -> Int {
        guard !Scanning else { throw RuntimeError.Message("A ROM folder scan is already running.") }
        Scanning = true
        defer { Scanning = false }
        let Found = try await Task.detached(priority: .userInitiated) { try Self.ScanFiles(Platform: Platform, Folder: Folder) }.value
        for var Game in Found {
            if let Existing = Games.first(where: { $0.Id == Game.Id }) {
                Game.Favorite = Existing.Favorite
                Game.PlayTimeSeconds = Existing.PlayTimeSeconds
                Game.LastPlayedAt = Existing.LastPlayedAt
            }
            Games.removeAll { $0.Id == Game.Id }
            Games.append(Game)
        }
        Games.sort { $0.Name.localizedStandardCompare($1.Name) == .orderedAscending }
        var Profile = Profile(for: Platform)
        if !Profile.Folders.contains(Folder.path) { Profile.Folders.append(Folder.path) }
        Profiles[Platform.Id] = Profile
        try Save()
        return Found.count
    }

    func Launch(_ Game: RetroGame, FilePath: String? = nil) async throws {
        guard let Platform = Platforms.first(where: { $0.Id == Game.PlatformId }) else { throw RuntimeError.Message("Unknown console.") }
        let Profile = Profile(for: Platform)
        guard !Profile.ExecutablePath.isEmpty else { throw RuntimeError.Message("Choose an emulator in Console Setup first.") }
        guard let File = FilePath ?? Game.FilePaths.first, FileManager.default.fileExists(atPath: File) else { throw RuntimeError.Message("This ROM file is missing. Scan its folder again.") }
        guard Game.MissingDependencies.isEmpty else { throw RuntimeError.Message("This game is missing disc files:\n" + Game.MissingDependencies.joined(separator: "\n")) }
        let Arguments = try Self.LaunchArguments(Platform: Platform, Profile: Profile, File: File, Presets: Emulators)
        var Launch = LibraryGame(Id: Game.Id, Name: Game.Name, DirectoryPath: URL(fileURLWithPath: File).deletingLastPathComponent().path, ExecutablePath: Profile.ExecutablePath)
        Launch.LaunchArguments = Arguments
        try await Launcher.Launch(Launch)
    }

    func Stop(_ Game: RetroGame) async throws { try await Launcher.Stop(Game.Id) }

    func PrepareForExit() { Launcher.PrepareForExit() }

    private func Save() throws {
        guard !LoadFailed else { throw RuntimeError.Message("The Retro library could not be read. Its metadata has been preserved.") }
        try RuntimePaths.CreateDirectory(StorageDirectory)
        try JSONEncoder().encode(RetroLibrary(Games: Games, Profiles: Profiles)).write(to: StorageDirectory.appendingPathComponent("retro-library.json"), options: .atomic)
    }

    nonisolated static func CustomArguments(_ Text: String) throws -> [String] {
        guard Text.utf8.count <= 8192, !Text.contains("\0") else { throw RuntimeError.Message("Emulator arguments are too long or contain an invalid character.") }
        let Arguments = Text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard Arguments.count <= 64 else { throw RuntimeError.Message("Use at most 64 emulator arguments.") }
        return Arguments
    }

    nonisolated static func LaunchArguments(Platform: RetroPlatform, Profile: RetroProfile, File: String, Presets: [RetroEmulatorPreset]) throws -> [String] {
        if let Preset = Presets.first(where: { $0.Id == Profile.Adapter }), !Preset.Platforms.contains(Platform.Id) {
            throw RuntimeError.Message("This emulator preset does not support the selected console.")
        }
        if Profile.Adapter == "custom" {
            let Arguments = try CustomArguments(Profile.Arguments.joined(separator: "\n"))
            return Arguments.map { $0.replacingOccurrences(of: "{rom}", with: File) } + (Arguments.contains(where: { $0.contains("{rom}") }) ? [] : [File])
        }
        if let Preset = Presets.first(where: { $0.Id == Profile.Adapter }), let Arguments = Preset.Arguments {
            guard Preset.Platforms.contains(Platform.Id) else { throw RuntimeError.Message("This emulator preset does not support the selected console.") }
            return (Profile.Fullscreen ? Preset.FullscreenArguments ?? [] : []) + Arguments.map { $0.replacingOccurrences(of: "{rom}", with: File) }
        }
        switch Profile.Adapter {
        case "duckstation", "pcsx2": return ["-batch"] + (Profile.Fullscreen ? ["-fullscreen"] : []) + ["--", File]
        case "rpcs3": return ["--no-gui", File]
        case "ppsspp": return (Profile.Fullscreen ? ["--fullscreen"] : []) + [File]
        case "dolphin": return ["--batch"] + (Profile.Fullscreen ? ["--config", "Dolphin.Display.Fullscreen=True"] : []) + ["--exec", File]
        case "retroarch":
            guard !Profile.CorePath.isEmpty, FileManager.default.fileExists(atPath: Profile.CorePath) else { throw RuntimeError.Message("Select an installed RetroArch core for this console first.") }
            return (Profile.Fullscreen ? ["--fullscreen"] : []) + ["-L", Profile.CorePath, File]
        default: throw RuntimeError.Message("Choose an emulator preset or custom arguments.")
        }
    }

    nonisolated static func ScanFiles(Platform: RetroPlatform, Folder: URL) throws -> [RetroGame] {
        var IsDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: Folder.path, isDirectory: &IsDirectory), IsDirectory.boolValue else { throw RuntimeError.Message("The selected ROM folder does not exist.") }
        guard let Enumerator = FileManager.default.enumerator(at: Folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var Files: [URL] = []
        for case let File as URL in Enumerator {
            let Values = try File.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if Values.isSymbolicLink == true { Enumerator.skipDescendants(); continue }
            if File.pathComponents.count - Folder.pathComponents.count > 64 { Enumerator.skipDescendants(); continue }
            guard Values.isRegularFile == true else { continue }
            if Platform.Id == "ps3" {
                if File.lastPathComponent.uppercased() == "EBOOT.BIN", File.deletingLastPathComponent().lastPathComponent.uppercased() == "USRDIR" { Files.append(File) }
            } else if Platform.Extensions.contains(File.pathExtension.lowercased()) {
                if ["gamecube", "wii"].contains(Platform.Id), ["iso", "gcm"].contains(File.pathExtension.lowercased()) {
                    let Handle = try FileHandle(forReadingFrom: File)
                    let Header = try Handle.read(upToCount: 32) ?? Data()
                    try Handle.close()
                    if Header.count == 32 {
                        let Wii = Array(Header[24..<28]) == [0x5d, 0x1c, 0x9e, 0xa3]
                        let GameCube = Array(Header[28..<32]) == [0xc2, 0x33, 0x9f, 0x3d]
                        if Wii && Platform.Id != "wii" || GameCube && Platform.Id != "gamecube" { continue }
                    }
                }
                Files.append(File)
            }
        }
        var References: Set<String> = []
        var Missing: [String: [String]] = [:]
        var DependencyPaths: [String: [String]] = [:]
        for File in Files where ["cue", "m3u"].contains(File.pathExtension.lowercased()) {
            let Size = try File.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard Size <= 1024 * 1024 else { throw RuntimeError.Message("The disc descriptor exceeds 1 MB: \(File.lastPathComponent)") }
            let Text = try String(contentsOf: File, encoding: .utf8).replacingOccurrences(of: "\u{FEFF}", with: "")
            var Dependencies: [String] = []
            if File.pathExtension.lowercased() == "m3u" {
                Dependencies = Text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
            } else {
                let Pattern = try NSRegularExpression(pattern: #"^\s*FILE\s+(?:"([^"]+)"|(\S+))"#, options: [.caseInsensitive, .anchorsMatchLines])
                Dependencies = Pattern.matches(in: Text, range: NSRange(Text.startIndex..., in: Text)).compactMap { Match in
                    let Capture = Match.range(at: Match.range(at: 1).location == NSNotFound ? 2 : 1)
                    return Range(Capture, in: Text).map { String(Text[$0]) }
                }
            }
            for Dependency in Dependencies {
                let Resolved = File.deletingLastPathComponent().appendingPathComponent(Dependency).standardizedFileURL.path
                let Descriptor = File.standardizedFileURL.path
                References.insert(Resolved)
                DependencyPaths[Descriptor, default: []].append(Resolved)
                if !FileManager.default.fileExists(atPath: Resolved) { Missing[Descriptor, default: []].append(Resolved) }
            }
        }
        func MissingFiles(_ Path: String, Visited: Set<String> = []) -> [String] {
            guard !Visited.contains(Path) else { return [] }
            return (Missing[Path] ?? []) + (DependencyPaths[Path] ?? []).flatMap { MissingFiles($0, Visited: Visited.union([Path])) }
        }
        var Groups: [UUID: RetroGame] = [:]
        for File in Files where !References.contains(File.standardizedFileURL.path) {
            var Name = File.deletingPathExtension().lastPathComponent
            if Platform.Id == "ps3" {
                let Directory = File.deletingLastPathComponent().deletingLastPathComponent()
                Name = Directory.lastPathComponent.uppercased() == "PS3_GAME" ? Directory.deletingLastPathComponent().lastPathComponent : Directory.lastPathComponent
                if let SFO = try? Data(contentsOf: Directory.appendingPathComponent("PARAM.SFO")), let Title = ReadSFO(SFO)["TITLE"] { Name = Title }
            }
            let GroupName = Name.replacingOccurrences(of: #"\s*[\(\[](?:disc|disk|cd)\s*\d+(?:\s*of\s*\d+)?[\)\]]"#, with: "", options: [.regularExpression, .caseInsensitive])
            let Identity = Platform.Id + ":" + File.deletingLastPathComponent().resolvingSymlinksInPath().path + ":" + GroupName.lowercased()
            let Hash = Array(SHA256.hash(data: Data(Identity.utf8)))
            let Id = UUID(uuid: (Hash[0], Hash[1], Hash[2], Hash[3], Hash[4], Hash[5], Hash[6], Hash[7],
                                Hash[8], Hash[9], Hash[10], Hash[11], Hash[12], Hash[13], Hash[14], Hash[15]))
            let Title = GroupName.replacingOccurrences(of: #"\s*\[[^\]]*\]|\s*\((?:USA|Europe|Japan|World|Asia|En|Fr|De|Es|It|Rev\b|v\d)[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive]).trimmingCharacters(in: .whitespaces)
            if Groups[Id] == nil { Groups[Id] = RetroGame(Id: Id, Name: Title, PlatformId: Platform.Id, FilePaths: []) }
            Groups[Id]?.FilePaths.append(File.path)
            Groups[Id]?.MissingDependencies += MissingFiles(File.standardizedFileURL.path)
        }
        return Groups.values.map { Game in
            var Sorted = Game
            Sorted.FilePaths.sort { $0.localizedStandardCompare($1) == .orderedAscending }
            return Sorted
        }.sorted { $0.Name.localizedStandardCompare($1.Name) == .orderedAscending }
    }

    nonisolated static func ReadSFO(_ Data: Data) -> [String: String] {
        let Bytes = Array(Data)
        guard Bytes.count >= 20, Array(Bytes[0..<4]) == [0x00, 0x50, 0x53, 0x46] else { return [:] }
        func UInt16At(_ Offset: Int) -> Int { Int(Bytes[Offset]) | (Int(Bytes[Offset + 1]) << 8) }
        func UInt32At(_ Offset: Int) -> Int { UInt16At(Offset) | (UInt16At(Offset + 2) << 16) }
        let Keys = UInt32At(8)
        let Values = UInt32At(12)
        let Count = min(512, UInt32At(16))
        var Result: [String: String] = [:]
        for Index in 0..<Count {
            let Entry = 20 + Index * 16
            guard Entry + 16 <= Bytes.count else { break }
            let Key = Keys + UInt16At(Entry)
            let Value = Values + UInt32At(Entry + 12)
            let Size = UInt32At(Entry + 4)
            guard Key < Bytes.count, Value <= Bytes.count, Size <= Bytes.count - Value,
                  let End = Bytes[Key...].firstIndex(of: 0) else { continue }
            let Name = String(decoding: Bytes[Key..<End], as: UTF8.self)
            let Text = String(decoding: Bytes[Value..<(Value + Size)].prefix(while: { $0 != 0 }), as: UTF8.self)
            Result[Name] = Text
        }
        return Result
    }

    private static let BasePlatforms: [RetroPlatform] = [
        .init(Id: "ps1", Name: "PlayStation 1", Adapter: "duckstation", Extensions: ["cue", "chd", "iso", "img", "pbp", "m3u"]),
        .init(Id: "ps2", Name: "PlayStation 2", Adapter: "pcsx2", Extensions: ["iso", "chd", "cso", "gz", "bin"]),
        .init(Id: "ps3", Name: "PlayStation 3", Adapter: "rpcs3", Extensions: []),
        .init(Id: "psp", Name: "PlayStation Portable", Adapter: "ppsspp", Extensions: ["iso", "cso", "chd", "pbp"]),
        .init(Id: "gamecube", Name: "Nintendo GameCube", Adapter: "dolphin", Extensions: ["iso", "gcm", "rvz", "wia", "gcz", "ciso", "m3u"]),
        .init(Id: "wii", Name: "Nintendo Wii", Adapter: "dolphin", Extensions: ["iso", "wbfs", "rvz", "wia", "gcz", "ciso"]),
        .init(Id: "nes", Name: "Nintendo NES", Adapter: "retroarch", Extensions: ["nes", "fds", "unf", "unif", "zip", "7z"]),
        .init(Id: "snes", Name: "Super Nintendo", Adapter: "retroarch", Extensions: ["sfc", "smc", "zip", "7z"]),
        .init(Id: "n64", Name: "Nintendo 64", Adapter: "retroarch", Extensions: ["z64", "n64", "v64", "zip", "7z"]),
        .init(Id: "gb", Name: "Game Boy", Adapter: "retroarch", Extensions: ["gb", "zip", "7z"]),
        .init(Id: "gbc", Name: "Game Boy Color", Adapter: "retroarch", Extensions: ["gbc", "zip", "7z"]),
        .init(Id: "gba", Name: "Game Boy Advance", Adapter: "retroarch", Extensions: ["gba", "zip", "7z"])
    ]

    private static let BaseEmulators: [RetroEmulatorPreset] = [
        .init(Id: "duckstation", Name: "DuckStation", Platforms: ["ps1"], Website: "https://www.duckstation.org/", Arguments: nil, FullscreenArguments: nil),
        .init(Id: "pcsx2", Name: "PCSX2", Platforms: ["ps2"], Website: "https://pcsx2.net/", Arguments: nil, FullscreenArguments: nil),
        .init(Id: "rpcs3", Name: "RPCS3", Platforms: ["ps3"], Website: "https://rpcs3.net/", Arguments: nil, FullscreenArguments: nil),
        .init(Id: "ppsspp", Name: "PPSSPP", Platforms: ["psp"], Website: "https://www.ppsspp.org/", Arguments: nil, FullscreenArguments: nil),
        .init(Id: "dolphin", Name: "Dolphin", Platforms: ["gamecube", "wii"], Website: "https://dolphin-emu.org/", Arguments: nil, FullscreenArguments: nil),
        .init(Id: "retroarch", Name: "RetroArch", Platforms: ["nes", "snes", "n64", "gb", "gbc", "gba", "ps1", "psp", "genesis", "saturn", "pcengine", "dreamcast", "nds"], Website: "https://www.retroarch.com/", Arguments: nil, FullscreenArguments: nil)
    ]
}
