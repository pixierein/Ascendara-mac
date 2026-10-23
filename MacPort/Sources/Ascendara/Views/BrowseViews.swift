import SwiftUI

struct HomeView: View {
    @EnvironmentObject var Store: AppStore
    @State private var Slide = 0
    private var Featured: [Game] { Array(Store.Games.sorted { ($0.Weight ?? 0) > ($1.Weight ?? 0) }.prefix(6)) }
    private var Recent: [LibraryGame] { Array(Store.Library.filter { $0.LastPlayedAt != nil }.sorted { ($0.LastPlayedAt ?? .distantPast) > ($1.LastPlayedAt ?? .distantPast) }.prefix(3)) }
    var body: some View {
        GeometryReader { Geometry in
            let RecentWidth = (min(Geometry.size.width, 1500) - 72) / 3
            let HeroHeight = RecentWidth * 2 * 9 / 16
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if Store.Games.isEmpty {
                        CatalogEmptyView()
                    } else {
                        HStack(alignment: .top, spacing: 20) {
                            Hero.frame(maxWidth: .infinity)
                            RecentPanel.frame(width: RecentWidth)
                        }.frame(height: HeroHeight)
                        HStack(spacing: 12) {
                            SearchField(Text: $Store.SearchQuery, Placeholder: "What will you play next?")
                                .onSubmit { Store.CurrentRoute = .Search }
                            Button { Store.CurrentRoute = .Search } label: { Label("Find games", systemImage: "magnifyingglass") }.buttonStyle(PrimaryButtonStyle())
                            IconButton(Symbol: "bookmark", Help: "Play Later") { Store.CurrentRoute = .Wishlist }
                            IconButton(Symbol: "arrow.clockwise", Help: "Refresh game index") { Store.RefreshCatalog() }
                        }.padding(.horizontal, 30)
                        GameRow(Title: "Top Games", Subtitle: "", Symbol: "flame", Games: Array(Store.Games.sorted { ($0.Weight ?? 0) > ($1.Weight ?? 0) }.prefix(20)))
                        GameRow(Title: "Recently updated", Subtitle: "Fresh updates, ready to explore", Symbol: "sparkles", Games: Array(Store.Games.filter { $0.LatestUpdate != nil }.sorted { ($0.LatestUpdate ?? "") > ($1.LatestUpdate ?? "") }.prefix(20)))
                        GameRow(Title: "Play together", Subtitle: "Games with online multiplayer", Symbol: "globe", Games: Array(Store.Games.filter(\.Online).prefix(20)))
                        VStack(alignment: .leading, spacing: 16) {
                            SectionHeading(Title: "Find your next adventure", Subtitle: "Browse by genre", Symbol: "gamecontroller")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                                ForEach(["Action", "Adventure", "Survival", "Simulation", "Strategy", "Sports"], id: \.self) { Genre in
                                    Button {
                                        Store.SelectedGenre = Genre
                                        Store.CurrentRoute = .Search
                                    } label: {
                                        HStack { Text(Genre).font(.system(size: 14, weight: .semibold)); Spacer(); Image(systemName: "arrow.up.right") }
                                            .padding(20).background(Theme.Accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                    }.buttonStyle(MotionButtonStyle())
                                }
                            }
                        }
                    }
                }.padding(26).padding(.bottom, 100).frame(maxWidth: 1500)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    private var Hero: some View {
        let Game = Featured[min(Slide, max(0, Featured.count - 1))]
        return ZStack(alignment: .bottomLeading) {
            GameArtwork(URL: Game.ArtworkURL, Name: Game.Name, CornerRadius: 16)
                .id(Game.Id).MotionTransition(Distance: 0)
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom) {
                ZStack(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Featured", systemImage: "sparkles").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 9).padding(.vertical, 5).background(Theme.Accent, in: RoundedRectangle(cornerRadius: 5))
                        Text(Game.Name).font(.system(size: 38, weight: .bold)).lineLimit(2).foregroundStyle(.white)
                        HStack(spacing: 7) {
                            ForEach(Array(Game.Categories.prefix(3)), id: \.self) { Category in
                                Text(Category).font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 5).background(.white.opacity(0.13), in: Capsule())
                            }
                        }.foregroundStyle(.white.opacity(0.9))
                        Button("View Game") { Store.OpenGame(Game) }.buttonStyle(PrimaryButtonStyle())
                    }.id(Game.Id).MotionTransition()
                }
                Spacer(minLength: 4)
                HStack(spacing: 8) {
                    Button { Slide = (Slide + Featured.count - 1) % Featured.count } label: { Image(systemName: "chevron.left").frame(width: 31, height: 31) }
                    ForEach(Featured.indices, id: \.self) { Index in
                        Capsule().fill(Index == Slide ? Theme.Accent : .white.opacity(0.4)).frame(width: Index == Slide ? 20 : 5, height: 5)
                    }
                    Button { Slide = (Slide + 1) % Featured.count } label: { Image(systemName: "chevron.right").frame(width: 31, height: 31) }
                }.buttonStyle(MotionButtonStyle()).foregroundStyle(.white)
            }.padding(28)
        }.clipShape(RoundedRectangle(cornerRadius: 16))
            .MotionAnimation(Slide)
    }
    private var RecentPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recent Games", systemImage: "play").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.SecondaryText)
            if Recent.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "play.circle").font(.system(size: 29, weight: .light)).foregroundStyle(Theme.SecondaryText.opacity(0.55))
                    Text("Your next session starts here").font(.system(size: 12, weight: .medium))
                    Text("Launch a game from your library to find it here.").font(.system(size: 11)).foregroundStyle(Theme.SecondaryText).multilineTextAlignment(.center)
                    Button("Open library") { Store.CurrentRoute = .Library }.buttonStyle(SecondaryButtonStyle())
                }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Card.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Border, style: StrokeStyle(lineWidth: 1, dash: [4])))
            } else {
                ForEach(Recent) { Game in
                    Button { Store.LaunchGame(Game) } label: {
                        ZStack(alignment: .bottomLeading) {
                            GameArtwork(URL: Game.ArtworkURL, Name: Game.Name, CornerRadius: 8)
                            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Game.Name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                if let Date = Game.LastPlayedAt {
                                    Text(Date, style: .relative).font(.system(size: 10)).foregroundStyle(.white.opacity(0.8))
                                }
                            }.padding(9).foregroundStyle(.white)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(MotionButtonStyle()).frame(maxHeight: .infinity)
                }
            }
        }.frame(maxHeight: .infinity)
    }
}

