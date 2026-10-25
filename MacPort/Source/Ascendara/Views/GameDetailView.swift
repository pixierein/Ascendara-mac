import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject private var Store: AppStore
    let Game: Game
    @State private var Details: GameDetails?
    @State private var Loading = false
    @State private var SelectedProvider = ""
    @State private var SelectedLink = ""
    @State private var DirectLink = ""
    @State private var ScreenshotIndex = 0
    @State private var Releases: [GameRelease] = []
    @State private var HistoryLoading = false
    @State private var HistoryError: String?
    @State private var ShowingHistory = false

    private var Providers: [String] {
        let Priority = ["gofile", "pixeldrain", "megadb", "buzzheavier", "fileditch", "datanodes", "vikingfile", "1fichier", "torrent"]
        return Game.DownloadLinks.keys.filter { !(Game.DownloadLinks[$0] ?? []).isEmpty }
            .sorted { Left, Right in
                let LeftRank = Priority.firstIndex(of: Left.lowercased()) ?? Priority.count
                let RightRank = Priority.firstIndex(of: Right.lowercased()) ?? Priority.count
                return LeftRank == RightRank ? Left < Right : LeftRank < RightRank
            }
    }
    private var Links: [String] { Game.DownloadLinks[SelectedProvider] ?? [] }
    private var Screenshots: [URL] { Details?.Screenshots ?? [] }
    private var Facts: [(String, String, String)] {
        var Items: [(String, String, String)] = []
        if let Size = Game.Size { Items.append(("DOWNLOAD SIZE", Size, "externaldrive")) }
        if let Size = Store.LibraryMatch(Game)?.InstalledSizeBytes {
            Items.append(("INSTALLED SIZE", ByteCountFormatter.string(fromByteCount: Size, countStyle: .file), "internaldrive"))
        }
        if let Version = Game.Version { Items.append(("VERSION", Version, "tag")) }
        if let Updated = Game.LatestUpdate { Items.append(("LAST UPDATED", Updated, "calendar")) }
        if let Date = Details?.ReleaseDate { Items.append(("RELEASED", Date, "calendar.badge.clock")) }
        return Items
    }

    var body: some View {
        GeometryReader { Geometry in
            let Compact = Geometry.size.width < 1210
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Toolbar
                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 22) {
                            Hero(Compact: Compact)
                            About
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 18) {
                            CompatibilityPanel
                            DownloadPanel
                            Requirements
                        }
                        .frame(width: Compact ? 285 : min(360, Geometry.size.width * 0.28))
                    }
                    if !Screenshots.isEmpty || Loading { ScreenshotGallery }
                    RatingsView(Game: Game)
                    if Game.HasHistory { ReleaseHistory }
                    Attribution
                }
                .padding(.horizontal, Compact ? 22 : 30)
                .padding(.top, 22)
                .padding(.bottom, 120)
                .frame(maxWidth: 1580)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Theme.Background)
        .foregroundStyle(Theme.Foreground)
        .overlay(alignment: .topLeading) {
            Button { Store.SelectedGame = nil } label: {
                Label(I18n.T("Back"), systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14).frame(height: 38)
                    .background(Theme.Card, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel(I18n.T("Back to games"))
            .padding(.leading, 30).padding(.top, 15)
            .zIndex(10)
        }
        .task(id: Game.Id) {
            SelectedProvider = Providers.first ?? ""
            SelectedLink = Links.first ?? ""
            ScreenshotIndex = 0
            Details = nil
            Loading = true
            Details = await Store.LoadGameDetails(Game)
            Loading = false
        }
        .onChange(of: SelectedProvider) { _, _ in SelectedLink = Links.first ?? "" }
    }

    private var Toolbar: some View {
        HStack(spacing: 10) {
            Spacer()
            Button { Store.ToggleWishlist(Game) } label: {
                Label(Store.Wishlist.contains(Game.Id) ? "Saved to Play Later" : "Play Later",
                      systemImage: Store.Wishlist.contains(Game.Id) ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(SecondaryButtonStyle())
            ShareLink(item: Game.Name) {
                Label(I18n.T("Share"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(SecondaryButtonStyle())
            Button { Store.OpenExternal("https://github.com/pixierein/ascendara/issues/new") } label: {
                Label(I18n.T("Report an issue"), systemImage: "flag")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .font(.system(size: 12))
    }

    private func Hero(Compact: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                GameArtwork(URL: Details?.HeaderURL ?? Game.ArtworkURL, Name: Game.Name, CornerRadius: 0)
                LinearGradient(colors: [.black.opacity(0.04), .black.opacity(0.12), .black.opacity(0.88)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .bottom, spacing: 18) {
                        if let HeaderURL = Details?.HeaderURL, HeaderURL != Game.ArtworkURL {
                            GameArtwork(URL: Game.ArtworkURL, Name: Game.Name, CornerRadius: 9)
                                .frame(width: Compact ? 93 : 118, height: Compact ? 112 : 142)
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.3)))
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 9) {
                                Text(Game.Name)
                                    .font(.system(size: Compact ? 29 : 35, weight: .bold))
                                    .lineLimit(2)
                                if Store.VerifiedIds.contains(Game.Id) {
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 17))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .accessibilityLabel(I18n.T("Verified catalogue entry"))
                                }
                            }
                            HStack(spacing: 8) {
                                if let Version = Game.Version { HeroTag(Version) }
                                if Game.Online { HeroTag("ONLINE", Symbol: "gamecontroller") }
                                if Game.Dlc { HeroTag("DLC INCLUDED", Symbol: "gift") }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    if !Game.Categories.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Game.Categories.prefix(5), id: \.self) { Category in
                                HeroTag(Category)
                            }
                        }
                    }
                }
                .padding(Compact ? 20 : 25)
                .foregroundStyle(.white)
            }
            .frame(height: Compact ? 295 : 370)
            if !Facts.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: Compact ? 2 : 4), spacing: 1) {
                    ForEach(Array(Facts.enumerated()), id: \.offset) { _, Fact in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(Fact.0, systemImage: Fact.2)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.SecondaryText)
                            Text(Fact.1)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                        .padding(14)
                        .background(Theme.Muted.opacity(0.25))
                    }
                }
            }
        }
        .background(Theme.Card, in: RoundedRectangle(cornerRadius: 15))
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.Border.opacity(0.7)))
    }

    private func HeroTag(_ Title: String, Symbol: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let Symbol { Image(systemName: Symbol) }
            Text(I18n.T(Title)).lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.black.opacity(0.48), in: Capsule())
    }

    private var About: some View {
        Panel(Padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                Text(I18n.T("About This Game")).font(.system(size: 21, weight: .semibold))
                if Loading { ProgressView().controlSize(.small) }
                Text(Details?.Description ?? Details?.Summary ?? Game.Description ?? "No description is available for this game.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.SecondaryText)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let Website = Details?.WebsiteURL {
                    Button(I18n.T("Official website ↗")) { Store.OpenExternal(Website.absoluteString) }
                        .buttonStyle(MotionButtonStyle())
                        .foregroundStyle(Theme.Accent)
                }
                if let Details {
                    Divider()
                    HStack(alignment: .top, spacing: 20) {
                        if !Game.Categories.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                DetailLabel("CATEGORIES")
                                FlowCategories
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: 15) {
                            if !Details.Developers.isEmpty {
                                DetailMetadata("DEVELOPERS", Details.Developers.joined(separator: ", "))
                            }
                            if !Details.Publishers.isEmpty {
                                DetailMetadata("PUBLISHERS", Details.Publishers.joined(separator: ", "))
                            }
                            if !Details.Platforms.isEmpty {
                                DetailMetadata("PLATFORMS", Details.Platforms.joined(separator: ", "))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var FlowCategories: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Game.Categories.Chunked(into: 3), id: \.self) { Row in
                HStack(spacing: 6) {
                    ForEach(Row, id: \.self) { Category in
                        Text(Category)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Theme.Muted.opacity(0.65), in: Capsule())
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func DetailLabel(_ Title: String) -> some View {
        Text(I18n.T(Title))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.SecondaryText)
    }

    private func DetailMetadata(_ Title: String, _ Value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            DetailLabel(Title)
            Text(I18n.T(Value)).font(.system(size: 12)).textSelection(.enabled)
        }
    }

    private var CompatibilityPanel: some View {
        Panel(Padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Label(I18n.T("Mac compatibility"), systemImage: "desktopcomputer")
                    .font(.system(size: 15, weight: .semibold))
                if let Report = Store.MacCompatibility(for: Game) {
                    Label(Report.Label, systemImage: Report.IsPrediction ? "questionmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Report.Label == "Mac: Works" ? Color.green : Color.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background((Report.Label == "Mac: Works" ? Color.green : Color.cyan).opacity(0.12), in: Capsule())
                    Text(Report.Evidence)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.SecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(MacCompatibility.Attribution)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.SecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(I18n.T("View compatibility source ↗")) {
                        Store.OpenExternal(Report.SourceURL.absoluteString)
                    }
                    .buttonStyle(MotionButtonStyle())
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Accent)
                    if Report.IsPrediction {
                        Button(I18n.T("How this is estimated ↗")) {
                            Store.OpenExternal(MacCompatibility.AttributionURL.absoluteString)
                        }
                        .buttonStyle(MotionButtonStyle())
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Accent)
                    }
                } else {
                    Text(I18n.T("No Mac compatibility report yet"))
                        .font(.system(size: 12, weight: .medium))
                    Text(I18n.T("Compatibility depends on the game and runtime. Check community reports before downloading."))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.SecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var DownloadPanel: some View {
        Panel(Padding: 20) {
            VStack(alignment: .leading, spacing: 15) {
                Label(I18n.T("Download and play"), systemImage: "bolt.fill")
                    .font(.system(size: 17, weight: .semibold))
                if let Installed = Store.LibraryMatch(Game) {
                    Label(I18n.T("In your library"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                    let Running = Store.IsRunning(Installed)
                    Button {
                        if Running { Store.StopGame(Installed) }
                        else { Store.LaunchGame(Installed) }
                    } label: {
                        Label(Store.BusyGameIds.contains(Installed.Id) ? "Launching…" : Running ? "Stop game" : "Play game",
                              systemImage: Store.BusyGameIds.contains(Installed.Id) ? "hourglass" : Running ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(Store.BusyGameIds.contains(Installed.Id) || (!Running && !Installed.IsInstalled))
                    Button(I18n.T("Show game files")) { Store.RevealGame(Installed) }
                    Button(I18n.T("Reinstall…")) { Store.RequestReinstall(Installed) }.disabled(Running)
                        .buttonStyle(SecondaryButtonStyle())
                    if !Installed.IsInstalled {
                        Text(I18n.T("Game file missing. Update its location in Library."))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.SecondaryText)
                    }
                    Divider()
                } else {
                    Button(I18n.T("Already installed? Add to library…")) { Store.ImportGame(For: Game) }
                        .buttonStyle(MotionButtonStyle())
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Accent)
                }
                if Providers.isEmpty {
                    Text(I18n.T("No catalogue download links are available for this game."))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.SecondaryText)
                } else {
                    VStack(alignment: .leading, spacing: 9) {
                        DetailLabel("DOWNLOAD SOURCE")
                        Picker(I18n.T("Download source"), selection: $SelectedProvider) {
                            ForEach(Providers, id: \.self) { Provider in
                                Text(Self.ProviderDisplayName(Provider)).tag(Provider)
                            }
                        }
                        .labelsHidden()
                        if Providers.count == 1 {
                            Text(I18n.T("The current index lists one mirror for this game. More mirrors may be listed on its source page."))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.SecondaryText)
                        }
                        if Links.count > 1 {
                            Picker(I18n.T("Download link"), selection: $SelectedLink) {
                                ForEach(Array(Links.enumerated()), id: \.offset) { Index, Link in
                                    Text(I18n.Interpolated("Link \(Index + 1)")).tag(Link)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                    Button { Store.StartDownload(Game, Link: SelectedLink) } label: {
                        HStack(spacing: 8) {
                            if Store.ResolvingGameIds.contains(Game.Id) {
                                ProgressView().controlSize(.small)
                                Text(I18n.T("Preparing download…"))
                            } else {
                                Label(I18n.T("Download Now"), systemImage: "arrow.down.circle")
                            }
                        }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(SelectedLink.isEmpty || Store.ResolvingGameIds.contains(Game.Id))
                }
                if let SourceURL = Game.SourceURL {
                    Button(I18n.T("View original game page ↗")) { Store.OpenExternal(SourceURL.absoluteString) }
                        .buttonStyle(MotionButtonStyle())
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Accent)
                }
                DisclosureGroup(I18n.T("Use a direct file link")) {
                    VStack(alignment: .leading, spacing: 9) {
                        TextField(I18n.T("https://…"), text: $DirectLink)
                            .textFieldStyle(.roundedBorder)
                        Button(Store.ResolvingGameIds.contains(Game.Id) ? "Preparing download…" : "Download file") {
                            Store.StartDownload(Game, Link: DirectLink)
                        }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(DirectLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Store.ResolvingGameIds.contains(Game.Id))
                    }
                    .padding(.top, 7)
                }
                .font(.system(size: 11))
            }
        }
    }

    private static func ProviderDisplayName(_ Key: String) -> String {
        ["1fichier": "1Fichier", "megadb": "MegaDB", "gofile": "GoFile", "buzzheavier": "Buzzheavier",
         "pixeldrain": "PixelDrain", "datanodes": "DataNodes", "vikingfile": "VikingFile",
         "fileditch": "FileDitch", "fileditchfiles": "FileDitch" ][Key.lowercased()] ?? Key.capitalized
    }

    private var Requirements: some View {
        Panel(Padding: 20) {
            VStack(alignment: .leading, spacing: 13) {
                Label(I18n.T("Minimum requirements"), systemImage: "cpu")
                    .font(.system(size: 15, weight: .semibold))
                Text(Details?.MinimumRequirements ?? Game.MinimumRequirements ?? "Requirements are not available from this game's source.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.SecondaryText)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let Recommended = Details?.RecommendedRequirements {
                    Divider()
                    DetailLabel("RECOMMENDED")
                    Text(Recommended)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.SecondaryText)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
                Divider()
                Text(I18n.T("These requirements describe the source game. Windows versions also need a compatible Mac runtime."))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.SecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var ScreenshotGallery: some View {
        Panel(Padding: 24) {
            VStack(alignment: .leading, spacing: 17) {
                Text(I18n.T("Screenshots")).font(.system(size: 22, weight: .semibold))
                if Loading {
                    ProgressView("Loading screenshots…")
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else if Screenshots.indices.contains(ScreenshotIndex) {
                    GameArtwork(URL: Screenshots[ScreenshotIndex], Name: Game.Name, CornerRadius: 11)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .contextMenu {
                            Button(I18n.T("Open full image")) {
                                Store.OpenExternal(Screenshots[ScreenshotIndex].absoluteString)
                            }
                        }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(Screenshots.enumerated()), id: \.offset) { Index, Screenshot in
                                Button { ScreenshotIndex = Index } label: {
                                    GameArtwork(URL: Screenshot, Name: Game.Name, CornerRadius: 7)
                                        .frame(width: 116, height: 68)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7)
                                                .stroke(ScreenshotIndex == Index ? Theme.Accent : Theme.Border,
                                                        lineWidth: ScreenshotIndex == Index ? 2 : 1)
                                        )
                                }
                                .buttonStyle(MotionButtonStyle())
                                .accessibilityLabel(I18n.Interpolated("Screenshot \(Index + 1)"))
                            }
                        }
                    }
                }
            }
        }
    }

    private var ReleaseHistory: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                ShowingHistory.toggle()
                if ShowingHistory && Releases.isEmpty { Task { await LoadHistory() } }
            } label: {
                HStack {
                    Label(I18n.T("Release history"), systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Image(systemName: ShowingHistory ? "chevron.up" : "chevron.down")
                }
                .padding(20)
                .background(Theme.Card, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(MotionButtonStyle())
            if ShowingHistory {
                if HistoryLoading {
                    ProgressView("Loading releases…").padding(22)
                } else if let HistoryError {
                    Notice(Message: HistoryError, Symbol: "exclamationmark.triangle")
                    Button(I18n.T("Try again")) { Task { await LoadHistory() } }
                        .buttonStyle(SecondaryButtonStyle())
                } else if Releases.isEmpty {
                    Notice(Message: I18n.T("No previous releases are available for this game."))
                } else {
                    ForEach(Releases) { Release in
                        Panel(Padding: 16) {
                            HStack(spacing: 12) {
                                Image(systemName: "shippingbox")
                                    .foregroundStyle(Theme.Accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Release.Version).font(.system(size: 14, weight: .semibold))
                                    if let Date = Release.FirstSeen {
                                        Text(I18n.Interpolated("First seen \(Date)"))
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.SecondaryText)
                                    }
                                    Text(Release.IsLive ? "Current release" : "Previous release")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Theme.SecondaryText)
                                }
                                Spacer()
                                if !Release.Game.DownloadLinks.isEmpty {
                                    Menu(Store.ResolvingGameIds.contains(Release.Game.Id) ? "Preparing download…" : "Download") {
                                        ForEach(Release.Game.DownloadLinks.keys.sorted(), id: \.self) { Provider in
                                            ForEach(Array((Release.Game.DownloadLinks[Provider] ?? []).enumerated()), id: \.offset) { Index, Link in
                                                Button(I18n.Interpolated("\(Provider) · Link \(Index + 1)")) {
                                                    Store.StartDownload(Release.Game, Link: Link)
                                                }
                                            }
                                        }
                                    }
                                    .disabled(Store.ResolvingGameIds.contains(Release.Game.Id))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var Attribution: some View {
        HStack(spacing: 4) {
            Spacer()
            if let SteamId = Details?.SteamId {
                Button(I18n.T("Game data provided by Steam ↗")) {
                    Store.OpenExternal("https://store.steampowered.com/app/\(SteamId)")
                }
                .buttonStyle(MotionButtonStyle())
            } else {
                Text(I18n.T("Game data provided by the selected catalogue"))
            }
            Text(I18n.T("· Game information may be inaccurate."))
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(Theme.SecondaryText)
    }

    private func LoadHistory() async {
        HistoryLoading = true
        HistoryError = nil
        do { Releases = try await Store.Catalog.LoadReleases(Game: Game) }
        catch { HistoryError = error.localizedDescription }
        HistoryLoading = false
    }
}

private extension Array {
    func Chunked(into Size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: Size).map { Array(self[$0..<Swift.min($0 + Size, count)]) }
    }
}
