import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import UserNotifications
import AscendaraCore

struct HomeCategorySection: Sendable {
    let Name: String
    let Count: Int
    let Preview: [Game]
}

struct HomeCatalogSnapshot: Sendable {
    var Highlights: [Game] = []
    var Top: [Game] = []
    var TVFeatured: [Game] = []
    var Updated: [Game] = []
    var Online: [Game] = []
    var Action: [Game] = []
    var UpdatedCount = 0
    var OnlineCount = 0
    var ActionCount = 0
    var Categories: [HomeCategorySection] = []

    static func Build(_ Games: [Game]) -> Self {
        let Ranked = Games.sorted { ($0.Weight ?? 0) > ($1.Weight ?? 0) }
        let Updated = Games.filter { $0.LatestUpdate != nil }
            .sorted { ($0.LatestUpdate ?? "") > ($1.LatestUpdate ?? "") }
        let Online = Games.filter(\.Online)
        let Names = Set(Games.flatMap(\.Categories)).sorted()
        let Categories = ["Action", "Adventure", "Survival", "Simulation", "Strategy", "Sports"].compactMap { Name -> HomeCategorySection? in
            guard let Matched = Names.first(where: { $0.caseInsensitiveCompare(Name) == .orderedSame }) else { return nil }
            let Matches = Games.filter { $0.Categories.contains { $0.caseInsensitiveCompare(Matched) == .orderedSame } }
            return HomeCategorySection(Name: Matched, Count: Matches.count, Preview: Array(Matches.prefix(4)))
        }
        let Action = Games.filter { $0.Categories.contains { $0.caseInsensitiveCompare("Action") == .orderedSame } }
        return Self(Highlights: Array(Ranked.lazy.filter { $0.ArtworkURL != nil }.prefix(7)),
                    Top: Array(Ranked.prefix(12)), TVFeatured: Array(Ranked.prefix(24)),
                    Updated: Array(Updated.prefix(12)),
                    Online: Array(Online.prefix(12)), Action: Array(Action.prefix(12)),
                    UpdatedCount: Updated.count, OnlineCount: Online.count,
                    ActionCount: Action.count, Categories: Categories)
    }
}

@MainActor
final class AppStore: ObservableObject {
    private struct GameFilterKey: Equatable {
        let Revision: Int
        let Query: String
        let Genre: String
        let Sort: String
        let OnlineOnly: Bool
        let DlcOnly: Bool
        let VerifiedOnly: Bool
        let Provider: String
        let MaximumSizeGB: Double
        let VerifiedRevision: Int
    }

    @Published var Route: AppRoute = .Home
    @Published var Games: [Game] = [] { didSet { CatalogRevision += 1 } }
    var HomeCatalog = HomeCatalogSnapshot()
    @Published var Library: [LibraryGame] = []
    @Published var Downloads: [DownloadItem] = []
    @Published var TorrentJobs: [TorrentJobStatus] = []
    @Published var Wishlist: Set<String> = []
    @Published var SearchQuery = ""
    @Published var SelectedGenre = "All genres"
    @Published var SortOrder = "Relevance"
    @Published var SelectedGame: Game?
    @Published var SelectedLibraryId: UUID?
    @Published var Settings = AppSettings() {
        didSet { Theme.Name = Settings.Theme }
    }
    @Published var IsLoading = false
    @Published var CatalogWarning: String?
    @Published var ErrorMessage: String?
    @Published var GameFailure: GameFailureReport?
    @Published var Reinstall: ReinstallRequest?
    @Published private(set) var AvailableGameUpdates: [UUID: Game] = [:]
    @Published var Notice: String?
    @Published var ShowingWelcome = false
    @Published var ShowingBigPicture = false
    @Published var CatalogMetadata: Ascendara.CatalogMetadata = .init()
    @Published var RunningIds: Set<UUID> = []
    @Published private(set) var BusyGameIds: Set<UUID> = []
    @Published var VerifiedIds: Set<String> = [] { didSet { VerifiedRevision += 1 } }
    @Published var OnlineOnly = false
    @Published var DlcOnly = false
    @Published var VerifiedOnly = false
    @Published var SelectedProvider = "All providers"
    @Published var MaximumSizeGB: Double = 0
    @Published var ResolvingGameIds: Set<String> = []
    @Published private(set) var MacCompatibilityBySteamId: [String: MacCompatibility] = [:]

    let Catalog = CatalogService(CacheDirectory: AppPaths.Support.appendingPathComponent("CatalogCache"))
    let LibraryStore: LibraryService
    let DownloadStore: DownloadService
    let Launcher: GameLauncher
    let Compatibility = CompatibilityService()
    let MacCompatibilityLookup = MacCompatibilityService()
    let AchievementWatcher = AchievementWatcherService()
    let Notifications = NotificationService()
    private var SizeTask: Task<Void, Never>?
    private var AutomaticUpdateTask: Task<Void, Never>?
    private var Observers: Set<AnyCancellable> = []
    private var CatalogTask: Task<Void, Never>?
    private var DidStart = false
    private var SleepActivity: NSObjectProtocol?
    private var AchievementTimer: Timer?
    private var TorrentTimer: Timer?
    private var AchievementScanInProgress = false
    private var LastDownloadPublish = Date.distantPast
    private var CatalogRevision = 0
    private var VerifiedRevision = 0
    private var CachedFilter: (GameFilterKey, [Game])?
    private var CachedGenres: (Int, [String])?
    private var CachedProviders: (Int, [String])?
    private var HandledTorrentJobs: Set<UUID> = []
    private var PendingGameId: String?
    private let SettingsURL = AppPaths.Support.appendingPathComponent("Settings.json")
    private let WishlistURL = AppPaths.Support.appendingPathComponent("Wishlist.json")
    private var SavedSettings = AppSettings()

