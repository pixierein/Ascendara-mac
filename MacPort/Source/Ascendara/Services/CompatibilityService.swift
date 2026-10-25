import Foundation
import Combine

@MainActor
final class CompatibilityService: ObservableObject {
    @Published private(set) var Status = CompatibilityStatus()
    @Published private(set) var SetupMessage: String?
    @Published private(set) var SetupProgress: Double?
    @Published private(set) var SetupDetail: String?
    var CustomWinePath: String?
    var CustomHighballPath: String?
    let HighballHome = RuntimePaths.Support.appendingPathComponent("Highball", isDirectory: true)
    private let LatestManifestAddress = URL(string: "https://raw.githubusercontent.com/gauthierpiarrette/highball/main/spike/engine-manifest.json")!
    private var PreparationTask: Task<String, Error>?
    private var LatestManifestFile: URL { HighballHome.appendingPathComponent("latest-engine-manifest.json") }

    private struct EngineDownload {
        let Name: String
        let Destination: URL
        let Partial: URL
        let ExpectedBytes: Int64
    }

    var Environment: [String: String] {
        var Environment = ProcessInfo.processInfo.environment
        Environment["HIGHBALL_HOME"] = HighballHome.path
        return Environment
    }

    func FindWine() -> URL? {
        FindExecutable([CustomWinePath,
            "/opt/homebrew/bin/wine64", "/opt/homebrew/bin/wine", "/usr/local/bin/wine64", "/usr/local/bin/wine",
            "/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine64",
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine64",
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine"])
    }

    func FindHighball() -> URL? {
        FindExecutable([CustomHighballPath,
            Bundle.main.resourceURL?.appendingPathComponent("Highball/highball").path,
            ProcessInfo.processInfo.environment["ASCENDARA_HIGHBALL_PATH"],
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("BuildTools/Highball/highball").path,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("MacPort/BuildTools/Highball/highball").path,
            "/opt/homebrew/bin/highball", "/usr/local/bin/highball"])
    }

    var DefaultManifestURL: URL? {
        if let Data = try? Data(contentsOf: LatestManifestFile), (try? ValidateManifest(Data)) != nil {
            return LatestManifestFile
        }
        return FindHighballResource("engine-manifest.json")
    }

    var DefaultEngineID: String? {
        guard let URL = DefaultManifestURL, let Data = try? Data(contentsOf: URL) else { return nil }
        return try? ValidateManifest(Data)
    }

    var IsHighballReady: Bool {
        Status.HighballAvailable && Status.RosettaInstalled &&
            Status.BottleEngines["ascendara"].map { Status.Engines.contains($0) } == true
    }

    var IsReady: Bool { Status.WineAvailable || IsHighballReady }

    var D3DMetalLicenseText: String? {
        guard let URL = FindHighballResource("d3dmetal-license.txt") else { return nil }
        return try? String(contentsOf: URL, encoding: .utf8)
    }

    private func FindHighballResource(_ Name: String) -> URL? {
        let Candidates = [Bundle.main.resourceURL?.appendingPathComponent("Highball/" + Name),
                          FindHighball()?.deletingLastPathComponent().appendingPathComponent(Name)]
        return Candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func FindExecutable(_ Paths: [String?]) -> URL? {
        Paths.compactMap { $0 }.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    private func ShowSetup(_ Message: String, Progress: Double? = nil, Detail: String? = nil) {
        if SetupMessage != Message { SetupMessage = Message }
        if SetupProgress != Progress { SetupProgress = Progress }
        if SetupDetail != Detail { SetupDetail = Detail }
    }

    private func ClearSetup() {
        SetupMessage = nil
        SetupProgress = nil
        SetupDetail = nil
    }

    private func EngineDownloads(_ Data: Data) -> [EngineDownload] {
        guard let Manifest = try? JSONSerialization.jsonObject(with: Data) as? [String: Any],
              let Components = Manifest["components"] as? [String: [String: Any]] else { return [] }
        let Directory = HighballHome.appendingPathComponent("downloads", isDirectory: true)
        var Seen = Set<String>()
        return Components.keys.sorted().compactMap { Name in
            guard let Component = Components[Name],
                  let Address = Component["url"] as? String,
                  let SourceURL = URL(string: Address),
                  let Hash = Component["sha256"] as? String,
                  let Size = Component["size"] as? NSNumber,
                  Size.int64Value > 0 else { return nil }
            let Destination = Directory.appendingPathComponent(SourceURL.lastPathComponent)
            let Key = Destination.lastPathComponent + "." + String(Hash.prefix(12))
            guard Seen.insert(Key).inserted else { return nil }
            return EngineDownload(Name: Name, Destination: Destination,
                                  Partial: URL(fileURLWithPath: Destination.path + "." + String(Hash.prefix(12)) + ".partial"),
                                  ExpectedBytes: Size.int64Value)
        }
    }

    private func FileSize(_ URL: URL) -> Int64 {
        guard let Attributes = try? FileManager.default.attributesOfItem(atPath: URL.path),
              let Size = Attributes[.size] as? NSNumber else { return 0 }
        return Size.int64Value
    }

    private func RefreshDownloadProgress(_ Downloads: [EngineDownload]) {
        let Total = Downloads.reduce(Int64(0)) { $0 + $1.ExpectedBytes }
        guard Total > 0 else {
            ShowSetup("Downloading and installing compatibility files…")
            return
        }
        var Received: Int64 = 0
        var Active: EngineDownload?
        for Download in Downloads {
            let Complete = FileSize(Download.Destination)
            let Partial = FileSize(Download.Partial)
            Received += min(Download.ExpectedBytes, max(Complete, Partial))
            if Partial > 0 && Partial < Download.ExpectedBytes { Active = Download }
        }
        let Detail = "\(ByteCountFormatter.string(fromByteCount: Received, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Total, countStyle: .file)) downloaded"
        if Received >= Total {
            ShowSetup("Installing and verifying compatibility files…", Detail: Detail)
        } else {
            let Name = Active.map { "Downloading \($0.Name)…" } ?? "Downloading compatibility files…"
            ShowSetup(Name, Progress: Double(Received) / Double(Total), Detail: Detail)
        }
    }

    private func InstallEngineCommand(_ Highball: URL, Arguments: [String], ManifestData: Data) async throws {
        let Downloads = EngineDownloads(ManifestData)
        RefreshDownloadProgress(Downloads)
        let Monitor = Task { @MainActor in
            while !Task.isCancelled {
                RefreshDownloadProgress(Downloads)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        do {
            _ = try await NativeProcess.Checked(Highball, Arguments, Environment: Environment)
        } catch {
            Monitor.cancel()
            await Monitor.value
            throw error
        }
        Monitor.cancel()
        await Monitor.value
        ShowSetup("Checking the installed compatibility files…")
    }

    @discardableResult
    func Detect() async -> CompatibilityStatus {
        var Current = CompatibilityStatus()
        Current.WinePath = FindWine()?.path
        Current.HighballPath = FindHighball()?.path
        let Arm = try? await NativeProcess.Run(URL(fileURLWithPath: "/usr/sbin/sysctl"), ["-n", "hw.optional.arm64"])
        Current.AppleSilicon = Arm?.Output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        let Rosetta = try? await NativeProcess.Run(URL(fileURLWithPath: "/usr/bin/arch"), ["-x86_64", "/usr/bin/true"])
        Current.RosettaInstalled = Rosetta?.Status == 0
        if let Highball = FindHighball() {
            do {
                let Engines = try await NativeProcess.Checked(Highball, ["engine", "list"], Environment: Environment)
                Current.Engines = Engines.components(separatedBy: .newlines).filter { $0.contains("\trenderers:") && !$0.contains("INCOMPLETE") }.compactMap { $0.components(separatedBy: "\t").first }
                let Bottles = try await NativeProcess.Checked(Highball, ["bottle", "list"], Environment: Environment)
                for Line in Bottles.components(separatedBy: .newlines) {
                    let Fields = Line.components(separatedBy: "\t")
                    guard let Name = Fields.first, !Name.isEmpty,
                          let EngineField = Fields.first(where: { $0.hasPrefix("engine=") }) else { continue }
                    Current.BottleEngines[Name] = String(EngineField.dropFirst("engine=".count))
                }
                Current.Bottles = Current.BottleEngines.keys.sorted()
            } catch { Current.ErrorMessage = error.localizedDescription }
        }
        Status = Current
        return Current
    }

    func CreateBottle(Name: String, Engine: String) async throws {
        guard let Highball = FindHighball() else { throw RuntimeError.Message("Highball was not found. Choose its executable in Settings.") }
        guard !Name.isEmpty, !Engine.isEmpty else { throw RuntimeError.Message("Choose a bottle name and an installed engine.") }
        _ = try await NativeProcess.Checked(Highball, ["bottle", "create", Name, "--engine", Engine], Environment: Environment)
        await Detect()
    }

    func SetBottleEngine(Name: String, Engine: String) async throws {
        guard let Highball = FindHighball(), Status.Engines.contains(Engine), Status.Bottles.contains(Name) else {
            throw RuntimeError.Message("Choose an existing bottle and an installed engine.")
        }
        if Status.BottleEngines[Name] == Engine { return }
        defer { ClearSetup() }
        ShowSetup("Switching the Windows environment to \(Engine)…")
        _ = try await NativeProcess.Checked(Highball, ["bottle", "set", Name, "engine", Engine], Environment: Environment)
        ShowSetup("Refreshing the Windows environment…")
        _ = try await NativeProcess.Checked(Highball, ["bottle", "repair", Name], Environment: Environment)
        await Detect()
    }

    func InstallEngine(ManifestURL: URL) async throws {
        guard let Highball = FindHighball() else { throw RuntimeError.Message("Highball was not found.") }
        defer { ClearSetup() }
        let Data = try Data(contentsOf: ManifestURL)
        try await InstallEngineCommand(Highball, Arguments: ["engine", "install", ManifestURL.path], ManifestData: Data)
        await Detect()
    }

    func InstallDefaultEngine() async throws {
        guard let Manifest = DefaultManifestURL else { throw RuntimeError.Message("The bundled Highball engine manifest is missing. Choose an engine manifest file instead.") }
        try await InstallEngine(ManifestURL: Manifest)
    }

    func EnsureReady(Bottle: String = "ascendara") async throws {
        let Name = Bottle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Name.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$", options: .regularExpression) != nil else {
            throw RuntimeError.Message("Choose a valid Highball environment name.")
        }
        defer { ClearSetup() }
        let Current = await Detect()
        if Current.AppleSilicon, Current.RosettaInstalled,
           Current.HighballAvailable,
           let ExistingEngine = Current.BottleEngines[Name],
           Current.Engines.contains(ExistingEngine) {
            return
        }
        let Work: Task<String, Error>
        if let Existing = PreparationTask { Work = Existing }
        else {
            let New = Task { @MainActor in try await self.PrepareEngine() }
            PreparationTask = New
            Work = New
        }
        let Engine: String
        do { Engine = try await Work.value }
        catch {
            PreparationTask = nil
            ClearSetup()
            throw error
        }
        PreparationTask = nil
        guard let Highball = FindHighball() else { throw RuntimeError.Message("Highball is not bundled with this build.") }
        let Prepared = await Detect()
        let ExistingEngine = Prepared.BottleEngines[Name]
        if ExistingEngine == nil {
            ShowSetup("Preparing the Windows environment…")
            _ = try await NativeProcess.Checked(Highball, ["bottle", "create", Name, "--engine", Engine], Environment: Environment)
        } else if let ExistingEngine, ExistingEngine != Engine && !Prepared.Engines.contains(ExistingEngine) {
            ShowSetup("Updating the Windows environment…")
            _ = try await NativeProcess.Checked(Highball, ["bottle", "set", Name, "engine", Engine], Environment: Environment)
            _ = try await NativeProcess.Checked(Highball, ["bottle", "repair", Name], Environment: Environment)
        }
        ShowSetup("Checking the Windows environment…")
        await Detect()
    }

    private func PrepareEngine() async throws -> String {
        ShowSetup("Checking this Mac and its compatibility files…")
        let Current = await Detect()
        guard Current.AppleSilicon, let Highball = FindHighball() else {
            throw RuntimeError.Message("Highball requires an Apple Silicon Mac and the bundled Highball command-line tool.")
        }
        guard let Manifest = DefaultManifestURL, let Data = try? Data(contentsOf: Manifest) else {
            throw RuntimeError.Message("The Highball engine manifest is missing from this build.")
        }
        let Engine = try ValidateManifest(Data)
        if !Current.RosettaInstalled {
            ShowSetup("Installing Rosetta 2… macOS may ask for your administrator password.")
            _ = try await NativeProcess.Checked(URL(fileURLWithPath: "/usr/bin/osascript"),
                ["-e", "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"])
        }
        if !Current.Engines.contains(Engine) {
            var Arguments = ["engine", "install", Manifest.path]
            if UserDefaults.standard.bool(forKey: "D3DMetalLicenseAccepted") {
                Arguments.append("--accept-d3dmetal-license")
            }
            try await InstallEngineCommand(Highball, Arguments: Arguments, ManifestData: Data)
        }
        return Engine
    }

    func InstallLatestEngine() async throws {
        ShowSetup("Checking the latest Highball engine…")
        defer { ClearSetup() }
        var Request = URLRequest(url: LatestManifestAddress, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        Request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (Data, Response) = try await URLSession.shared.data(for: Request)
        guard (Response as? HTTPURLResponse)?.statusCode == 200 else {
            throw RuntimeError.Message("Highball did not return an engine manifest.")
        }
        guard Data.count < 2_000_000 else { throw RuntimeError.Message("The Highball manifest is unexpectedly large.") }
        let Engine = try ValidateManifest(Data)
        try FileManager.default.createDirectory(at: HighballHome, withIntermediateDirectories: true)
        let Pending = HighballHome.appendingPathComponent("pending-engine-manifest.json")
        try Data.write(to: Pending, options: .atomic)
        defer { try? FileManager.default.removeItem(at: Pending) }
        guard let Highball = FindHighball() else { throw RuntimeError.Message("Highball is not bundled with this build.") }
        let Current = await Detect()
        guard Current.AppleSilicon else { throw RuntimeError.Message("Highball requires Apple Silicon.") }
        if !Current.RosettaInstalled {
            ShowSetup("Installing Rosetta 2… macOS may ask for your administrator password.")
            _ = try await NativeProcess.Checked(URL(fileURLWithPath: "/usr/bin/osascript"),
                ["-e", "do shell script \"/usr/sbin/softwareupdate --install-rosetta --agree-to-license\" with administrator privileges"])
        }
        if !Current.Engines.contains(Engine) {
            var Arguments = ["engine", "install", Pending.path]
            if UserDefaults.standard.bool(forKey: "D3DMetalLicenseAccepted") {
                Arguments.append("--accept-d3dmetal-license")
            }
            try await InstallEngineCommand(Highball, Arguments: Arguments, ManifestData: Data)
        }
        try Data.write(to: LatestManifestFile, options: .atomic)
        try await EnsureReady()
        if Status.Bottles.contains("ascendara") {
            try await SetBottleEngine(Name: "ascendara", Engine: Engine)
        }
    }

    private func ValidateManifest(_ Data: Data) throws -> String {
        guard let Root = try JSONSerialization.jsonObject(with: Data) as? [String: Any],
              Root["$schema"] as? String == "https://highball.app/schemas/engine-manifest/v0",
              Root["arch"] as? String == "x86_64",
              let Engine = Root["id"] as? String,
              Engine.range(of: "^[A-Za-z0-9._-]{1,100}$", options: .regularExpression) != nil,
              let Components = Root["components"] as? [String: [String: Any]],
              !Components.isEmpty, Components.count < 100 else {
            throw RuntimeError.Message("Highball returned an invalid engine manifest.")
        }
        for (_, Component) in Components {
            guard let Address = Component["url"] as? String,
                  let URL = URL(string: Address), URL.scheme == "https",
                  ["github.com", "raw.githubusercontent.com"].contains(URL.host?.lowercased() ?? ""),
                  let Hash = Component["sha256"] as? String,
                  Hash.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
                throw RuntimeError.Message("A Highball component has an invalid URL or checksum.")
            }
        }
        return Engine
    }

    func AcceptD3DMetalLicense(Engine: String) async throws {
        guard let Highball = FindHighball(), Status.Engines.contains(Engine) else { throw RuntimeError.Message("Choose an installed Highball engine first.") }
        _ = try await NativeProcess.Checked(Highball, ["engine", "accept", Engine, "apple-gptk-license-2023-08-17"], Environment: Environment)
        UserDefaults.standard.set(true, forKey: "D3DMetalLicenseAccepted")
        await Detect()
    }

    func LaunchCommand(for Game: LibraryGame) async throws -> (Executable: URL, Arguments: [String], Environment: [String: String]) {
        var LaunchEnvironment = ProcessInfo.processInfo.environment
        switch Game.LaunchMode {
        case .Native:
            return (Game.ExecutableURL, Game.LaunchArguments, LaunchEnvironment)
        case .Wine:
            guard let Wine = FindWine() else { throw RuntimeError.Message("Wine is not installed. Choose a Wine executable in Settings, or use a configured Highball bottle.") }
            if let Prefix = Game.WinePrefixPath, !Prefix.isEmpty { LaunchEnvironment["WINEPREFIX"] = Prefix }
            let Extension = Game.ExecutableURL.pathExtension.lowercased()
            let Prefix = Extension == "msi" ? ["msiexec", "/i"] : (["bat", "cmd"].contains(Extension) ? ["cmd", "/c"] : [])
            return (Wine, Prefix + [Game.ExecutablePath] + Game.LaunchArguments, LaunchEnvironment)
        case .Highball:
            try await EnsureReady(Bottle: Game.HighballBottle)
            let Current = await Detect()
            guard let Path = Current.HighballPath, Current.AppleSilicon else { throw RuntimeError.Message("Highball needs Apple Silicon and its installed command line runtime.") }
            guard Current.RosettaInstalled else { throw RuntimeError.Message("Install Rosetta 2 before launching Windows games through Highball.") }
            guard Current.Bottles.contains(Game.HighballBottle) else { throw RuntimeError.Message("The Highball bottle ‘\(Game.HighballBottle)’ is not installed. Create it in Compatibility settings first.") }
            var Arguments = ["run"]
            if ["dxmt", "d3dmetal", "dxvk", "vkd3d", "wined3d"].contains(Game.Renderer) { Arguments += ["--renderer", Game.Renderer] }
            Arguments += [Game.HighballBottle, Game.ExecutablePath]
            if !Game.LaunchArguments.isEmpty { Arguments += ["--"] + Game.LaunchArguments }
            return (URL(fileURLWithPath: Path), Arguments, Environment)
        }
    }
}


actor MacCompatibilityService {
    private let CacheDirectory: URL
    private let Session: URLSession
    private let Lifetime: TimeInterval = 24 * 60 * 60
    private let MaximumStaleAge: TimeInterval = 7 * 24 * 60 * 60

    private struct CuratedFeed: Decodable {
        let license: String
        let games: [CuratedGame]
    }

    private struct CuratedGame: Decodable {
        let steam_appid: Int?
        let status: String
        let url: String?
        let lastVerified: String?
    }

    private struct PredictionFeed: Decodable {
        let license: String
        let games: [String: PredictionGame]
    }

    private struct PredictionGame: Decodable {
        let s: String
        let p: String
        let c: String
    }

    init(CacheDirectory: URL = AppPaths.Support.appendingPathComponent("CompatibilityCache"), Session: URLSession = .shared) {
        self.CacheDirectory = CacheDirectory
        self.Session = Session
    }

    func LoadCached() -> [String: MacCompatibility] {
        guard let Curated = ReadCache(Name: "HighballGames.json") else { return [:] }
        return Self.Decode(Curated: Curated, Predictions: ReadCache(Name: "HighballPredictions.json"))
    }

    func Load() async -> [String: MacCompatibility] {
        async let Curated = LoadFeed(Name: "HighballGames.json", Path: "games.json")
        async let Predictions = LoadFeed(Name: "HighballPredictions.json", Path: "predictions.json")
        guard let CuratedData = await Curated else { return [:] }
        return Self.Decode(Curated: CuratedData, Predictions: await Predictions)
    }

    private func LoadFeed(Name: String, Path: String) async -> Data? {
        let CacheURL = CacheDirectory.appendingPathComponent(Name)
        let Cached = ReadCache(Name: Name)
        let Modified = (try? CacheURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let Cached, let Modified, Date().timeIntervalSince(Modified) < Lifetime { return Cached }
        do {
            let Address = URL(string: "https://gethighball.com/data/\(Path)")!
            var Request = URLRequest(url: Address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
            Request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (Data, Response) = try await Session.data(for: Request)
            guard (Response as? HTTPURLResponse)?.statusCode == 200 else { return Cached }
            guard Self.ValidFeed(Data: Data, Path: Path) else { return Cached }
            try? FileManager.default.createDirectory(at: CacheDirectory, withIntermediateDirectories: true)
            try? Data.write(to: CacheURL, options: .atomic)
            return Data
        } catch {
            return Cached
        }
    }

    private func ReadCache(Name: String) -> Data? {
        let URL = CacheDirectory.appendingPathComponent(Name)
        guard let Modified = (try? URL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              Date().timeIntervalSince(Modified) < MaximumStaleAge else { return nil }
        return try? Data(contentsOf: URL)
    }

    private static func ValidFeed(Data: Data, Path: String) -> Bool {
        if Path == "games.json" { return (try? JSONDecoder().decode(CuratedFeed.self, from: Data))?.license == "CC0-1.0" }
        return (try? JSONDecoder().decode(PredictionFeed.self, from: Data))?.license == "ODbL-1.0"
    }

    private static func Decode(Curated: Data, Predictions: Data?) -> [String: MacCompatibility] {
        guard let Feed = try? JSONDecoder().decode(CuratedFeed.self, from: Curated), Feed.license == "CC0-1.0" else { return [:] }
        var Results: [String: MacCompatibility] = [:]
        var CuratedIds: Set<String> = []
        for Game in Feed.games {
            guard let AppId = Game.steam_appid else { continue }
            let Id = String(AppId)
            CuratedIds.insert(Id)
            guard let Address = Game.url.flatMap(URL.init(string:)) else { continue }
            switch Game.status {
            case "verified-local":
                let DateText = Game.lastVerified.map { " Last checked \($0)." } ?? ""
                Results[Id] = MacCompatibility(Kind: .Works,
                                               Evidence: "Tested on Apple Silicon by Highball.\(DateText) Your Mac, macOS version, and game build may differ.",
                                               SourceURL: Address, IsPrediction: false)
            case "reported-upstream":
                Results[Id] = MacCompatibility(Kind: .Likely,
                                               Evidence: "Reported working in upstream release notes; not verified by Highball on this Mac.",
                                               SourceURL: Address, IsPrediction: false)
            case "community":
                Results[Id] = MacCompatibility(Kind: .Likely,
                                               Evidence: "Reported by Mac players; not verified by Highball on this Mac.",
                                               SourceURL: Address, IsPrediction: false)
            default: break
            }
        }
        if let Predictions, let Feed = try? JSONDecoder().decode(PredictionFeed.self, from: Predictions), Feed.license == "ODbL-1.0" {
            for (Id, Game) in Feed.games where !CuratedIds.contains(Id) && Game.p == "Likely playable" && Game.c == "good" {
                guard let Address = URL(string: "https://gethighball.com/games/\(Game.s)/") else { continue }
                Results[Id] = MacCompatibility(Kind: .Likely,
                                               Evidence: "Prediction from ProtonDB Linux reports and anti-cheat data. It has not been tested on a Mac.",
                                               SourceURL: Address, IsPrediction: true)
            }
        }
        return Results
    }
}
