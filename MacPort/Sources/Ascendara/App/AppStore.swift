import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppStore: ObservableObject {
    @Published var Route: AppRoute = .Home
    @Published var Games: [Game] = []
    @Published var Library: [LibraryGame] = []
    @Published var Downloads: [DownloadItem] = []
    @Published var Wishlist: Set<String> = []
    @Published var SearchQuery = ""
    @Published var SelectedGenre = "All genres"
    @Published var SortOrder = "Relevance"
    @Published var SelectedGame: Game?
    @Published var Settings = AppSettings() {
        didSet { Theme.Name = Settings.Theme }
    }
    @Published var IsLoading = false
    @Published var CatalogWarning: String?
    @Published var ErrorMessage: String?
    @Published var Notice: String?
    @Published var ShowingWelcome = false
    @Published var ShowingBigPicture = false
    @Published var CatalogMetadata: Ascendara.CatalogMetadata = .init()
    @Published var RunningIds: Set<UUID> = []
    @Published var VerifiedIds: Set<String> = []
    @Published var OnlineOnly = false
    @Published var DlcOnly = false
    @Published var VerifiedOnly = false
    @Published var SelectedProvider = "All providers"
    @Published var MaximumSizeGB: Double = 0
    @Published var ResolvingGameIds: Set<String> = []

    let Catalog = CatalogService(CacheDirectory: AppPaths.Support.appendingPathComponent("CatalogCache"))
    let LibraryStore: LibraryService
    let DownloadStore: DownloadService
    let Launcher: GameLauncher
    let Compatibility = CompatibilityService()
    private var Observers: Set<AnyCancellable> = []
    private var CatalogTask: Task<Void, Never>?
    private var DidStart = false
    private var SleepActivity: NSObjectProtocol?
    private var PendingGameId: String?
    private let SettingsURL = AppPaths.Support.appendingPathComponent("Settings.json")
    private let WishlistURL = AppPaths.Support.appendingPathComponent("Wishlist.json")
    private var SavedSettings = AppSettings()

    var CurrentRoute: AppRoute {
        get { Route }
        set { Route = newValue }
    }

    init() {
        LibraryStore = LibraryService(StorageDirectory: AppPaths.Support)
        DownloadStore = DownloadService(StorageDirectory: AppPaths.Support)
        Launcher = GameLauncher(Compatibility: Compatibility)
        do {
            if FileManager.default.fileExists(atPath: SettingsURL.path) {
                Settings = try AppSettings.Load(From: SettingsURL)
            }
            if FileManager.default.fileExists(atPath: WishlistURL.path) {
                Wishlist = try AppPaths.Read(Set<String>.self, From: WishlistURL)
            }
        } catch { ErrorMessage = "Your saved data could not be read: \(error.localizedDescription)" }
        if ProcessInfo.processInfo.environment["ASCENDARA_NATIVE_HOME"] == nil {
            Settings.TorBoxAPIKey = KeychainService.Read("TorBoxAPIKey") ?? ""
            Settings.QBitTorrentPassword = KeychainService.Read("QBitTorrentPassword") ?? ""
        }
        Settings.FirebaseAPIKey = Settings.FirebaseAPIKey.isEmpty
            ? ProcessInfo.processInfo.environment["VITE_FIREBASE_API_KEY"] ?? "" : Settings.FirebaseAPIKey
        Settings.FirebaseProjectId = Settings.FirebaseProjectId.isEmpty
            ? ProcessInfo.processInfo.environment["VITE_FIREBASE_PROJECT_ID"] ?? "" : Settings.FirebaseProjectId
        SavedSettings = Settings
        Route = AppRoute(rawValue: Settings.DefaultPage) ?? .Home
        Theme.Name = Settings.Theme
        ShowingWelcome = !Settings.HasCompletedWelcome
        LibraryStore.$Games.sink { [weak self] in self?.Library = $0 }.store(in: &Observers)
        LibraryStore.$ErrorMessage.compactMap { $0 }.sink { [weak self] in self?.ErrorMessage = $0 }.store(in: &Observers)
        DownloadStore.$Downloads.sink { [weak self] in self?.DownloadsChanged($0) }.store(in: &Observers)
        DownloadStore.$ErrorMessage.compactMap { $0 }.sink { [weak self] in self?.ErrorMessage = $0 }.store(in: &Observers)
        DownloadStore.OnCompleted = { [weak self] Download in self?.DownloadCompleted(Download) }
        Launcher.$RunningIds.sink { [weak self] in self?.RunningIds = $0; self?.UpdateSleepActivity() }.store(in: &Observers)
        Launcher.$ErrorMessage.compactMap { $0 }.sink { [weak self] in self?.ErrorMessage = $0 }.store(in: &Observers)
        Launcher.OnSessionEnded = { [weak self] Id, StartedAt, Seconds in
            do { try self?.LibraryStore.RecordSession(Id, StartedAt: StartedAt, Seconds: Seconds) }
            catch { self?.Report(error) }
        }
    }

    var Genres: [String] { ["All genres"] + Set(Games.flatMap(\.Categories)).sorted() }
    var Providers: [String] { ["All providers"] + Set(Games.flatMap { $0.DownloadLinks.keys }).sorted() }
    var FilteredGames: [Game] {
        let Sort: CatalogSort
        switch SortOrder {
        case "Name A–Z", "Name", "A–Z": Sort = .Name
        case "Recently updated", "Recent", "Newest": Sort = .Recent
        case "Smallest size", "Size": Sort = .Smallest
        default: Sort = .Popular
        }
        return GameSearch.Filter(Games: Games, Query: SearchQuery,
                                 Categories: SelectedGenre == "All genres" ? [] : [SelectedGenre], Sort: Sort,
                                 OnlineOnly: OnlineOnly, DlcOnly: DlcOnly,
                                 MaximumSizeGB: MaximumSizeGB > 0 ? MaximumSizeGB : nil,
                                 Provider: SelectedProvider == "All providers" ? nil : SelectedProvider,
                                 VerifiedIds: VerifiedOnly ? VerifiedIds : nil)
    }
    var WishlistGames: [Game] { Games.filter { Wishlist.contains($0.Id) } }
    var ActiveDownloadCount: Int { Downloads.filter(\.IsActive).count }

    func Start() {
        guard !DidStart else { return }
        DidStart = true
        ApplySettings()
        RefreshCatalog()
    }

    func RefreshCatalog() {
        CatalogTask?.cancel()
        CatalogTask = Task {
            IsLoading = true
            defer { if !Task.isCancelled { IsLoading = false } }
            do {
                let Source = try ActiveCatalogSource()
                let Snapshot = try await Catalog.Load(Source: Source, Force: true)
                try Task.checkCancellation()
                Games = Snapshot.Games
                CatalogMetadata = Snapshot.Metadata
                CatalogWarning = Snapshot.Warning
                if let SelectedGame { self.SelectedGame = Games.first { $0.Id == SelectedGame.Id } ?? SelectedGame }
                if let Id = PendingGameId {
                    PendingGameId = nil
                    if let Game = Games.first(where: { $0.Id == Id }) { OpenGame(Game) }
                    else { Notice = "This game is not in the active catalogue. Choose its source in Preferences." }
                }
                if let Values = try? await Catalog.LoadVerifiedIds(), !Task.isCancelled { VerifiedIds = Values }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { CatalogWarning = error.localizedDescription }
            }
        }
    }

    private func ActiveCatalogSource() throws -> CatalogSource {
        switch Settings.CatalogSource.lowercased() {
        case "local":
            guard !Settings.LocalCatalogPath.isEmpty else { throw AppFailure.Message("Choose a local catalogue JSON file in External sources.") }
            return .Local(URL(fileURLWithPath: Settings.LocalCatalogPath))
        case "custom", "hydra":
            guard let URL = URL(string: Settings.CustomCatalogURL), ["https", "http"].contains(URL.scheme?.lowercased() ?? "") else {
                throw AppFailure.Message("Enter a valid catalogue URL in External sources.")
            }
            return .Custom(URL, URL.host ?? "Custom source")
        default: return .Community
        }
    }

    func OpenGame(_ Game: Game) { SelectedGame = Game }
    func LoadGameDetails(_ Game: Game) async -> GameDetails? {
        do { return try await Catalog.LoadDetails(Game: Game) }
        catch { Notice = "Game information: \(error.localizedDescription)"; return nil }
    }
    func ToggleWishlist(_ Game: Game) {
        var Updated = Wishlist
        if Updated.contains(Game.Id) { Updated.remove(Game.Id) } else { Updated.insert(Game.Id) }
        do { try AppPaths.Write(Updated, To: WishlistURL); Wishlist = Updated }
        catch { Report(error) }
    }
    func LibraryMatch(_ Game: Game) -> LibraryGame? {
        Library.first { $0.CatalogId == Game.Id || $0.Name.caseInsensitiveCompare(Game.Name) == .orderedSame }
    }
    func IsRunning(_ Game: LibraryGame) -> Bool { RunningIds.contains(Game.Id) }

    func ImportGame() {
        let Panel = NSOpenPanel()
        Panel.title = "Add a game to your library"
        Panel.prompt = "Add Game"
        Panel.canChooseDirectories = false
        Panel.allowsMultipleSelection = true
        Panel.treatsFilePackagesAsDirectories = false
        guard Panel.runModal() == .OK else { return }
        for URL in Panel.urls {
            do {
                _ = try LibraryStore.ImportGame(Name: URL.deletingPathExtension().lastPathComponent, ExecutableURL: URL)
            } catch { Report(error) }
        }
        Route = .Library
    }

    func ImportGame(For Game: Game) {
        let Panel = NSOpenPanel()
        Panel.title = "Choose the executable for \(Game.Name)"
        Panel.canChooseDirectories = false
        Panel.treatsFilePackagesAsDirectories = false
        guard Panel.runModal() == .OK, let URL = Panel.url else { return }
        do {
            _ = try LibraryStore.ImportGame(Name: Game.Name, ExecutableURL: URL, CatalogId: Game.Id, ImageURL: Game.ArtworkURL?.absoluteString)
            Notice = "\(Game.Name) added to your library."
        } catch { Report(error) }
    }

    func UpdateGame(_ Game: LibraryGame) {
        do { try LibraryStore.Update(Game) } catch { Report(error) }
    }
    func UpdateLibraryGame(_ Game: LibraryGame) { UpdateGame(Game) }
    func ToggleLibraryFavorite(_ Game: LibraryGame) {
        var Updated = Game
        Updated.Favorite.toggle()
        UpdateGame(Updated)
    }
    func SetExecutable(_ Game: LibraryGame) {
        let Panel = NSOpenPanel()
        Panel.title = "Choose the executable for \(Game.Name)"
        Panel.canChooseDirectories = false
        guard Panel.runModal() == .OK, let URL = Panel.url else { return }
        do {
            try LibraryStore.ValidateExecutable(URL)
            var Updated = Game
            Updated.ExecutablePath = URL.path
            Updated.DirectoryPath = URL.deletingLastPathComponent().path
            try LibraryStore.Update(Updated)
        } catch { Report(error) }
    }
    func LaunchGame(_ Game: LibraryGame) {
        var Game = Game
        if Game.LaunchArguments.isEmpty {
            Game.LaunchArguments = Settings.LaunchArguments.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        Task { do { try await Launcher.Launch(Game) } catch { Report(error) } }
    }
    func StopGame(_ Game: LibraryGame) {
        Task { do { try await Launcher.Stop(Game.Id) } catch { Report(error) } }
    }
    func RevealGame(_ Game: LibraryGame) { NSWorkspace.shared.activateFileViewerSelecting([Game.ExecutableURL]) }
    func RemoveGame(_ Game: LibraryGame) {
        let Alert = NSAlert()
        Alert.messageText = "Remove \(Game.Name) from your library?"
        Alert.informativeText = "The game files will remain on your Mac."
        Alert.addButton(withTitle: "Remove")
        Alert.addButton(withTitle: "Cancel")
        guard Alert.runModal() == .alertFirstButtonReturn else { return }
        do { try LibraryStore.Remove(Game.Id) } catch { Report(error) }
    }

    func StartDownload(_ Game: Game, Link: String) {
        guard let URL = URL(string: Link) else { ErrorMessage = "This download link is invalid."; return }
        if URL.scheme?.lowercased() == "magnet" {
            Task {
                do {
                    try await TorrentService.Add(URL: URL, Settings: Settings)
                    Notice = "\(Game.Name) was sent to qBittorrent."
                } catch { Report(error) }
            }
            return
        }
        guard ResolvingGameIds.insert(Game.Id).inserted else { return }
        Task {
            defer { ResolvingGameIds.remove(Game.Id) }
            do {
                let Files = try await DownloadLinkResolver.Resolve(URL: URL)
                let BatchId = UUID()
                let Directory = URLFromPath(Settings.DownloadDirectory)
                    .appendingPathComponent(RuntimePaths.SafeName(Game.Name), isDirectory: true)
                    .appendingPathComponent(String(BatchId.uuidString.prefix(8)), isDirectory: true)
                for File in Files {
                    _ = try DownloadStore.Start(Name: Game.Name, URL: File.URL, DestinationDirectory: Directory,
                                                CatalogId: Game.Id, FileName: File.FileName, BatchId: BatchId, Version: Game.Version)
                }
                SelectedGame = nil
                Route = .Downloads
            } catch { Report(error) }
        }
    }
    func StartDirectDownload(Name: String, Link: String) {
        StartDownload(Game(Id: "direct-\(UUID().uuidString)", Name: Name.isEmpty ? "Download" : Name), Link: Link)
    }
    func PauseDownload(_ Download: DownloadItem) { do { try DownloadStore.Pause(Download.Id) } catch { Report(error) } }
    func ResumeDownload(_ Download: DownloadItem) { do { try DownloadStore.Resume(Download.Id) } catch { Report(error) } }
    func CancelDownload(_ Download: DownloadItem) { do { try DownloadStore.Cancel(Download.Id) } catch { Report(error) } }
    func RevealDownload(_ Download: DownloadItem) {
        NSWorkspace.shared.activateFileViewerSelecting([Download.ExtractedPath.map(URLFromPath) ?? Download.FileURL])
    }
    func ExtractDownload(_ Download: DownloadItem) {
        Task { do { _ = try await DownloadStore.Extract(Download.Id) } catch { Report(error) } }
    }
    func ImportDownload(_ Download: DownloadItem) {
        let Panel = NSOpenPanel()
        Panel.title = "Select the game executable"
        Panel.directoryURL = Download.ExtractedPath.map(URLFromPath) ?? Download.DestinationDirectory
        guard Panel.runModal() == .OK, let URL = Panel.url else { return }
        do {
            let CatalogGame = Games.first { $0.Id == Download.CatalogId }
            _ = try LibraryStore.ImportGame(Name: Download.Name, ExecutableURL: URL, CatalogId: Download.CatalogId,
                                            ImageURL: CatalogGame?.ArtworkURL?.absoluteString, Version: Download.Version)
            Route = .Library
        } catch { Report(error) }
    }
    private func DownloadsChanged(_ Values: [DownloadItem]) {
        Downloads = Values
        UpdateSleepActivity()
    }
    private func DownloadCompleted(_ Download: DownloadItem) {
        if Download.State == .Completed && Settings.AutoExtract {
            let Group = Download.BatchId.map { BatchId in DownloadStore.Downloads.filter { $0.BatchId == BatchId } } ?? [Download]
            guard Group.allSatisfy({ $0.State == .Completed || $0.State == .Extracted }) else { return }
            let Archives = Group.filter { File in
                let Name = File.FileName.lowercased()
                let IsLaterPart = Name.range(of: #"\.part(?!0*1\.)\d+\.rar$"#, options: .regularExpression) != nil
                return !IsLaterPart && (["zip", "7z", "rar", "tar", "gz", "bz2", "xz"].contains(File.FileURL.pathExtension.lowercased()) || Name.hasSuffix(".7z.001") || Name.hasSuffix(".zip.001"))
            }.sorted { $0.CreatedAt < $1.CreatedAt }
            if let Archive = Archives.first, Archive.State == .Completed { ExtractDownload(Archive) }
        } else if Download.State == .Extracted {
            Notice = "\(Download.Name) is ready. Select its executable to add it to your library."
        }
    }

    func ChooseDownloadDirectory() {
        guard let URL = ChooseFolder(Title: "Choose your games folder") else { return }
        Settings.DownloadDirectory = URL.path
        SaveSettings()
    }
    func ImportCatalog() {
        let Panel = NSOpenPanel()
        Panel.title = "Import a local catalogue"
        Panel.allowedContentTypes = [.json]
        guard Panel.runModal() == .OK, let URL = Panel.url else { return }
        Settings.LocalCatalogPath = URL.path
        Settings.CatalogSource = "local"
        SaveSettings()
        RefreshCatalog()
    }
    func SaveSettings() {
        do {
            Settings.ConcurrentDownloads = min(8, max(1, Settings.ConcurrentDownloads))
            if Settings.TorBoxAPIKey != SavedSettings.TorBoxAPIKey { try KeychainService.Write(Settings.TorBoxAPIKey, For: "TorBoxAPIKey") }
            if Settings.QBitTorrentPassword != SavedSettings.QBitTorrentPassword { try KeychainService.Write(Settings.QBitTorrentPassword, For: "QBitTorrentPassword") }
            try AppPaths.Write(Settings.PublicCopy(), To: SettingsURL)
            SavedSettings = Settings
            ApplySettings()
        } catch { Report(error) }
    }
    private func ApplySettings() {
        Theme.Name = Settings.Theme
        DownloadStore.MaximumConcurrentDownloads = Settings.ConcurrentDownloads
        Compatibility.CustomWinePath = Settings.WinePath.isEmpty ? nil : Settings.WinePath
        Compatibility.CustomHighballPath = Settings.HighballPath.isEmpty ? nil : Settings.HighballPath
        UpdateSleepActivity()
    }
    private func UpdateSleepActivity() {
        let Needed = Settings.KeepAwake && (Downloads.contains(where: \.IsActive) || !RunningIds.isEmpty)
        if Needed && SleepActivity == nil {
            SleepActivity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason: "Ascendara is downloading or running a game")
        } else if !Needed, let Activity = SleepActivity {
            ProcessInfo.processInfo.endActivity(Activity)
            SleepActivity = nil
        }
    }
    func PrepareForExit() async {
        Launcher.PrepareForExit()
        RetroService.Shared.PrepareForExit()
        await DownloadStore.PrepareForExit()
        if let Activity = SleepActivity {
            ProcessInfo.processInfo.endActivity(Activity)
            SleepActivity = nil
        }
    }
    func CompleteWelcome() {
        Settings.HasCompletedWelcome = true
        SaveSettings()
        ShowingWelcome = false
    }

    func ExportLibrary() {
        let Panel = NSSavePanel()
        Panel.nameFieldStringValue = "Ascendara-Library.json"
        Panel.allowedContentTypes = [.json]
        guard Panel.runModal() == .OK, let URL = Panel.url else { return }
        do { try AppPaths.Write(Library, To: URL); Notice = "Library exported." } catch { Report(error) }
    }
    func ImportLibrary() {
        let Panel = NSOpenPanel()
        Panel.allowedContentTypes = [.json]
        guard Panel.runModal() == .OK, let URL = Panel.url else { return }
        do {
            let Imported = try AppPaths.Read([LibraryGame].self, From: URL)
            let Count = try LibraryStore.ImportRecords(Imported)
            Notice = "Imported \(Count) games."
        } catch { Report(error) }
    }
    func ImportLegacyLibrary() {
        guard let URL = ChooseFolder(Title: "Select your existing Ascendara games folder") else { return }
        do { Notice = "Imported \(try LibraryStore.ImportLegacyLibrary(URL)) games." }
        catch { Report(error) }
    }

    func CreateBackup(_ Game: LibraryGame) {
        guard let Source = ChooseFolder(Title: "Choose the save folder for \(Game.Name)") else { return }
        Task {
            do {
                let Service = BackupService(StorageDirectory: URLFromPath(Settings.BackupDirectory))
                _ = try await Service.Create(Game, SourceURL: Source)
                Notice = "Backup created for \(Game.Name)."
            } catch { Report(error) }
        }
    }
    func RestoreBackup(_ Game: LibraryGame) {
        Task {
            do {
                let Service = BackupService(StorageDirectory: URLFromPath(Settings.BackupDirectory))
                guard var Backup = try await Service.List(GameId: Game.Id).first else {
                    throw AppFailure.Message("No local backups were found for \(Game.Name).")
                }
                guard let Destination = ChooseFolder(Title: "Restore \(Game.Name) saves to…") else { return }
                let Alert = NSAlert()
                Alert.messageText = "Restore this backup?"
                Alert.informativeText = "Files from \(Backup.CreatedAt.formatted()) will be restored to \(Destination.path). Existing files may be replaced."
                Alert.addButton(withTitle: "Restore"); Alert.addButton(withTitle: "Cancel")
                guard Alert.runModal() == .alertFirstButtonReturn else { return }
                Backup.SourcePath = Destination.path
                _ = try await Service.Restore(Backup)
                Notice = "Backup restored."
            } catch { Report(error) }
        }
    }

    func ScanSteamLibrary() {
        Task {
            do {
                let Entries = try SteamLibraryService.Scan()
                Notice = "Found \(Entries.count) installed Steam games."
                for Entry in Entries {
                    guard let Executable = Entry.ExecutableURL else { continue }
                    _ = try LibraryStore.ImportGame(Name: Entry.Name, ExecutableURL: Executable,
                                                   ImageURL: "https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/\(Entry.Id)/header.jpg")
                }
                Route = .Library
            } catch { Report(error) }
        }
    }
    func OpenExternal(_ Link: String) {
        guard let URL = URL(string: Link), ["http", "https", "steam", "mailto"].contains(URL.scheme?.lowercased() ?? "") else {
            ErrorMessage = "This link cannot be opened."
            return
        }
        NSWorkspace.shared.open(URL)
    }
    func ChooseFolder(Title: String) -> URL? {
        let Panel = NSOpenPanel()
        Panel.title = Title
        Panel.canChooseDirectories = true
        Panel.canChooseFiles = false
        Panel.canCreateDirectories = true
        return Panel.runModal() == .OK ? Panel.url : nil
    }
    func Report(_ Error: Error) { ErrorMessage = Error.localizedDescription }
    func URLFromPath(_ Path: String) -> URL { URL(fileURLWithPath: (Path as NSString).expandingTildeInPath) }

    func HandleURL(_ URL: URL) {
        guard let Link = DeepLink.Parse(URL) else { return }
        switch Link {
        case .Game(let Id):
            if let Game = Games.first(where: { $0.Id == Id }) { OpenGame(Game) }
            else if IsLoading || !DidStart { PendingGameId = Id }
            else { Notice = "This game is not in the active catalogue. Choose its source in Preferences." }
        case .Search(let Query): SearchQuery = Query; Route = .Search
        case .Library: Route = .Library
        case .Downloads: Route = .Downloads
        case .Ascend: Route = .Ascend
        case .ShowWindow: NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