    var CurrentRoute: AppRoute {
        get { Route }
        set { Route = newValue }
    }

    init() {
        if UserDefaults.standard.double(forKey: "NativeProfileCreatedAt") == 0 {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "NativeProfileCreatedAt")
        }
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
        SavedSettings = Settings
        Route = AppRoute(rawValue: Settings.DefaultPage) ?? .Home
        Theme.Name = Settings.Theme
        ShowingWelcome = !Settings.HasCompletedWelcome
        LibraryStore.$Games.sink { [weak self] in self?.Library = $0 }.store(in: &Observers)
        LibraryStore.$ErrorMessage.compactMap { $0 }.sink { [weak self] in self?.ErrorMessage = $0 }.store(in: &Observers)
        DownloadStore.$Downloads.sink { [weak self] in self?.DownloadsChanged($0) }.store(in: &Observers)
        DownloadStore.$ErrorMessage.compactMap { $0 }.sink { [weak self] in self?.ErrorMessage = $0 }.store(in: &Observers)
        DownloadStore.OnCompleted = { [weak self] Download in self?.DownloadCompleted(Download) }
        Launcher.$RunningIds.sink { [weak self] Ids in
            let Previous = self?.RunningIds ?? []
            self?.RunningIds = Ids
            self?.UpdateSleepActivity()
            self?.UpdateAchievementTimer(RunningIds: Ids)
            if !Previous.subtracting(Ids).isEmpty {
                self?.ProcessPendingInstallations()
                self?.CheckGameUpdates()
            }
        }.store(in: &Observers)
        Launcher.$ErrorMessage.compactMap { $0 }.sink { [weak self] in self?.ErrorMessage = $0 }.store(in: &Observers)
        Launcher.$Failure.compactMap { $0 }.sink { [weak self] Failure in
            self?.GameFailure = Failure
            self?.Notifications.Post("Game closed unexpectedly", Message: "\(Failure.GameName): \(Failure.Summary)", Kind: "failure")
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)
        }.store(in: &Observers)
        Launcher.OnSessionEnded = { [weak self] Id, StartedAt, Seconds in
            do { try self?.LibraryStore.RecordSession(Id, StartedAt: StartedAt, Seconds: Seconds) }
            catch { self?.Report(error) }
        }
        Launcher.OnSessionProgress = { [weak self] gameId, sessionId, startedAt, totalSeconds, summary in
            do {
                try self?.LibraryStore.RecordManagedSession(gameId, SessionId: sessionId,
                    StartedAt: startedAt, TotalSeconds: totalSeconds, Summary: summary)
            } catch { self?.Report(error) }
        }
        Launcher.RestoreSessions(KnownGameIds: Set(LibraryStore.Games.map(\.Id)))
    }

    var Genres: [String] {
        if let CachedGenres, CachedGenres.0 == CatalogRevision { return CachedGenres.1 }
        let Values = ["All genres"] + Set(Games.flatMap(\.Categories)).sorted()
        CachedGenres = (CatalogRevision, Values)
        return Values
    }
    var Providers: [String] {
        if let CachedProviders, CachedProviders.0 == CatalogRevision { return CachedProviders.1 }
        let Values = ["All providers"] + Set(Games.flatMap { $0.DownloadLinks.keys }).sorted()
        CachedProviders = (CatalogRevision, Values)
        return Values
    }
    var FilteredGames: [Game] {
        let Key = GameFilterKey(Revision: CatalogRevision, Query: SearchQuery, Genre: SelectedGenre,
                                Sort: SortOrder, OnlineOnly: OnlineOnly, DlcOnly: DlcOnly,
                                VerifiedOnly: VerifiedOnly, Provider: SelectedProvider,
                                MaximumSizeGB: MaximumSizeGB, VerifiedRevision: VerifiedRevision)
        if let CachedFilter, CachedFilter.0 == Key { return CachedFilter.1 }
        let Sort: CatalogSort
        switch SortOrder {
        case "Name A–Z", "Name", "A–Z": Sort = .Name
        case "Recently updated", "Recent", "Newest": Sort = .Recent
        case "Smallest size", "Size": Sort = .Smallest
        default: Sort = .Popular
        }
        let Values = GameSearch.Filter(Games: Games, Query: SearchQuery,
                                 Categories: SelectedGenre == "All genres" ? [] : [SelectedGenre], Sort: Sort,
                                 OnlineOnly: OnlineOnly, DlcOnly: DlcOnly,
                                 MaximumSizeGB: MaximumSizeGB > 0 ? MaximumSizeGB : nil,
                                 Provider: SelectedProvider == "All providers" ? nil : SelectedProvider,
                                 VerifiedIds: VerifiedOnly ? VerifiedIds : nil)
        CachedFilter = (Key, Values)
        return Values
    }
    var WishlistGames: [Game] { Games.filter { Wishlist.contains($0.Id) } }
    var ActiveDownloadCount: Int {
        Downloads.filter(\.IsActive).count + TorrentJobs.filter { !$0.IsTerminal && $0.State != "Paused" }.count
    }

    func Start() {
        guard !DidStart else { return }
        DidStart = true
        ApplySettings()
        UpdateAchievementTimer(RunningIds: Launcher.RunningIds)
        RefreshTorrentJobs()
        Task {
            MacCompatibilityBySteamId = await MacCompatibilityLookup.LoadCached()
            let Updated = await MacCompatibilityLookup.Load()
            if !Updated.isEmpty { MacCompatibilityBySteamId = Updated }
        }
        if Settings.AutoExtract {
            for Download in Downloads where Download.State == .Completed &&
                Download.ErrorMessage == "Extraction failed: Archives containing links or special files are not extracted automatically." &&
                FileManager.default.fileExists(atPath: Download.FileURL.path) {
                DownloadCompleted(Download)
            }
        }
        if Settings.HasCompletedWelcome { RefreshCatalog(Force: false) }
        SizeTask = Task {
            for Game in LibraryStore.Games where Game.InstalledSizeBytes == nil && Game.IsInstalled {
                if Task.isCancelled { break }
                try? await LibraryStore.MeasureSize(Game.Id)
            }
        }
        for Download in Downloads where Download.State == .Extracted && !Download.ImportCompleted { DownloadCompleted(Download) }
    }

    private func UpdateAchievementTimer(RunningIds: Set<UUID>) {
        guard DidStart, !RunningIds.isEmpty else {
            AchievementTimer?.invalidate()
            AchievementTimer = nil
            return
        }
        guard AchievementTimer == nil else { return }
        AchievementTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.Launcher.RunningIds.isEmpty, !self.AchievementScanInProgress else { return }
                self.AchievementScanInProgress = true
                defer { self.AchievementScanInProgress = false }
                let Unlocks = await self.AchievementWatcher.Scan(Games: self.LibraryStore.Games,
                    Catalog: self.Games, RunningIds: self.Launcher.RunningIds)
                for Unlock in Unlocks {
                    self.Notice = "Achievement unlocked in \(Unlock.GameName): \(Unlock.AchievementName)"
                    self.Notifications.Post("Achievement unlocked", Message: "\(Unlock.GameName): \(Unlock.AchievementName)", Kind: "achievement")
                }
            }
        }
        AchievementTimer?.tolerance = 0.4
    }

    private func UpdateTorrentTimer() {
        let Interval: TimeInterval = TorrentJobs.contains(where: { !$0.IsTerminal && $0.State != "Paused" })
            ? 1 : TorrentJobs.contains(where: { !$0.IsTerminal }) ? 5 : 0
        guard Interval > 0 else {
            TorrentTimer?.invalidate()
            TorrentTimer = nil
            return
        }
        if TorrentTimer?.timeInterval == Interval { return }
        TorrentTimer?.invalidate()
        TorrentTimer = Timer.scheduledTimer(withTimeInterval: Interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.RefreshTorrentJobs()
            }
        }
        TorrentTimer?.tolerance = Interval * 0.2
    }

    func MacCompatibility(for Game: Game) -> MacCompatibility? {
        MacCompatibility(for: Game.SteamId)
    }

    func MacCompatibility(for SteamId: String?) -> MacCompatibility? {
        guard let SteamId else { return nil }
        return MacCompatibilityBySteamId[SteamId]
    }

    func RefreshCatalog(Force: Bool = true) {
        CatalogTask?.cancel()
        CatalogTask = Task {
            IsLoading = true
            defer { if !Task.isCancelled { IsLoading = false } }
            do {
                let Source = try ActiveCatalogSource()
                let Snapshot = try await Catalog.Load(Source: Source, Force: Force)
                try Task.checkCancellation()
                let Blocked = Set(Settings.BlacklistedGameIds)
                let LoadedGames = Snapshot.Games.filter { !Blocked.contains($0.Id) }
                let Home = await Task.detached(priority: .userInitiated) {
                    HomeCatalogSnapshot.Build(LoadedGames)
                }.value
                try Task.checkCancellation()
                HomeCatalog = Home
                Games = LoadedGames
                CatalogMetadata = Snapshot.Metadata
                CatalogWarning = Snapshot.Warning
                CheckGameUpdates()
                if let Latest = Snapshot.Metadata.AppVersion, VersionComparison.IsNewer(Latest, than: AppVersion.Current) {
                    Notifications.Post("App update available", Message: "Ascendara \(Latest) is listed in the game index.", Kind: "update")
                }
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
            Updated.LaunchMode = LibraryService.DefaultLaunchMode(for: URL)
            Updated.InstalledSizeBytes = nil; Updated.SizeMeasuredAt = nil
            try LibraryStore.Update(Updated)
            Task { try? await LibraryStore.MeasureSize(Game.Id) }
        } catch { Report(error) }
    }
    func LaunchGame(_ Game: LibraryGame) {
        guard BusyGameIds.insert(Game.Id).inserted else { return }
        var Game = Game
        let UseBundledRunner = Game.LaunchMode == .Wine && Compatibility.FindWine() == nil
            && Compatibility.FindHighball() != nil
            && LibraryService.DefaultLaunchMode(for: Game.ExecutableURL) == .Highball
        if UseBundledRunner { Game.LaunchMode = .Highball }
        if Game.LaunchArguments.isEmpty {
            Game.LaunchArguments = Settings.LaunchArguments.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        Task {
            defer { BusyGameIds.remove(Game.Id) }
            do {
                try await Launcher.Launch(Game)
                if UseBundledRunner, var Updated = LibraryStore.Games.first(where: { $0.Id == Game.Id }) {
                    Updated.LaunchMode = .Highball
                    try LibraryStore.Update(Updated)
                }
                try LibraryStore.RecordLaunch(Game.Id)
                if Settings.HideOnGameLaunch { NSApp.hide(nil) }
            } catch is GameLaunchFailure {  }
            catch { Report(error) }
        }
    }
    func StopGame(_ Game: LibraryGame) {
        guard BusyGameIds.insert(Game.Id).inserted else { return }
        Task {
            defer { BusyGameIds.remove(Game.Id) }
            do { try await Launcher.Stop(Game.Id) } catch { Report(error) }
        }
    }
    func RevealGame(_ Game: LibraryGame) { NSWorkspace.shared.activateFileViewerSelecting([Game.ExecutableURL]) }
    func RemoveGame(_ Game: LibraryGame) {
        let FilesURL = LibraryStore.RemovableFilesURL(for: Game, Downloads: DownloadStore.Downloads)
        let SharesFiles = FilesURL.map { Root in
            LibraryStore.Games.contains { $0.Id != Game.Id && RuntimePaths.IsInside($0.ExecutableURL, Root) }
        } ?? false
        let CanMoveFiles = FilesURL != nil && !SharesFiles && !IsRunning(Game) && !BusyGameIds.contains(Game.Id)
        let Alert = NSAlert()
        Alert.messageText = "Remove \(Game.Name) from your library?"
        if let FilesURL {
            Alert.informativeText = SharesFiles
                ? "Another library game uses this folder. You can remove this entry, but its files must stay."
                : IsRunning(Game) ? "Stop the game before moving its files to Trash."
                : "Keep the game files, or move this folder to Trash:\n\(FilesURL.path)"
        } else {
            Alert.informativeText = "Ascendara did not install these files, so it will leave them in place. You can remove this library entry."
        }
        Alert.addButton(withTitle: "Remove from Library")
        let MoveFilesButton = Alert.addButton(withTitle: "Move Files to Trash")
        MoveFilesButton.isEnabled = CanMoveFiles
        Alert.addButton(withTitle: "Cancel")
        let Choice = Alert.runModal()
        guard Choice == .alertFirstButtonReturn || Choice == .alertSecondButtonReturn else { return }
        do {
            try LibraryStore.Remove(Game.Id, DeleteFiles: Choice == .alertSecondButtonReturn,
                                    Downloads: DownloadStore.Downloads)
        } catch { Report(error) }
    }

    func StartDownload(_ Game: Game, Link: String, Installation: InstallationPlan? = nil, Interactive: Bool = true) {
        if Installation == nil, let Installed = LibraryMatch(Game) {
            Reinstall = ReinstallRequest(Game: Game, Installed: Installed, Link: Link)
            return
        }
        if let Installation, RunningIds.contains(Installation.ReplaceGameId) || BusyGameIds.contains(Installation.ReplaceGameId) {
            ErrorMessage = "Stop the game before reinstalling it."; return
        }
        if let Installation, DownloadStore.Downloads.contains(where: { $0.Installation?.ReplaceGameId == Installation.ReplaceGameId && ![.Failed, .Cancelled].contains($0.State) }) {
            Notice = "A replacement installation is already in the download queue."; return
        }
        guard let URL = URL(string: Link) else { ErrorMessage = "This download link is invalid."; return }
        guard ResolvingGameIds.insert(Game.Id).inserted else { return }
        if URL.scheme?.lowercased() == "magnet" {
            if Installation != nil {
                ResolvingGameIds.remove(Game.Id)
                ErrorMessage = "Reinstalling from a torrent requires downloading it first, then choosing its installed executable in Game options. Choose a direct mirror for a managed reinstall."
                return
            }
            Task {
                defer { ResolvingGameIds.remove(Game.Id) }
                do {
                    try await TorrentService.Add(URL: URL, Settings: Settings,
                        GameName: Game.Name,
                        EstimatedSizeBytes: Game.SizeGB > 0 ? Int64(Game.SizeGB * 1_073_741_824) : nil)
                    RefreshTorrentJobs()
                    SelectedGame = nil
                    Route = .Downloads
                    Notice = "\(Game.Name) was added to the torrent queue."
                } catch { Report(error) }
            }
            return
        }
        Task {
            defer { ResolvingGameIds.remove(Game.Id) }
            let Priority = ["gofile", "pixeldrain", "megadb", "buzzheavier", "fileditch", "datanodes", "vikingfile", "1fichier"]
            let Mirrors: [String] = Game.DownloadLinks.keys.sorted {
                let Left = Priority.firstIndex(of: $0.lowercased()) ?? Priority.count
                let Right = Priority.firstIndex(of: $1.lowercased()) ?? Priority.count
                return Left == Right ? $0 < $1 : Left < Right
            }.flatMap { Game.DownloadLinks[$0] ?? [] }
            var Seen: Set<String> = []
            let CandidateAddresses: [String] = [Link] + (Game.Id.hasPrefix("direct-") ? [String]() : Mirrors)
            let Candidates = CandidateAddresses.compactMap { Address -> URL? in
                guard Seen.insert(Address).inserted, let Candidate = Foundation.URL(string: Address),
                      ["http", "https"].contains(Candidate.scheme?.lowercased() ?? "") else { return nil }
                return Candidate
            }
            var Files: [ResolvedDownload]?
            var SelectedMirror: URL?
            var LastError: Error?
            for Candidate in Candidates {
                do {
                    Files = try await DownloadLinkResolver.Resolve(URL: Candidate, Interactive: Interactive)
                    SelectedMirror = Candidate
                    break
                } catch is CancellationError { return }
                catch { LastError = error }
            }
            guard let Files else {
                Report(LastError ?? AppFailure.Message("No direct download mirror is available for this game."))
                return
            }
            var StartedIds: [UUID] = []
            do {
                let BatchId = UUID()
                let Directory = URLFromPath(Settings.DownloadDirectory)
                    .appendingPathComponent(RuntimePaths.SafeName(Game.Name), isDirectory: true)
                    .appendingPathComponent(String(BatchId.uuidString.prefix(8)), isDirectory: true)
                var KnownSizes = await DownloadLinkResolver.ContentLengths(Files)
                if Files.count == 1, KnownSizes[0] == nil, Game.SizeGB > 0, Game.SizeGB < Double(Int64.max) / 1_073_741_824 {
                    KnownSizes[0] = Int64(Game.SizeGB * 1_073_741_824)
                }
                let Required = KnownSizes.compactMap { $0 }.reduce(Int64(0)) { Total, Size in
                    let (Next, Overflow) = Total.addingReportingOverflow(max(0, Size))
                    return Overflow ? Int64.max : Next
                }
                try DownloadStore.CheckCapacity(at: Directory, Required: Required)
                for (Index, File) in Files.enumerated() {
                    let Id = try DownloadStore.Start(Name: Game.Name, URL: File.URL, DestinationDirectory: Directory,
                                                CatalogId: Game.Id, FileName: File.FileName, BatchId: BatchId,
                                                Version: Game.Version, RequestHeaders: File.Headers,
                                                RequestCookies: File.Cookies, EstimatedBytes: KnownSizes[Index], Installation: Installation)
                    StartedIds.append(Id)
                }
                SelectedGame = nil
                Route = .Downloads
                if SelectedMirror != URL { Notice = "The selected host was unavailable. Ascendara started another mirror automatically." }
            } catch {
                for Id in StartedIds { try? DownloadStore.Cancel(Id) }
                Report(error)
            }
        }
    }
    func StartDirectDownload(Name: String, Link: String) {
        StartDownload(Game(Id: "direct-\(UUID().uuidString)", Name: Name.isEmpty ? "Download" : Name), Link: Link)
    }
    func PauseDownload(_ Download: DownloadItem) { do { try DownloadStore.Pause(Download.Id) } catch { Report(error) } }
    func RefreshDownloadProgress() { DownloadStore.RefreshProgress() }
    func ResumeDownload(_ Download: DownloadItem) { do { try DownloadStore.Resume(Download.Id) } catch { Report(error) } }
    func CancelDownload(_ Download: DownloadItem) { do { try DownloadStore.Cancel(Download.Id) } catch { Report(error) } }
    func RemoveDownload(_ Download: DownloadItem) {
        let Alert = NSAlert()
        Alert.messageText = "Remove \(Download.Name) from Downloads?"
        Alert.informativeText = "You can keep the downloaded archive and extracted game files, or move both to the Trash."
        Alert.addButton(withTitle: "Remove, Keep Files")
        Alert.addButton(withTitle: "Move Files to Trash")
        Alert.addButton(withTitle: "Cancel")
        switch Alert.runModal() {
        case .alertFirstButtonReturn:
            do { try DownloadStore.Remove(Download.Id, DeleteFiles: false) } catch { Report(error) }
        case .alertSecondButtonReturn:
            do { try DownloadStore.Remove(Download.Id, DeleteFiles: true) } catch { Report(error) }
        default: break
        }
    }
    func ControlTorrent(_ Job: TorrentJobStatus, Operation: String) {
        do { try TorrentService.ControlJob(Job.Id, Operation: Operation); RefreshTorrentJobs() }
        catch { Report(error) }
    }
    func RevealTorrent(_ Job: TorrentJobStatus) {
        if let Path = Job.ResultDirectory { NSWorkspace.shared.open(URL(fileURLWithPath: Path)) }
        else { NSWorkspace.shared.open(URLFromPath(Settings.DownloadDirectory)) }
    }
    func ImportTorrent(_ Job: TorrentJobStatus) {
        guard let Path = Job.ResultDirectory else { return }
        let Directory = URL(fileURLWithPath: Path, isDirectory: true)
        let Panel = NSOpenPanel()
        Panel.title = "Select the game executable"
        Panel.directoryURL = Directory
        guard Panel.runModal() == .OK, let Executable = Panel.url else { return }
        do {
            let CatalogGame = Games.first { $0.Name.localizedCaseInsensitiveCompare(Job.GameName) == .orderedSame }
            _ = try LibraryStore.ImportGame(Name: Job.GameName, ExecutableURL: Executable,
                CatalogId: CatalogGame?.Id, ImageURL: CatalogGame?.ArtworkURL?.absoluteString)
            Route = .Library
        } catch { Report(error) }
    }
    private func RefreshTorrentJobs() {
        let Jobs = TorrentService.ListJobs()
        if Jobs != TorrentJobs { TorrentJobs = Jobs }
        UpdateTorrentTimer()
        for Job in Jobs where Job.IsTerminal && HandledTorrentJobs.insert(Job.Id).inserted {
            switch Job.State {
            case "Completed":
                if let Path = Job.ResultDirectory,
                   let Executable = try? LibraryStore.BestExecutable(in: URL(fileURLWithPath: Path), GameName: Job.GameName) {
                    do {
                        let CatalogGame = Games.first { $0.Name.localizedCaseInsensitiveCompare(Job.GameName) == .orderedSame }
                        _ = try LibraryStore.ImportGame(Name: Job.GameName, ExecutableURL: Executable,
                            CatalogId: CatalogGame?.Id, ImageURL: CatalogGame?.ArtworkURL?.absoluteString)
                        Notice = "\(Job.GameName) is ready to play in your library."
                    } catch { Report(error) }
                } else { Notice = "\(Job.GameName) finished downloading. Choose its executable to add it to your library." }
            case "ManualInstallRequired": Notice = "\(Job.GameName) needs its installer run manually."
            case "Failed": if let Message = Job.ErrorMessage { ErrorMessage = "\(Job.GameName): \(Message)" }
            default: break
            }
        }
        UpdateSleepActivity()
    }
    func RevealDownload(_ Download: DownloadItem) {
        let Location = Download.ExtractedPath.map(URLFromPath) ?? Download.FileURL
        if FileManager.default.fileExists(atPath: Location.path) {
            NSWorkspace.shared.activateFileViewerSelecting([Location])
        } else {
            NSWorkspace.shared.open(Download.DestinationDirectory)
        }
    }
    func ExtractDownload(_ Download: DownloadItem) {
        Task {
            do { _ = try await DownloadStore.Extract(Download.Id, SpaceSaving: Settings.SpaceSavingExtraction,
                Directory: Settings.ExtractionDirectory.isEmpty ? nil : URLFromPath(Settings.ExtractionDirectory)) }
            catch { Notifications.Post("Extraction failed", Message: "\(Download.Name): \(error.localizedDescription)", Kind: "failure"); Report(error) }
        }
    }
    func ImportDownload(_ Download: DownloadItem) {
        let Panel = NSOpenPanel()
        Panel.title = "Select the game executable"
        Panel.directoryURL = Download.ExtractedPath.map(URLFromPath) ?? Download.DestinationDirectory
        guard Panel.runModal() == .OK, let URL = Panel.url else { return }
        do {
            let CatalogGame = Games.first { $0.Id == Download.CatalogId }
            if let Plan = Download.Installation, let Path = Download.ExtractedPath {
                guard !RunningIds.contains(Plan.ReplaceGameId), !BusyGameIds.contains(Plan.ReplaceGameId) else {
                    throw RuntimeError.Message("Stop the game before replacing its installation.")
                }
                let Installed = try LibraryStore.ReplaceInstallation(Plan, From: Foundation.URL(fileURLWithPath: Path), Executable: URL, Version: Download.Version)
                try DownloadStore.CommitInstallation(Download.Id, Path: Installed.ManagedFilesPath ?? Installed.DirectoryPath)
                Route = .Library
                return
            }
            let ManagedDirectory = Download.ExtractedPath.map { URLFromPath($0) }
                .flatMap { RuntimePaths.IsInside(URL, $0) ? $0 : nil }
            _ = try LibraryStore.ImportGame(Name: Download.Name, ExecutableURL: URL, CatalogId: Download.CatalogId,
                                            ImageURL: CatalogGame?.ArtworkURL?.absoluteString, Version: Download.Version,
                                            ManagedDirectory: ManagedDirectory)
            if let Path = Download.ExtractedPath { try DownloadStore.CommitInstallation(Download.Id, Path: Path) }
            Route = .Library
        } catch { Report(error) }
    }
    private func DownloadsChanged(_ Values: [DownloadItem]) {
        guard Values != Downloads else { return }
        let StateChanged = Values.count != Downloads.count || zip(Values, Downloads).contains { Pair in
            Pair.0.Id != Pair.1.Id || Pair.0.State != Pair.1.State
        }
        if !StateChanged && Date().timeIntervalSince(LastDownloadPublish) <
            (Route == .Downloads && NSApp?.isActive == true ? 1.0 : 5.0) {
            return
        }
        LastDownloadPublish = Date()
        let PreviousDownloads = Downloads
        Downloads = Values
        for Item in Values where Item.State == .Failed && !PreviousDownloads.contains(where: { $0.Id == Item.Id && $0.State == .Failed }) {
            Notifications.Post("Download failed", Message: "\(Item.Name): \(Item.ErrorMessage ?? "Unknown error")", Kind: "failure")
        }
        UpdateSleepActivity()
    }
    private func DownloadCompleted(_ Download: DownloadItem) {
        if Download.State == .Completed { Notifications.Post("Download complete", Message: Download.Name, Kind: "download") }
        if Download.State == .Completed && (Settings.AutoExtract || Download.Installation != nil) {
            let Group = Download.BatchId.map { BatchId in DownloadStore.Downloads.filter { $0.BatchId == BatchId } } ?? [Download]
            guard Group.allSatisfy({ $0.State == .Completed || $0.State == .Extracted }) else { return }
            let Archives = Group.filter { File in
                let Name = File.FileName.lowercased()
                let IsLaterPart = Name.range(of: #"\.part(?!0*1\.)\d+\.rar$"#, options: .regularExpression) != nil
                return !IsLaterPart && (["zip", "7z", "rar", "tar", "gz", "bz2", "xz"].contains(File.FileURL.pathExtension.lowercased()) || Name.hasSuffix(".7z.001") || Name.hasSuffix(".zip.001"))
            }.sorted { $0.CreatedAt < $1.CreatedAt }
            if let Archive = Archives.first, Archive.State == .Completed { ExtractDownload(Archive) }
        } else if Download.State == .Extracted {
            if let Plan = Download.Installation, let Path = Download.ExtractedPath,
               !FileManager.default.fileExists(atPath: Path),
               let Installed = LibraryStore.Games.first(where: { $0.Id == Plan.ReplaceGameId && $0.ManagedFilesPath == Plan.DestinationPath && $0.Version == Download.Version }) {
                do { try DownloadStore.CommitInstallation(Download.Id, Path: Installed.ManagedFilesPath ?? Installed.DirectoryPath) }
                catch { Report(error) }
                return
            }
            if let Path = Download.ExtractedPath {
                do {
                    let Directory = URL(fileURLWithPath: Path, isDirectory: true)
                    if let Executable = try LibraryStore.BestExecutable(in: Directory, GameName: Download.Name) {
                        if let Plan = Download.Installation {
                            guard !RunningIds.contains(Plan.ReplaceGameId), !BusyGameIds.contains(Plan.ReplaceGameId) else {
                                Notice = "\(Download.Name) is ready to install. Stop the running game, then choose Finish installation in Downloads."
                                return
                            }
                            let Installed = try LibraryStore.ReplaceInstallation(Plan, From: Directory, Executable: Executable, Version: Download.Version)
                            try DownloadStore.CommitInstallation(Download.Id, Path: Installed.ManagedFilesPath ?? Installed.DirectoryPath)
                            AvailableGameUpdates.removeValue(forKey: Installed.Id)
                            Notifications.Post("Installation complete", Message: Installed.Name, Kind: "download")
                            Notice = "\(Installed.Name) has been reinstalled."
                            return
                        }
                        let CatalogGame = Games.first { $0.Id == Download.CatalogId }
                        _ = try LibraryStore.ImportGame(Name: Download.Name, ExecutableURL: Executable,
                                                        CatalogId: Download.CatalogId, ImageURL: CatalogGame?.ArtworkURL?.absoluteString,
                                                        Version: Download.Version, ManagedDirectory: Directory)
                        try DownloadStore.CommitInstallation(Download.Id, Path: Directory.path)
                        Notice = "\(Download.Name) is ready to play in your library."
                        Notifications.Post("Ready to play", Message: Download.Name, Kind: "download")
                        return
                    }
                } catch { Report(error); return }
            }
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
        Panel.canChooseDirectories = true
        Panel.allowedContentTypes = [.json]
        guard Panel.runModal() == .OK, let URL = Panel.url else { return }
        Settings.LocalCatalogPath = URL.path
        Settings.CatalogSource = "local"
        SaveSettings()
        RefreshCatalog()
    }
    func UseBundledCatalog() {
        guard let File = Bundle.main.url(forResource: "ascendara_games", withExtension: "json") else {
            ErrorMessage = "This build does not contain a bundled index. Import an ascendara_games.json file instead."
            return
        }
        Settings.LocalCatalogPath = File.path
        Settings.CatalogSource = "local"
        SaveSettings()
        RefreshCatalog()
    }
    func SaveSettings() {
        do {
            Settings.ConcurrentDownloads = min(8, max(1, Settings.ConcurrentDownloads))
            Settings.DownloadThreads = min(32, max(1, Settings.DownloadThreads))
            Settings.DownloadSpeedLimitKBps = max(0, Settings.DownloadSpeedLimitKBps)
            if Settings.TorBoxAPIKey != SavedSettings.TorBoxAPIKey { try KeychainService.Write(Settings.TorBoxAPIKey, For: "TorBoxAPIKey") }
            if Settings.QBitTorrentPassword != SavedSettings.QBitTorrentPassword { try KeychainService.Write(Settings.QBitTorrentPassword, For: "QBitTorrentPassword") }
            try AppPaths.Write(Settings.PublicCopy(), To: SettingsURL)
            SavedSettings = Settings
            ApplySettings()
        } catch { Report(error) }
    }
    private func ApplySettings() {
        Theme.Name = Settings.Theme
        Theme.Custom = Settings.CustomTheme
        I18n.Use(Settings.Language)
        Notifications.Configure(Settings)
        DownloadStore.MaximumConcurrentDownloads = Settings.ConcurrentDownloads
        DownloadStore.Configure(SingleStream: Settings.SingleStreamDownload,
                                Threads: Settings.DownloadThreads,
                                SpeedLimitKBps: Settings.DownloadSpeedLimitKBps)
        Compatibility.CustomWinePath = Settings.WinePath.isEmpty ? nil : Settings.WinePath
        Compatibility.CustomHighballPath = Settings.HighballPath.isEmpty ? nil : Settings.HighballPath
        UpdateSleepActivity()
    }
    private func UpdateSleepActivity() {
        let Needed = Settings.KeepAwake && (Downloads.contains(where: \.IsActive)
            || TorrentJobs.contains(where: { !$0.IsTerminal && $0.State != "Paused" }) || !RunningIds.isEmpty)
        if Needed && SleepActivity == nil {
            SleepActivity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason: "Ascendara is downloading or running a game")
        } else if !Needed, let Activity = SleepActivity {
            ProcessInfo.processInfo.endActivity(Activity)
            SleepActivity = nil
        }
    }
    func PrepareForExit() async {
        SizeTask?.cancel()
        AutomaticUpdateTask?.cancel()
        AchievementTimer?.invalidate()
        AchievementTimer = nil
        TorrentTimer?.invalidate()
        TorrentTimer = nil
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
        if Games.isEmpty { RefreshCatalog() }
    }

    func ReplayWelcome() {
        SelectedGame = nil
        ShowingBigPicture = false
        Settings.HasCompletedWelcome = false
        SaveSettings()
        ShowingWelcome = true
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
    func Report(_ Error: Error) {
        ErrorMessage = Error.localizedDescription
        Notifications.Post("Operation failed", Message: Error.localizedDescription, Kind: "failure")
    }
    func URLFromPath(_ Path: String) -> URL { URL(fileURLWithPath: (Path as NSString).expandingTildeInPath) }

    func FinishInstallation(_ Download: DownloadItem) { DownloadCompleted(Download) }

    private func ProcessPendingInstallations() {
        for Download in DownloadStore.Downloads where Download.State == .Extracted && Download.Installation != nil {
            DownloadCompleted(Download)
        }
    }

    func RequestReinstall(_ Installed: LibraryGame) {
        guard let Game = Games.first(where: { $0.Id == Installed.CatalogId }),
              let Link = Game.DownloadLinks.keys.sorted().flatMap({ Game.DownloadLinks[$0] ?? [] })
                .first(where: { ["http", "https"].contains(URL(string: $0)?.scheme?.lowercased() ?? "") }) else {
            ErrorMessage = "No direct download is available in the active index for this game."
            return
        }
        Reinstall = ReinstallRequest(Game: Game, Installed: Installed, Link: Link)
    }

    func CheckGameUpdates() {
        var Updates: [UUID: Game] = [:]
        for Installed in LibraryStore.Games {
            guard let Latest = Games.first(where: { $0.Id == Installed.CatalogId }),
                  let LatestVersion = Latest.Version, let InstalledVersion = Installed.Version,
                  VersionComparison.IsNewer(LatestVersion, than: InstalledVersion) else { continue }
            Updates[Installed.Id] = Latest
        }
        AvailableGameUpdates = Updates
        guard Settings.AutomaticallyCheckGameUpdates else { return }
        if !Updates.isEmpty { Notifications.Post("Game updates available", Message: "\(Updates.count) installed games have newer versions in the index.", Kind: "update") }
        guard AutomaticUpdateTask == nil else { return }
        AutomaticUpdateTask = Task {
            defer { AutomaticUpdateTask = nil }
            for Installed in LibraryStore.Games where Installed.AutomaticallyUpdate && Installed.IsManaged {
                guard !Task.isCancelled, let Latest = Updates[Installed.Id],
                      !RunningIds.contains(Installed.Id), !BusyGameIds.contains(Installed.Id),
                      !DownloadStore.Downloads.contains(where: { $0.Installation?.ReplaceGameId == Installed.Id && ![.Failed, .Cancelled].contains($0.State) }),
                      let Destination = Installed.ManagedFilesPath,
                      let Link = Latest.DownloadLinks.keys.sorted().flatMap({ Latest.DownloadLinks[$0] ?? [] })
                        .first(where: { ["http", "https"].contains(URL(string: $0)?.scheme?.lowercased() ?? "") }) else { continue }
                StartDownload(Latest, Link: Link, Installation: InstallationPlan(ReplaceGameId: Installed.Id, DestinationPath: Destination), Interactive: false)
                while ResolvingGameIds.contains(Latest.Id) && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(250)) }
            }
        }
    }

    func MeasureLibrary() {
        SizeTask?.cancel()
        SizeTask = Task {
            for Game in LibraryStore.Games where Game.IsInstalled {
                if Task.isCancelled { return }
                do { try await LibraryStore.MeasureSize(Game.Id) } catch { Report(error); return }
            }
            Notice = "Installed sizes refreshed."
        }
    }

    func MoveGame(_ Game: LibraryGame) {
        guard !RunningIds.contains(Game.Id), BusyGameIds.insert(Game.Id).inserted else { return }
        guard let Parent = ChooseFolder(Title: "Move \(Game.Name) to…") else { BusyGameIds.remove(Game.Id); return }
        Task {
            defer { BusyGameIds.remove(Game.Id) }
            do {
                try await LibraryStore.MoveInstallation(Game.Id, To: Parent.appendingPathComponent(RuntimePaths.SafeName(Game.Name)))
                Notice = "\(Game.Name) moved to \(Parent.path)."
            } catch { Report(error) }
        }
    }

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
        case .ShowWindow: NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