struct GameRow: View {
    @EnvironmentObject var Store: AppStore
    let Title: String
    let Subtitle: String
    let Symbol: String
    let Games: [Game]
    var body: some View {
        if !Games.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SectionHeading(Title: Title, Subtitle: Subtitle.isEmpty ? nil : Subtitle, Symbol: Symbol)
                    Button { Store.CurrentRoute = .Search } label: { Label("View all", systemImage: "arrow.right") }.buttonStyle(MotionButtonStyle()).foregroundStyle(Theme.Accent)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 16) { ForEach(Games) { Game in HomeGameCard(Game: Game) } }.padding(.bottom, 8)
                }
            }
        }
    }
}

struct HomeGameCard: View {
    @EnvironmentObject var Store: AppStore
    let Game: Game
    var body: some View {
        Button { Store.OpenGame(Game) } label: {
            ZStack(alignment: .bottomLeading) {
                GameArtwork(URL: Game.ArtworkURL, Name: Game.Name)
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if Game.Online { Image(systemName: "globe").foregroundStyle(.white).padding(5).background(Theme.Accent, in: Circle()) }
                        if Game.Dlc { Image(systemName: "gift").foregroundStyle(.white).padding(5).background(.orange, in: Circle()) }
                    }.font(.system(size: 9))
                    Text(Game.Name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(Game.Categories.prefix(2).joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }.padding(12)
            }.frame(width: 280, height: 157.5).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Border.opacity(0.3), lineWidth: 1))
        }.buttonStyle(MotionButtonStyle()).contextMenu {
            Button("View game") { Store.OpenGame(Game) }
            Button(Store.Wishlist.contains(Game.Id) ? "Remove from Play Later" : "Add to Play Later") { Store.ToggleWishlist(Game) }
        }
    }
}

