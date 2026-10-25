import SwiftUI

struct TVGameDetailView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.TVScale) private var Scale
    let Game: Game
    @State private var Details: GameDetails?
    @State private var Loading = false
    @State private var Tab = "Overview"
    @State private var Provider = ""
    @State private var Releases: [GameRelease] = []
    @State private var HistoryLoading = false
    @State private var HistoryError: String?
    @State private var Editor: LibraryGame?
    @State private var Screenshot: TVScreenshot?
    @State private var DirectLink = ""

    private var Installed: LibraryGame? { Store.LibraryMatch(Game) }
    private var Providers: [String] { Game.DownloadLinks.keys.sorted() }
    private var Links: [String] { Game.DownloadLinks[Provider] ?? [] }
    private var Summary: String {
        if let Details, !Details.Summary.isEmpty { return Details.Summary }
        return Game.Description ?? "Explore the game details, requirements, and available downloads."
    }
    private var Description: String {
        if let Details, !Details.Description.isEmpty { return Details.Description }
        return Game.Description ?? "No description is available for this game."
    }
    private var Tabs: [String] {
        ["Overview", "Screenshots", "Requirements", "Reviews"] + (Game.HasHistory ? ["Release History"] : [])
    }

    var body: some View {
        ScrollViewReader { Reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 30 * Scale) {
                    TVGamesHero(Name: Game.Name,
                                Eyebrow: Game.Categories.prefix(3).joined(separator: " · ").uppercased(),
                                Summary: Summary, Artwork: Details?.HeaderURL ?? Game.ArtworkURL, Height: 520) {
                        if let Installed { TVLaunchButton(Game: Installed) }
                        else {
                            Button { Reader.scrollTo("Downloads", anchor: .top) } label: { Label(I18n.T("Get Game"), systemImage: "arrow.down") }
                                .buttonStyle(TVButtonStyle(Prominent: true))
                        }
                        Button { Store.ToggleWishlist(Game) } label: {
                            Label(Store.Wishlist.contains(Game.Id) ? "Saved" : "Play Later", systemImage: Store.Wishlist.contains(Game.Id) ? "checkmark" : "plus")
                        }.buttonStyle(TVButtonStyle())
                    }
                    VStack(alignment: .leading, spacing: 28 * Scale) {
                        Metadata
                        ScrollView(.horizontal) {
                            HStack(spacing: 14 * Scale) {
                                ForEach(Tabs, id: \.self) { Value in
                                    Button(I18n.T(Value)) { Tab = Value }.buttonStyle(TVButtonStyle(Selected: Tab == Value))
                                }
                            }.padding(.vertical, 5 * Scale)
                        }.scrollIndicators(.hidden)
                        Information
                        DownloadOptions.id("Downloads")
                        HStack(spacing: 16 * Scale) {
                            if let Installed {
                                Button { Editor = Installed } label: { Label(I18n.T("Game Options"), systemImage: "slider.horizontal.3") }
                                    .buttonStyle(TVButtonStyle())
                                Button(I18n.T("Show in Finder")) { Store.RevealGame(Installed) }.buttonStyle(TVButtonStyle())
                            } else {
                                Button(I18n.T("Already Installed? Locate Game")) { Store.ImportGame(For: Game) }.buttonStyle(TVButtonStyle())
                            }
                            if let Website = Details?.WebsiteURL {
                                Button(I18n.T("Official Website")) { Store.OpenExternal(Website.absoluteString) }.buttonStyle(TVButtonStyle())
                            }
                        }
                    }.padding(.horizontal, 40 * Scale)
                }.padding(.bottom, 44 * Scale)
            }
        }
        .background(TVStyle.Background).foregroundStyle(TVStyle.Text)
        .sheet(item: $Editor) { Game in LibraryEditorView(Game: Game).environmentObject(Store) }
        .sheet(item: $Screenshot) { Shot in TVScreenshotView(URL: Shot.URL) }
        .task(id: Game) {
            Provider = Providers.first ?? ""
            Tab = "Overview"
            Details = nil
            Releases = []
            HistoryError = nil
            Loading = true
            let Loaded = await Store.LoadGameDetails(Game)
            guard !Task.isCancelled else { return }
            Details = Loaded
            Loading = false
        }
        .task(id: Tab) {
            guard Tab == "Release History", Releases.isEmpty else { return }
            await LoadHistory()
        }
    }

    private var Metadata: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 30 * Scale) {
                if let Size = Game.Size { MetadataValue("DOWNLOAD", Size) }
                if let Version = Game.Version { MetadataValue("VERSION", Version) }
                if let Released = Details?.ReleaseDate { MetadataValue("RELEASED", Released) }
                if let Developer = Details?.Developers.first { MetadataValue("DEVELOPER", Developer) }
                if Game.Online { MetadataValue("MULTIPLAYER", "Online") }
                if Game.Dlc { MetadataValue("EXTRAS", "Includes DLC") }
                if let Installed { MetadataValue("PLAYTIME", FormatPlayTime(Installed.PlayTimeSeconds)) }
                if let Size = Installed?.InstalledSizeBytes { MetadataValue("INSTALLED SIZE", ByteCountFormatter.string(fromByteCount: Size, countStyle: .file)) }
            }
        }.scrollIndicators(.hidden)
    }

    private func MetadataValue(_ Title: String, _ Value: String) -> some View {
        VStack(alignment: .leading, spacing: 8 * Scale) {
            Text(I18n.T(Title)).font(.system(size: 12 * Scale, weight: .bold)).tracking(1.5 * Scale).foregroundStyle(TVStyle.Secondary)
            Text(I18n.T(Value)).font(.system(size: 21 * Scale, weight: .medium)).lineLimit(1)
        }
    }

    @ViewBuilder private var Information: some View {
        switch Tab {
        case "Screenshots": Screenshots
        case "Requirements": Requirements
        case "Reviews":
            VStack(alignment: .leading, spacing: 20 * Scale) {
                Text(I18n.T("Player reviews")).font(.system(size: 30 * Scale, weight: .semibold))
                RatingsView(Game: Game).environmentObject(Store)
            }.padding(26 * Scale).background(TVStyle.Panel, in: RoundedRectangle(cornerRadius: 16 * Scale))
        case "Release History": History
        default:
            VStack(alignment: .leading, spacing: 20 * Scale) {
                Text(I18n.T("About the game")).font(.system(size: 30 * Scale, weight: .semibold))
                if Loading { ProgressView("Loading game information…").font(.system(size: 19 * Scale)) }
                Text(Description)
                    .font(.system(size: 22 * Scale)).foregroundStyle(TVStyle.Secondary)
                    .lineSpacing(7 * Scale).textSelection(.enabled)
            }.padding(28 * Scale).frame(maxWidth: .infinity, alignment: .leading)
                .background(TVStyle.Panel, in: RoundedRectangle(cornerRadius: 16 * Scale))
        }
    }

    private var Screenshots: some View {
        Group {
            if let Details, !Details.Screenshots.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 20 * Scale) {
                        ForEach(Array(Details.Screenshots.enumerated()), id: \.element) { Index, URL in
                            TVGameTile(Name: "Screenshot \(Index + 1)", Subtitle: I18n.T("View full screen"), Artwork: URL, Width: 410 * Scale) {
                                Screenshot = TVScreenshot(URL: URL)
                            }
                        }
                    }.padding(.vertical, 8 * Scale)
                }.scrollIndicators(.hidden)
            } else {
                TVEmptyState(Symbol: "photo.on.rectangle", Title: Loading ? "Loading screenshots" : "No screenshots available", Message: I18n.T("Screenshots appear here when they are available for this game."))
            }
        }
    }

    private var Requirements: some View {
        VStack(alignment: .leading, spacing: 26 * Scale) {
            Requirement(Title: I18n.T("Minimum requirements"), Text: Details?.MinimumRequirements ?? Game.MinimumRequirements)
            if let Recommended = Details?.RecommendedRequirements, !Recommended.isEmpty {
                Requirement(Title: I18n.T("Recommended requirements"), Text: Recommended)
            }
            Text(I18n.T("These requirements describe the original game. Windows titles also need a compatible runtime on your Mac."))
                .font(.system(size: 18 * Scale)).foregroundStyle(TVStyle.Secondary)
        }
    }

    private func Requirement(Title: String, Text: String?) -> some View {
        VStack(alignment: .leading, spacing: 18 * Scale) {
            SwiftUI.Text(I18n.T(Title)).font(.system(size: 28 * Scale, weight: .semibold))
            SwiftUI.Text(Text.flatMap { $0.isEmpty ? nil : $0 } ?? "Requirements have not been provided.")
                .font(.system(size: 21 * Scale)).lineSpacing(6 * Scale).foregroundStyle(TVStyle.Secondary)
                .textSelection(.enabled)
        }.padding(28 * Scale).frame(maxWidth: .infinity, alignment: .leading)
            .background(TVStyle.Panel, in: RoundedRectangle(cornerRadius: 16 * Scale))
    }

    private var History: some View {
        VStack(alignment: .leading, spacing: 18 * Scale) {
            Text(I18n.T("Release history")).font(.system(size: 30 * Scale, weight: .semibold))
            if HistoryLoading { ProgressView("Loading releases…").font(.system(size: 20 * Scale)) }
            if let HistoryError {
                Text(HistoryError).font(.system(size: 20 * Scale)).foregroundStyle(TVStyle.Secondary)
                Button(I18n.T("Try Again")) { Task { await LoadHistory() } }.buttonStyle(TVButtonStyle())
            }
            ForEach(Releases) { Release in
                Button { Store.OpenGame(Release.Game) } label: {
                    HStack(spacing: 18 * Scale) {
                        VStack(alignment: .leading, spacing: 8 * Scale) {
                            Text(Release.Version).font(.system(size: 23 * Scale, weight: .semibold))
                            Text(Release.FirstSeen ?? "Release date unavailable").font(.system(size: 18 * Scale)).foregroundStyle(TVStyle.Secondary)
                        }
                        Spacer()
                        Text(Release.IsLive ? "Current" : "View Release")
                        Image(systemName: "chevron.right")
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(TVButtonStyle())
            }
            if !HistoryLoading && Releases.isEmpty && HistoryError == nil {
                Text(I18n.T("No earlier releases are available.")).font(.system(size: 21 * Scale)).foregroundStyle(TVStyle.Secondary)
            }
        }
    }

    private var DownloadOptions: some View {
        VStack(alignment: .leading, spacing: 24 * Scale) {
            TVPageHeading(Title: I18n.T("Download options"), Subtitle: I18n.T("Choose a provider to see its available files."))
            if Providers.isEmpty {
                Text(I18n.T("This source has not provided a download link.")).font(.system(size: 21 * Scale)).foregroundStyle(TVStyle.Secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 14 * Scale) {
                        ForEach(Providers, id: \.self) { Value in
                            Button(I18n.T(Value)) { Provider = Value }.buttonStyle(TVButtonStyle(Selected: Value == Provider))
                        }
                    }.padding(.vertical, 5 * Scale)
                }.scrollIndicators(.hidden)
                ForEach(Array(Links.enumerated()), id: \.offset) { Index, Link in
                    HStack(spacing: 20 * Scale) {
                        VStack(alignment: .leading, spacing: 7 * Scale) {
                            Text(Links.count == 1 ? Provider : "\(Provider) · Link \(Index + 1)").font(.system(size: 23 * Scale, weight: .semibold))
                            Text(URL(string: Link)?.host ?? Link).font(.system(size: 17 * Scale)).foregroundStyle(TVStyle.Secondary).lineLimit(1)
                        }
                        Spacer()
                        Button { Store.StartDownload(Game, Link: Link) } label: {
                            if Store.ResolvingGameIds.contains(Game.Id) {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text(I18n.T("Preparing…"))
                                }
                            } else {
                                Label(I18n.T("Download"), systemImage: "arrow.down")
                            }
                        }.buttonStyle(TVButtonStyle(Prominent: true)).disabled(Store.ResolvingGameIds.contains(Game.Id))
                        if let Scheme = URL(string: Link)?.scheme?.lowercased(), ["http", "https"].contains(Scheme) {
                            Button { Store.OpenExternal(Link) } label: { Image(systemName: "arrow.up.right") }
                                .buttonStyle(TVButtonStyle()).accessibilityLabel(I18n.T("Open provider link"))
                        }
                    }.padding(24 * Scale).background(TVStyle.Panel, in: RoundedRectangle(cornerRadius: 14 * Scale))
                }
            }
            VStack(alignment: .leading, spacing: 14 * Scale) {
                Text(I18n.T("Use a direct link")).font(.system(size: 22 * Scale, weight: .semibold))
                HStack(spacing: 16 * Scale) {
                    TextField(I18n.T("https://…"), text: $DirectLink).textFieldStyle(.plain)
                        .font(.system(size: 21 * Scale)).padding(20 * Scale)
                        .background(TVStyle.Panel, in: RoundedRectangle(cornerRadius: 10 * Scale))
                    Button { Store.StartDownload(Game, Link: DirectLink) } label: {
                        if Store.ResolvingGameIds.contains(Game.Id) {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(I18n.T("Preparing…"))
                            }
                        } else {
                            Text(I18n.T("Download"))
                        }
                    }
                    .buttonStyle(TVButtonStyle())
                    .disabled(DirectLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Store.ResolvingGameIds.contains(Game.Id))
                }
            }
        }.padding(.top, 20 * Scale)
    }

    private func LoadHistory() async {
        HistoryLoading = true
        HistoryError = nil
        defer { HistoryLoading = false }
        do {
            let Loaded = try await Store.Catalog.LoadReleases(Game: Game)
            if !Task.isCancelled { Releases = Loaded }
        } catch {
            if !Task.isCancelled { HistoryError = error.localizedDescription }
        }
    }
}

private struct TVScreenshot: Identifiable {
    let URL: URL
    var id: String { URL.absoluteString }
}

private struct TVScreenshotView: View {
    @Environment(\.dismiss) private var Dismiss
    @Environment(\.TVScale) private var Scale
    let URL: URL
    var body: some View {
        VStack(spacing: 20 * Scale) {
            HStack {
                Text(I18n.T("Screenshot")).font(.system(size: 25 * Scale, weight: .semibold))
                Spacer()
                Button(I18n.T("Close")) { Dismiss() }.buttonStyle(TVButtonStyle()).keyboardShortcut(.cancelAction)
            }
            AsyncImage(url: URL) { Phase in
                if let Image = Phase.image { Image.resizable().scaledToFit() }
                else if Phase.error != nil { TVEmptyState(Symbol: "photo", Title: I18n.T("Unable to load screenshot"), Message: I18n.T("Try opening the screenshot again.")) }
                else { ProgressView() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(28 * Scale).frame(minWidth: 760, idealWidth: 1100, minHeight: 520, idealHeight: 760)
        .background(TVStyle.Background).foregroundStyle(TVStyle.Text)
    }
}
