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
                            Button { Reader.scrollTo("Downloads", anchor: .top) } label: { Label("Get Game", systemImage: "arrow.down") }
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
                                    Button(Value) { Tab = Value }.buttonStyle(TVButtonStyle(Selected: Tab == Value))
                                }
                            }.padding(.vertical, 5 * Scale)
                        }.scrollIndicators(.hidden)
                        Information
                        DownloadOptions.id("Downloads")
                        HStack(spacing: 16 * Scale) {
                            if let Installed {
                                Button { Editor = Installed } label: { Label("Game Options", systemImage: "slider.horizontal.3") }
                                    .buttonStyle(TVButtonStyle())
                                Button("Show in Finder") { Store.RevealGame(Installed) }.buttonStyle(TVButtonStyle())
                            } else {
                                Button("Already Installed? Locate Game") { Store.ImportGame(For: Game) }.buttonStyle(TVButtonStyle())
                            }
                            if let Website = Details?.WebsiteURL {
                                Button("Official Website") { Store.OpenExternal(Website.absoluteString) }.buttonStyle(TVButtonStyle())
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
            }
        }.scrollIndicators(.hidden)
    }

    private func MetadataValue(_ Title: String, _ Value: String) -> some View {
        VStack(alignment: .leading, spacing: 8 * Scale) {
            Text(Title).font(.system(size: 12 * Scale, weight: .bold)).tracking(1.5 * Scale).foregroundStyle(TVStyle.Secondary)
            Text(Value).font(.system(size: 21 * Scale, weight: .medium)).lineLimit(1)
        }
    }

    @ViewBuilder private var Information: some View {
        switch Tab {
        case "Screenshots": Screenshots
        case "Requirements": Requirements
        case "Reviews":
            VStack(alignment: .leading, spacing: 20 * Scale) {
                Text("Player reviews").font(.system(size: 30 * Scale, weight: .semibold))
                RatingsView(Game: Game).environmentObject(Store)
            }.padding(26 * Scale).background(TVStyle.Panel, in: RoundedRectangle(cornerRadius: 16 * Scale))
        case "Release History": History
        default:
            VStack(alignment: .leading, spacing: 20 * Scale) {
                Text("About the game").font(.system(size: 30 * Scale, weight: .semibold))
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
                            TVGameTile(Name: "Screenshot \(Index + 1)", Subtitle: "View full screen", Artwork: URL, Width: 410 * Scale) {
                                Screenshot = TVScreenshot(URL: URL)
                            }
                        }
                    }.padding(.vertical, 8 * Scale)
                }.scrollIndicators(.hidden)
            } else {
                TVEmptyState(Symbol: "photo.on.rectangle", Title: Loading ? "Loading screenshots" : "No screenshots available", Message: "Screenshots appear here when they are available for this game.")
            }
        }
    }

    private var Requirements: some View {
        VStack(alignment: .leading, spacing: 26 * Scale) {
            Requirement(Title: "Minimum requirements", Text: Details?.MinimumRequirements ?? Game.MinimumRequirements)
            if let Recommended = Details?.RecommendedRequirements, !Recommended.isEmpty {
                Requirement(Title: "Recommended requirements", Text: Recommended)
            }
            Text("These requirements describe the original game. Windows titles also need a compatible runtime on your Mac.")
                .font(.system(size: 18 * Scale)).foregroundStyle(TVStyle.Secondary)
        }
    }

    private func Requirement(Title: String, Text: String?) -> some View {
        VStack(alignment: .leading, spacing: 18 * Scale) {
            SwiftUI.Text(Title).font(.system(size: 28 * Scale, weight: .semibold))
            SwiftUI.Text(Text.flatMap { $0.isEmpty ? nil : $0 } ?? "Requirements have not been provided.")
                .font(.system(size: 21 * Scale)).lineSpacing(6 * Scale).foregroundStyle(TVStyle.Secondary)
                .textSelection(.enabled)
        }.padding(28 * Scale).frame(maxWidth: .infinity, alignment: .leading)
            .background(TVStyle.Panel, in: RoundedRectangle(cornerRadius: 16 * Scale))
    }

    private var History: some View {
        VStack(alignment: .leading, spacing: 18 * Scale) {
            Text("Release history").font(.system(size: 30 * Scale, weight: .semibold))
            if HistoryLoading { ProgressView("Loading releases…").font(.system(size: 20 * Scale)) }
            if let HistoryError {
                Text(HistoryError).font(.system(size: 20 * Scale)).foregroundStyle(TVStyle.Secondary)
                Button("Try Again") { Task { await LoadHistory() } }.buttonStyle(TVButtonStyle())
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
                Text("No earlier releases are available.").font(.system(size: 21 * Scale)).foregroundStyle(TVStyle.Secondary)
            }
        }
    }

    private var DownloadOptions: some View {
        VStack(alignment: .leading, spacing: 24 * Scale) {
            TVPageHeading(Title: "Download options", Subtitle: "Choose a provider to see its available files.")
            if Providers.isEmpty {
                Text("This source has not provided a download link.").font(.system(size: 21 * Scale)).foregroundStyle(TVStyle.Secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 14 * Scale) {
                        ForEach(Providers, id: \.self) { Value in
                            Button(Value) { Provider = Value }.buttonStyle(TVButtonStyle(Selected: Value == Provider))
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
                                    Text("Preparing…")
                                }
                            } else {
                                Label("Download", systemImage: "arrow.down")
                            }
                        }.buttonStyle(TVButtonStyle(Prominent: true)).disabled(Store.ResolvingGameIds.contains(Game.Id))
                        if let Scheme = URL(string: Link)?.scheme?.lowercased(), ["http", "https"].contains(Scheme) {
                            Button { Store.OpenExternal(Link) } label: { Image(systemName: "arrow.up.right") }
                                .buttonStyle(TVButtonStyle()).accessibilityLabel("Open provider link")
                        }
                    }.padding(24 * Scale).background(TVStyle.Panel, in: RoundedRectangle(cornerRadius: 14 * Scale))
                }
            }
            VStack(alignment: .leading, spacing: 14 * Scale) {
                Text("Use a direct link").font(.system(size: 22 * Scale, weight: .semibold))
                HStack(spacing: 16 * Scale) {
                    TextField("https://…", text: $DirectLink).textFieldStyle(.plain)
                        .font(.system(size: 21 * Scale)).padding(20 * Scale)
                        .background(TVStyle.Panel, in: RoundedRectangle(cornerRadius: 10 * Scale))
                    Button { Store.StartDownload(Game, Link: DirectLink) } label: {
                        if Store.ResolvingGameIds.contains(Game.Id) {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Preparing…")
                            }
                        } else {
                            Text("Download")
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
                Text("Screenshot").font(.system(size: 25 * Scale, weight: .semibold))
                Spacer()
                Button("Close") { Dismiss() }.buttonStyle(TVButtonStyle()).keyboardShortcut(.cancelAction)
            }
            AsyncImage(url: URL) { Phase in
                if let Image = Phase.image { Image.resizable().scaledToFit() }
                else if Phase.error != nil { TVEmptyState(Symbol: "photo", Title: "Unable to load screenshot", Message: "Try opening the screenshot again.") }
                else { ProgressView() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(28 * Scale).frame(minWidth: 760, idealWidth: 1100, minHeight: 520, idealHeight: 760)
        .background(TVStyle.Background).foregroundStyle(TVStyle.Text)
    }
}