struct CatalogEmptyView: View {
    @EnvironmentObject var Store: AppStore
    var body: some View {
        VStack(spacing: 20) {
            if Store.IsLoading {
                ProgressView().controlSize(.large).tint(Theme.Accent)
                Text("Loading your game index…").font(.system(size: 18, weight: .medium))
                Text("Your library is available while the index loads.").foregroundStyle(Theme.SecondaryText)
            } else {
                EmptyPanel(Symbol: "square.stack.3d.up", Title: "Your next game is waiting", Message: Store.CatalogWarning ?? "Load the Ascendara index or import your own source to start browsing.", ActionTitle: "Refresh game index", Action: Store.RefreshCatalog)
                HStack {
                    Button("Manage sources") { Store.CurrentRoute = .Sources }.buttonStyle(SecondaryButtonStyle())
                    Button("Import index…") { Store.ImportCatalog() }.buttonStyle(SecondaryButtonStyle())
                    Button("Open library") { Store.CurrentRoute = .Library }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 60)
    }
}

struct SearchView: View {
    @EnvironmentObject var Store: AppStore
    @State private var ShowFilters = false
    @State private var VisibleCount = 80
    private var Results: [Game] { Store.FilteredGames }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    PageHeading(Title: "Search", Subtitle: "Find something worth playing.")
                    IconButton(Symbol: "arrow.clockwise", Help: "Refresh game index", Action: Store.RefreshCatalog)
                }
                SearchField(Text: $Store.SearchQuery, Placeholder: "Search \(Store.Games.count.formatted()) games…")
                HStack(spacing: 16) {
                    Picker("Genre", selection: $Store.SelectedGenre) {
                        ForEach(Store.Genres, id: \.self) { Genre in Text(Genre).tag(Genre) }
                    }.frame(width: 220)
                    Picker("Sort", selection: $Store.SortOrder) {
                        ForEach(["Relevance", "Name A–Z", "Recently updated", "Smallest size"], id: \.self) { Order in Text(Order).tag(Order) }
                    }.frame(width: 230)
                    Toggle("Online", isOn: $Store.OnlineOnly).toggleStyle(.checkbox)
                    Toggle("Includes DLC", isOn: $Store.DlcOnly).toggleStyle(.checkbox)
                    Button { ShowFilters.toggle() } label: { Label("Filters", systemImage: "line.3.horizontal.decrease.circle") }.buttonStyle(MotionButtonStyle()).foregroundStyle(Theme.Accent)
                    Spacer()
                    Text("\(Results.count.formatted()) games").font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                }
                if ShowFilters {
                    Panel(Padding: 16) {
                        HStack(spacing: 22) {
                            Picker("Provider", selection: $Store.SelectedProvider) {
                                ForEach(Store.Providers, id: \.self) { Provider in Text(Provider).tag(Provider) }
                            }.frame(width: 230)
                            Toggle("Verified games", isOn: $Store.VerifiedOnly).toggleStyle(.checkbox)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(Store.MaximumSizeGB == 0 ? "Maximum size: Any" : "Maximum size: \(Int(Store.MaximumSizeGB)) GB").font(.system(size: 11))
                                Slider(value: $Store.MaximumSizeGB, in: 0...250, step: 5).frame(width: 180)
                            }
                            Spacer()
                            Button("Reset") { ResetFilters() }.buttonStyle(MotionButtonStyle()).foregroundStyle(Theme.Accent)
                        }
                    }.MotionTransition(Distance: -6)
                }
                if let Warning = Store.CatalogWarning { Notice(Message: Warning) }
                if Store.Games.isEmpty { CatalogEmptyView() }
                else if Results.isEmpty {
                    EmptyPanel(Symbol: "magnifyingglass", Title: "No games found", Message: "Try another title or clear your filters.", ActionTitle: "Clear filters") {
                        Store.SearchQuery = ""; ResetFilters()
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 225), spacing: 18)], spacing: 20) {
                        ForEach(Array(Results.prefix(VisibleCount))) { Game in GameCard(Game: Game) }
                    }
                    if Results.count > VisibleCount {
                        Button("Load more games") { VisibleCount += 80 }.buttonStyle(SecondaryButtonStyle()).frame(maxWidth: .infinity)
                    }
                }
            }.padding(30).padding(.bottom, 100).frame(maxWidth: 1500).frame(maxWidth: .infinity)
        }.MotionAnimation(ShowFilters)
            .onChange(of: Store.SearchQuery) { _, _ in VisibleCount = 80 }
            .onChange(of: Store.SelectedGenre) { _, _ in VisibleCount = 80 }
    }
    private func ResetFilters() {
        Store.SelectedGenre = "All genres"
        Store.OnlineOnly = false
        Store.DlcOnly = false
        Store.VerifiedOnly = false
        Store.SelectedProvider = "All providers"
        Store.MaximumSizeGB = 0
    }
}

struct WishlistView: View {
    @EnvironmentObject var Store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(Title: "Play Later", Subtitle: "\(Store.WishlistGames.count) games saved for your next adventure.")
                if Store.WishlistGames.isEmpty {
                    EmptyPanel(Symbol: "bookmark", Title: "Make room for your next adventure", Message: "Save games from Search or their detail page. Your list stays on this Mac.", ActionTitle: "Explore games") { Store.CurrentRoute = .Search }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 235), spacing: 18)], spacing: 20) {
                        ForEach(Store.WishlistGames) { Game in GameCard(Game: Game) }
                    }
                }
            }.padding(30).padding(.bottom, 100).frame(maxWidth: 1500).frame(maxWidth: .infinity)
        }
    }
}
