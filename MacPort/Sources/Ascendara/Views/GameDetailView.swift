import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject var Store: AppStore
    let Game: Game
    @State private var Details: GameDetails?
    @State private var Loading = false
    @State private var Tab = "Overview"
    @State private var SelectedProvider = ""
    @State private var SelectedLink = ""
    @State private var Releases: [GameRelease] = []
    @State private var HistoryLoading = false
    @State private var HistoryError: String?
    @State private var DirectLink = ""
    private var Providers: [String] { Game.DownloadLinks.keys.sorted() }
    private var Links: [String] { Game.DownloadLinks[SelectedProvider] ?? [] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Button { Store.SelectedGame = nil } label: { Label("Back", systemImage: "chevron.left") }.buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button { Store.ToggleWishlist(Game) } label: {
                        Label(Store.Wishlist.contains(Game.Id) ? "Saved to Play Later" : "Play Later", systemImage: Store.Wishlist.contains(Game.Id) ? "bookmark.fill" : "bookmark")
                    }.buttonStyle(SecondaryButtonStyle())
                }
                Hero
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 22) {
                        Picker("Game information", selection: $Tab) {
                            Text("Overview").tag("Overview")
                            Text("Screenshots").tag("Screenshots")
                            Text("Requirements").tag("Requirements")
                            Text("Reviews").tag("Reviews")
                            if Game.HasHistory { Text("Time machine").tag("History") }
                        }.pickerStyle(.segmented)
                        ZStack(alignment: .topLeading) {
                            Group {
                                switch Tab {
                                case "Screenshots": Screenshots
                                case "Requirements": Requirements
                                case "History": History
                                case "Reviews": RatingsView(Game: Game)
                                default: Overview
                                }
                            }.id(Tab).MotionTransition()
                        }.MotionAnimation(Tab)
                    }.frame(maxWidth: .infinity)
                    DownloadPanel.frame(width: 300)
                }
            }.padding(28).padding(.bottom, 100).frame(maxWidth: 1450).frame(maxWidth: .infinity)
        }.background(Theme.Background).foregroundStyle(Theme.Foreground)
            .MotionAnimation(Loading)
            .MotionAnimation(HistoryLoading)
            .MotionAnimation(Store.Wishlist.contains(Game.Id), Animation: AppMotion.Spring)
            .task(id: Game.Id) {
            SelectedProvider = Providers.first ?? ""
            SelectedLink = Links.first ?? ""
            Details = nil
            Loading = true
            Details = await Store.LoadGameDetails(Game)
            Loading = false
            if Game.HasHistory { await LoadHistory() }
        }.onChange(of: SelectedProvider) { _, _ in SelectedLink = Links.first ?? "" }
    }
    private var Hero: some View {
        ZStack(alignment: .bottomLeading) {
            GameArtwork(URL: Details?.HeaderURL ?? Game.ArtworkURL, Name: Game.Name, CornerRadius: 16)
            LinearGradient(colors: [.clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 7) {
                    if Game.Online { Text("ONLINE MULTIPLAYER").font(.system(size: 10, weight: .bold)).tracking(1) }
                    if Game.Dlc { Text("INCLUDES DLC").font(.system(size: 10, weight: .bold)).tracking(1) }
                }.foregroundStyle(.white.opacity(0.7))
                Text(Game.Name).font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
                HStack(spacing: 8) {
                    ForEach(Game.Categories.prefix(6), id: \.self) { Category in
                        Text(Category).font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 5).background(.white.opacity(0.15), in: Capsule())
                    }
                }.foregroundStyle(.white)
            }.padding(30)
        }.frame(height: 335).clipShape(RoundedRectangle(cornerRadius: 16))
    }
    private var Overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("About the game").font(.system(size: 19, weight: .semibold))
                    if Loading { ProgressView().controlSize(.small) }
                    Text(Details?.Description ?? Details?.Summary ?? Game.Description ?? "No description is available in this index.")
                        .font(.system(size: 13)).foregroundStyle(Theme.SecondaryText).lineSpacing(6).textSelection(.enabled)
                    if let Website = Details?.WebsiteURL { Button("Visit official website ↗") { Store.OpenExternal(Website.absoluteString) }.buttonStyle(MotionButtonStyle()).foregroundStyle(Theme.Accent) }
                }
            }
            if let Details {
                Panel {
                    Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 15) {
                        DetailRow("Developer", Details.Developers.joined(separator: ", "))
                        DetailRow("Publisher", Details.Publishers.joined(separator: ", "))
                        DetailRow("Release date", Details.ReleaseDate ?? "Unknown")
                        DetailRow("Platforms", Details.Platforms.joined(separator: ", "))
                    }
                }
            }
        }
    }
    @ViewBuilder private func DetailRow(_ Label: String, _ Value: String) -> some View {
        if !Value.isEmpty { GridRow { Text(Label).foregroundStyle(Theme.SecondaryText); Text(Value).textSelection(.enabled) }.font(.system(size: 12)) }
    }
    private var Screenshots: some View {
        VStack(spacing: 16) {
            if Loading { ProgressView().padding(35) }
            else if let Details, !Details.Screenshots.isEmpty {
                ForEach(Details.Screenshots, id: \.self) { Screenshot in
                    GameArtwork(URL: Screenshot, Name: Game.Name).aspectRatio(16 / 9, contentMode: .fit)
                        .contextMenu { Button("Open full image") { Store.OpenExternal(Screenshot.absoluteString) } }
                }
            } else { EmptyPanel(Symbol: "photo.on.rectangle.angled", Title: "No screenshots available", Message: "Screenshots appear when this game has matching store metadata.") }
        }
    }
    private var Requirements: some View {
        VStack(alignment: .leading, spacing: 16) {
            Notice(Message: "Requirements come from the source game. Windows titles need a compatible Wine or Highball installation on macOS.", Symbol: "desktopcomputer")
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Minimum requirements").font(.system(size: 18, weight: .semibold))
                    Text(Details?.MinimumRequirements ?? Game.MinimumRequirements ?? "This source does not include system requirements.").font(.system(size: 12)).foregroundStyle(Theme.SecondaryText).lineSpacing(6).textSelection(.enabled)
                    if let Recommended = Details?.RecommendedRequirements {
                        Divider().padding(.vertical, 6)
                        Text("Recommended").font(.system(size: 18, weight: .semibold))
                        Text(Recommended).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText).lineSpacing(6).textSelection(.enabled)
                    }
                }
            }
        }
    }
    private var History: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeading(Title: "Time machine", Subtitle: "Releases recorded by this game source", Symbol: "clock.arrow.circlepath")
            if HistoryLoading { ProgressView("Loading releases…").padding(25) }
            else if let HistoryError {
                Notice(Message: HistoryError, Symbol: "exclamationmark.triangle")
                Button("Try again") { Task { await LoadHistory() } }.buttonStyle(SecondaryButtonStyle())
            } else if Releases.isEmpty {
                Notice(Message: "No previous releases are available for this game.")
            } else {
                ForEach(Releases) { Release in
                    Panel(Padding: 18) {
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: "shippingbox").foregroundStyle(Theme.Accent).font(.system(size: 23))
                            VStack(alignment: .leading, spacing: 7) {
                                Text(Release.Version).font(.system(size: 15, weight: .semibold))
                                if let Date = Release.FirstSeen { Text("First seen \(Date)").font(.system(size: 11)).foregroundStyle(Theme.SecondaryText) }
                                Text(Release.IsLive ? "Current release" : "Previous release").font(.system(size: 10, weight: .medium)).foregroundStyle(Release.IsLive ? .green : Theme.SecondaryText)
                            }
                            Spacer()
                            if !Release.Game.DownloadLinks.isEmpty {
                                Menu("Download") {
                                    ForEach(Release.Game.DownloadLinks.keys.sorted(), id: \.self) { Provider in
                                        ForEach(Array((Release.Game.DownloadLinks[Provider] ?? []).enumerated()), id: \.offset) { Index, Link in
                                            Button("\(Provider) · Link \(Index + 1)") { Store.StartDownload(Release.Game, Link: Link) }
                                        }
                                    }
                                }.fixedSize()
                            }
                        }
                    }
                }
            }
        }
    }
    private func LoadHistory() async {
        HistoryLoading = true
        HistoryError = nil
        do { Releases = try await Store.Catalog.LoadReleases(Game: Game) }
        catch { HistoryError = error.localizedDescription }
        HistoryLoading = false
    }
    private var DownloadPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 17) {
                if let Installed = Store.LibraryMatch(Game) {
                    Label("In your library", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12, weight: .semibold))
                    Button { Store.LaunchGame(Installed) } label: { Label("Play game", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButtonStyle())
                    Button("Show game files") { Store.RevealGame(Installed) }.buttonStyle(SecondaryButtonStyle())
                    Divider()
                }
                Text("Download").font(.system(size: 20, weight: .bold))
                if Store.LibraryMatch(Game) == nil {
                    Button("Already installed? Add to library…") { Store.ImportGame(For: Game) }.buttonStyle(MotionButtonStyle()).foregroundStyle(Theme.Accent).font(.system(size: 11))
                }
                if let Version = Game.Version { Metadata("Version", Version) }
                if let Size = Game.Size { Metadata("Size", Size) }
                if let Updated = Game.LatestUpdate { Metadata("Updated", Updated) }
                if let Release = Game.ReleasedBy { Metadata("Source", Release) }
                if Providers.isEmpty {
                    Notice(Message: "This entry has no download links. You can still save it to Play Later.")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose a provider").font(.system(size: 12, weight: .medium))
                        Picker("Provider", selection: $SelectedProvider) { ForEach(Providers, id: \.self) { Provider in Text(Provider).tag(Provider) } }.labelsHidden()
                        if Links.count > 1 {
                            Picker("Download", selection: $SelectedLink) {
                                ForEach(Array(Links.enumerated()), id: \.offset) { Index, Link in Text("Link \(Index + 1)").tag(Link) }
                            }
                        }
                    }
                    Button { Store.StartDownload(Game, Link: SelectedLink) } label: { Label("Download", systemImage: "arrow.down.circle").frame(maxWidth: .infinity) }
                        .buttonStyle(PrimaryButtonStyle()).disabled(SelectedLink.isEmpty)
                    if let LinkURL = URL(string: SelectedLink), ["https", "http"].contains(LinkURL.scheme?.lowercased() ?? "") {
                        Button("Open provider in browser ↗") { Store.OpenExternal(SelectedLink) }.buttonStyle(MotionButtonStyle()).foregroundStyle(Theme.Accent).font(.system(size: 11))
                    }
                    DisclosureGroup("Use a direct file link") {
                        VStack(alignment: .leading, spacing: 9) {
                            TextField("https://…", text: $DirectLink).textFieldStyle(.roundedBorder)
                            Button("Download file") { Store.StartDownload(Game, Link: DirectLink) }.buttonStyle(SecondaryButtonStyle()).disabled(DirectLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }.padding(.top, 8)
                    }.font(.system(size: 11))
                }
            }
        }
    }
    private func Metadata(_ Title: String, _ Value: String) -> some View {
        HStack(alignment: .top) { Text(Title).foregroundStyle(Theme.SecondaryText); Spacer(); Text(Value).multilineTextAlignment(.trailing) }.font(.system(size: 12))
    }
}
