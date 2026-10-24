import SwiftUI

struct TVHomeView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.TVScale) private var Scale

    @State private var Slide = 0
    private var Featured: [Game] { Store.HomeCatalog.TVFeatured }
    private var Slides: [Game] { Array(Featured.prefix(6)) }
    private var FeaturedGame: Game? { Slides.isEmpty ? nil : Slides[min(Slide, Slides.count - 1)] }
    private var Recent: [LibraryGame] {
        Array(Store.Library.filter { $0.LastPlayedAt != nil }.sorted {
            ($0.LastPlayedAt ?? .distantPast) > ($1.LastPlayedAt ?? .distantPast)
        }.prefix(16))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34 * Scale) {
                if let Game = FeaturedGame {
                    TVGamesHero(Name: Game.Name, Eyebrow: "FEATURED", Summary: Game.Description ?? "Discover the game, explore its details, and make it your next adventure.", Artwork: Game.ArtworkURL) {
                        if let Installed = Store.LibraryMatch(Game) {
                            TVLaunchButton(Game: Installed)
                        } else {
                            Button { Store.OpenGame(Game) } label: { Label("View Game", systemImage: "play.fill") }
                                .buttonStyle(TVButtonStyle(Prominent: true))
                        }
                        Button { Store.ToggleWishlist(Game) } label: {
                            Label(Store.Wishlist.contains(Game.Id) ? "Saved" : "Play Later", systemImage: Store.Wishlist.contains(Game.Id) ? "checkmark" : "plus")
                        }.buttonStyle(TVButtonStyle())
                    }
                    .id(Game.Id).MotionTransition(Distance: 0)
                    .overlay(alignment: .bottomTrailing) { Carousel.padding(.trailing, 40 * Scale).padding(.bottom, 15 * Scale) }
                } else {
                    VStack(alignment: .leading, spacing: 24 * Scale) {
                        TVPageHeading(Title: "Your next game starts here", Subtitle: "Explore your catalogue or jump into your library.")
                        if Store.IsLoading { ProgressView("Loading catalogue…").font(.system(size: 22 * Scale)) }
                        HStack(spacing: 16 * Scale) {
                            Button("Open Library") { Store.Route = .Library }.buttonStyle(TVButtonStyle(Prominent: true))
                            Button("Refresh Catalogue") { Store.RefreshCatalog() }.buttonStyle(TVButtonStyle())
                            Button("Sources") { Store.Route = .Sources }.buttonStyle(TVButtonStyle())
                        }
                    }.padding(40 * Scale).frame(minHeight: 330 * Scale, alignment: .leading)
                }
                if !Recent.isEmpty {
                    VStack(alignment: .leading, spacing: 18 * Scale) {
                        TVGamesSectionTitle(Title: "Continue playing", ActionTitle: "Your library") { Store.Route = .Library }
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 20 * Scale) {
                                ForEach(Recent) { Game in
                                    TVGameTile(Name: Game.Name, Subtitle: "\(FormatPlayTime(Game.PlayTimeSeconds)) played", Artwork: Game.ArtworkURL, Width: 300 * Scale) {
                                        if let Match = Store.Games.first(where: { $0.Id == Game.CatalogId || $0.Name.caseInsensitiveCompare(Game.Name) == .orderedSame }) {
                                            Store.OpenGame(Match)
                                        } else {
                                            Store.SelectedLibraryId = Game.Id
                                            Store.Route = .Library
                                        }
                                    }
                                }
                            }.padding(.horizontal, 40 * Scale).padding(.vertical, 8 * Scale)
                        }.scrollIndicators(.hidden)
                    }
                }
                if !Featured.isEmpty {
                    TVCatalogueShelf(Title: "Featured games", Games: Featured, ActionTitle: "Browse all") { Store.Route = .Search }
                }
                if !Store.WishlistGames.isEmpty {
                    TVCatalogueShelf(Title: "Play later", Games: Array(Store.WishlistGames.prefix(16)), ActionTitle: "Your list") { Store.Route = .Wishlist }
                }
                if let Warning = Store.CatalogWarning {
                    Label(Warning, systemImage: "info.circle")
                        .font(.system(size: 18 * Scale)).foregroundStyle(TVStyle.Secondary)
                        .padding(.horizontal, 40 * Scale)
                }
            }.padding(.bottom, 44 * Scale)
        }.background(TVStyle.Background).foregroundStyle(TVStyle.Text)
            .MotionAnimation(Slide)
            .onChange(of: Slides.map(\.Id)) { _, Ids in Slide = min(Slide, max(0, Ids.count - 1)) }
    }

    private var Carousel: some View {
        HStack(spacing: 12 * Scale) {
            Button { MoveSlide(-1) } label: { Image(systemName: "chevron.left").frame(width: 42 * Scale, height: 42 * Scale) }
                .accessibilityLabel("Previous featured game")
            ForEach(Array(Slides.enumerated()), id: \.element.Id) { Index, Game in
                Button { Slide = Index } label: {
                    Capsule().fill(Slide == Index ? .white : .white.opacity(0.3))
                        .frame(width: (Slide == Index ? 24 : 8) * Scale, height: 8 * Scale)
                        .frame(minWidth: 28 * Scale, minHeight: 42 * Scale)
                }.accessibilityLabel("Feature \(Game.Name)").accessibilityAddTraits(Slide == Index ? .isSelected : [])
            }
            Button { MoveSlide(1) } label: { Image(systemName: "chevron.right").frame(width: 42 * Scale, height: 42 * Scale) }
                .accessibilityLabel("Next featured game")
        }.buttonStyle(MotionButtonStyle()).font(.system(size: 18 * Scale, weight: .semibold))
            .foregroundStyle(.white).padding(.horizontal, 10 * Scale)
            .background(.black.opacity(0.3), in: Capsule())
    }

    private func MoveSlide(_ Offset: Int) {
        guard !Slides.isEmpty else { return }
        Slide = (Slide + Offset + Slides.count) % Slides.count
    }
}

struct TVLibraryView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.TVScale) private var Scale
    @State private var Scope = "All games"
    @State private var Query = ""
    @State private var Editor: LibraryGame?
    @State private var ShowingUpdates = false

    private var Games: [LibraryGame] {
        Store.Library.filter { Game in
            (Query.isEmpty || Game.Name.localizedCaseInsensitiveContains(Query)) &&
            (Scope != "Favorites" || Game.Favorite) &&
            (Scope != "Recently played" || Game.LastPlayedAt != nil) &&
            (!Scope.hasPrefix("Collection: ") || Game.Collection == String(Scope.dropFirst(12)))
        }.sorted { ($0.LastPlayedAt ?? $0.AddedAt) > ($1.LastPlayedAt ?? $1.AddedAt) }
    }
    private var Selected: LibraryGame? { Games.first { $0.Id == Store.SelectedLibraryId } ?? Games.first }
    private var Collections: [String] { Array(Set(Store.Library.map(\.Collection).filter { !$0.isEmpty })).sorted() }

    var body: some View {
        ScrollViewReader { Reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 28 * Scale) {
                    HStack(spacing: 16 * Scale) {
                        TVPageHeading(Title: "Your library", Subtitle: "\(Store.Library.count) games, ready when you are.")
                        Spacer(minLength: 0)
                        Button { Store.ImportGame() } label: { Label("Add Game", systemImage: "plus") }
                            .buttonStyle(TVButtonStyle(Prominent: true))
                        Menu {
                            Button("Check updates") { ShowingUpdates = true }
                            Button("Scan Steam library") { Store.ScanSteamLibrary() }
                            Button("Import library…") { Store.ImportLibrary() }
                            Button("Export library…") { Store.ExportLibrary() }
                            Button("Import legacy library…") { Store.ImportLegacyLibrary() }
                        } label: {
                            Label("Manage", systemImage: "ellipsis")
                                .padding(12 * Scale)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton).font(.system(size: 20 * Scale)).fixedSize()
                    }.padding(.horizontal, 40 * Scale).padding(.top, 28 * Scale)
                    if let Game = Selected {
                        TVGamesHero(Name: Game.Name,
                                    Eyebrow: Store.IsRunning(Game) ? "NOW PLAYING" : "\(FormatPlayTime(Game.PlayTimeSeconds)) PLAYED · \(Game.LaunchMode.rawValue.uppercased())",
                                    Summary: Game.Notes.isEmpty ? (Game.IsInstalled ? "Choose a game, settle in, and play." : "Game files are missing. Choose an executable in Game Options.") : Game.Notes,
                                    Artwork: Game.ArtworkURL, Height: 460) {
                            TVLaunchButton(Game: Game)
                            Button { Editor = Game } label: { Label("Game Options", systemImage: "slider.horizontal.3") }
                                .buttonStyle(TVButtonStyle())
                            Button { Store.ToggleLibraryFavorite(Game) } label: { Image(systemName: Game.Favorite ? "star.fill" : "star") }
                                .buttonStyle(TVButtonStyle()).accessibilityLabel(Game.Favorite ? "Remove favorite" : "Add favorite")
                        }.id("LibraryHero")
                    }
                    VStack(alignment: .leading, spacing: 20 * Scale) {
                        TVGameSearchField(Text: $Query, Placeholder: "Search your library")
                        ScrollView(.horizontal) {
                            HStack(spacing: 12 * Scale) {
                                ForEach(["All games", "Favorites", "Recently played"], id: \.self) { Value in
                                    Button(Value) { Scope = Value }.buttonStyle(TVButtonStyle(Selected: Scope == Value))
                                }
                                ForEach(Collections, id: \.self) { Collection in
                                    Button(Collection) { Scope = "Collection: " + Collection }
                                        .buttonStyle(TVButtonStyle(Selected: Scope == "Collection: " + Collection))
                                }
                            }.padding(.vertical, 5 * Scale)
                        }.scrollIndicators(.hidden)
                    }.padding(.horizontal, 40 * Scale)
                    if Games.isEmpty {
                        TVEmptyState(Symbol: "books.vertical", Title: Store.Library.isEmpty ? "Make room for your next adventure" : "No games found", Message: Store.Library.isEmpty ? "Add a game on your Mac to get started." : "Try another search or collection.")
                            .padding(.horizontal, 40 * Scale)
                    } else {
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 20 * Scale) {
                                ForEach(Games) { Game in
                                    TVGameTile(Name: Game.Name, Subtitle: Game.Favorite ? "Favorite · \(FormatPlayTime(Game.PlayTimeSeconds)) played" : "\(FormatPlayTime(Game.PlayTimeSeconds)) played", Artwork: Game.ArtworkURL, Width: 310 * Scale) {
                                        Store.SelectedLibraryId = Game.Id
                                        Reader.scrollTo("LibraryHero", anchor: .top)
                                    }
                                    .overlay(RoundedRectangle(cornerRadius: 12 * Scale).stroke(Game.Id == Selected?.Id ? TVStyle.Accent : .clear, lineWidth: 3))
                                }
                            }.padding(.horizontal, 40 * Scale).padding(.vertical, 8 * Scale)
                        }.scrollIndicators(.hidden)
                        if let Game = Selected {
                            HStack(spacing: 14 * Scale) {
                                Button("Show in Finder") { Store.RevealGame(Game) }.buttonStyle(TVButtonStyle())
                                Button("Create Backup") { Store.CreateBackup(Game) }.buttonStyle(TVButtonStyle())
                                Menu("More") {
                                    Button("Restore backup…") { Store.RestoreBackup(Game) }
                                    Button("Choose executable…") { Store.SetExecutable(Game) }
                                    Button("Remove from library…", role: .destructive) { Store.RemoveGame(Game) }
                                }.menuStyle(.borderlessButton).font(.system(size: 20 * Scale)).fixedSize()
                            }.padding(.horizontal, 40 * Scale)
                        }
                    }
                }.padding(.bottom, 44 * Scale)
            }
        }
        .background(TVStyle.Background).foregroundStyle(TVStyle.Text)
        .sheet(item: $Editor) { Game in LibraryEditorView(Game: Game).environmentObject(Store) }
        .sheet(isPresented: $ShowingUpdates) { LibraryUpdatesView().environmentObject(Store) }
        .onChange(of: Store.Library.map(\.Id)) { _, Ids in if let Id = Store.SelectedLibraryId, !Ids.contains(Id) { Store.SelectedLibraryId = nil } }
    }
}

struct TVSearchView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.TVScale) private var Scale
    var Wishlist = false
    @State private var ShowingFilters = false
    private var Games: [Game] { Wishlist ? Store.FilteredGames.filter { Store.Wishlist.contains($0.Id) } : Store.FilteredGames }

    var body: some View {
        GeometryReader { Geometry in
            let Columns = Geometry.size.width >= 1450 * Scale ? 4 : Geometry.size.width >= 960 * Scale ? 3 : 2
            let TileWidth = max(1, (Geometry.size.width - 80 * Scale - CGFloat(Columns - 1) * 22 * Scale) / CGFloat(Columns))
            ScrollView {
                VStack(alignment: .leading, spacing: 28 * Scale) {
                    TVPageHeading(Title: Wishlist ? "Play later" : "Find your next game", Subtitle: Wishlist ? "Your saved games, all in one place." : "Explore \(Store.Games.count.formatted()) games.")
                    TVGameSearchField(Text: $Store.SearchQuery, Placeholder: Wishlist ? "Search your saved games" : "Search games, worlds, and adventures")
                    ScrollView(.horizontal) {
                        HStack(spacing: 12 * Scale) {
                            ForEach(Store.Genres, id: \.self) { Genre in
                                Button(Genre) { Store.SelectedGenre = Genre }
                                    .buttonStyle(TVButtonStyle(Selected: Store.SelectedGenre == Genre))
                            }
                        }.padding(.vertical, 5 * Scale)
                    }.scrollIndicators(.hidden)
                    HStack(spacing: 18 * Scale) {
                        Text("\(Games.count.formatted()) games").font(.system(size: 23 * Scale, weight: .semibold))
                        Spacer()
                        Menu {
                            ForEach(["Relevance", "Name A–Z", "Recently updated", "Smallest size"], id: \.self) { Order in
                                Button(Order) { Store.SortOrder = Order }
                            }
                        } label: {
                            Label(Store.SortOrder, systemImage: "arrow.up.arrow.down")
                                .padding(12 * Scale)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton).font(.system(size: 20 * Scale)).fixedSize()
                        Button { ShowingFilters.toggle() } label: { Label("Filters", systemImage: "line.3.horizontal.decrease") }
                            .buttonStyle(TVButtonStyle(Selected: ShowingFilters))
                    }
                    if ShowingFilters { Filters }
                    if Games.isEmpty {
                        TVEmptyState(Symbol: Wishlist ? "bookmark" : "magnifyingglass", Title: Wishlist ? "Nothing saved here yet" : "No games found", Message: Wishlist ? "Save a game with Play Later, or clear your search filters." : "Try another title, genre, or source.")
                        Button("Clear Filters", action: ClearFilters).buttonStyle(TVButtonStyle(Prominent: true))
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 22 * Scale), count: Columns), spacing: 28 * Scale) {
                            ForEach(Games) { Game in
                                TVGameTile(Name: Game.Name, Subtitle: Game.Categories.prefix(2).joined(separator: " · "), Artwork: Game.ArtworkURL, Width: TileWidth) {
                                    Store.OpenGame(Game)
                                }
                            }
                        }
                    }
                }.padding(40 * Scale)
            }
        }.background(TVStyle.Background).foregroundStyle(TVStyle.Text)
    }

    private var Filters: some View {
        VStack(alignment: .leading, spacing: 20 * Scale) {
            ScrollView(.horizontal) {
                HStack(spacing: 12 * Scale) {
                    Button("Online") { Store.OnlineOnly.toggle() }.buttonStyle(TVButtonStyle(Selected: Store.OnlineOnly))
                    Button("Includes DLC") { Store.DlcOnly.toggle() }.buttonStyle(TVButtonStyle(Selected: Store.DlcOnly))
                    Button("Verified") { Store.VerifiedOnly.toggle() }.buttonStyle(TVButtonStyle(Selected: Store.VerifiedOnly))
                    Menu {
                        ForEach(Store.Providers, id: \.self) { Provider in Button(Provider) { Store.SelectedProvider = Provider } }
                    } label: {
                        Label(Store.SelectedProvider, systemImage: "externaldrive")
                            .padding(12 * Scale)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton).font(.system(size: 20 * Scale)).fixedSize()
                }.padding(.vertical, 4 * Scale)
            }.scrollIndicators(.hidden)
            HStack(spacing: 20 * Scale) {
                Text(Store.MaximumSizeGB == 0 ? "Any download size" : "Up to \(Int(Store.MaximumSizeGB)) GB")
                    .font(.system(size: 19 * Scale)).frame(width: 230 * Scale, alignment: .leading)
                Slider(value: $Store.MaximumSizeGB, in: 0...300, step: 5).accessibilityLabel("Maximum download size")
                Button("Reset", action: ClearFilters).buttonStyle(TVButtonStyle())
            }
        }.padding(24 * Scale).background(TVStyle.Panel, in: RoundedRectangle(cornerRadius: 16 * Scale))
    }

    private func ClearFilters() {
        Store.SearchQuery = ""
        Store.SelectedGenre = "All genres"
        Store.OnlineOnly = false
        Store.DlcOnly = false
        Store.VerifiedOnly = false
        Store.SelectedProvider = "All providers"
        Store.MaximumSizeGB = 0
    }
}

struct TVGamesHero<ActionContent: View>: View {
    @Environment(\.TVScale) private var Scale
    let Name: String
    let Eyebrow: String
    let Summary: String
    let Artwork: URL?
    var Height: CGFloat = 490
    @ViewBuilder let Actions: ActionContent

    var body: some View {
        GeometryReader { Geometry in
            ZStack(alignment: .leading) {
                TVBackdrop(URL: Artwork, Name: Name)
                VStack(alignment: .leading, spacing: 22 * Scale) {
                    Text(Eyebrow).font(.system(size: 15 * Scale, weight: .bold)).tracking(2 * Scale)
                        .lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(TVStyle.Accent)
                    Text(Name).font(.system(size: 60 * Scale, weight: .bold))
                        .lineLimit(2).minimumScaleFactor(0.72).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(TVStyle.Text).accessibilityAddTraits(.isHeader)
                    Text(Summary).font(.system(size: 21 * Scale)).lineSpacing(4 * Scale)
                        .lineLimit(3).foregroundStyle(TVStyle.Secondary)
                    HStack(spacing: 16 * Scale) { Actions }.padding(.top, 8 * Scale)
                }
                .frame(maxWidth: Geometry.size.width * 0.64, alignment: .leading)
                .padding(.leading, 40 * Scale).padding(.vertical, 34 * Scale)
            }
        }.frame(height: Height * Scale)
    }
}

struct TVLaunchButton: View {
    @EnvironmentObject private var Store: AppStore
    let Game: LibraryGame
    var body: some View {
        let Running = Store.IsRunning(Game)
        let Busy = Store.BusyGameIds.contains(Game.Id)
        Button { Running ? Store.StopGame(Game) : Store.LaunchGame(Game) } label: {
            Label(Busy ? "Please Wait…" : Running ? "Stop Game" : "Play Now", systemImage: Running ? "stop.fill" : "play.fill")
        }
        .buttonStyle(TVButtonStyle(Prominent: true))
        .disabled(Busy || (!Running && !Game.IsInstalled))
    }
}

struct TVGameSearchField: View {
    @Environment(\.TVScale) private var Scale
    @Binding var Text: String
    let Placeholder: String
    var body: some View {
        HStack(spacing: 18 * Scale) {
            Image(systemName: "magnifyingglass").foregroundStyle(TVStyle.Secondary)
            TextField(Placeholder, text: $Text).textFieldStyle(.plain)
            if !Text.isEmpty {
                Button { Text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .font(.system(size: 26 * Scale)).foregroundStyle(TVStyle.Text)
        .padding(22 * Scale).background(TVStyle.Panel, in: RoundedRectangle(cornerRadius: 12 * Scale))
        .overlay(RoundedRectangle(cornerRadius: 12 * Scale).stroke(TVStyle.Secondary.opacity(0.3)))
    }
}

private struct TVGamesSectionTitle: View {
    @Environment(\.TVScale) private var Scale
    let Title: String
    let ActionTitle: String
    let Action: () -> Void
    var body: some View {
        HStack {
            Text(Title).font(.system(size: 27 * Scale, weight: .semibold))
            Spacer()
            Button(action: Action) { Label(ActionTitle, systemImage: "chevron.right") }.buttonStyle(TVButtonStyle())
        }.padding(.horizontal, 40 * Scale)
    }
}

private struct TVCatalogueShelf: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.TVScale) private var Scale
    let Title: String
    let Games: [Game]
    let ActionTitle: String
    let Action: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18 * Scale) {
            TVGamesSectionTitle(Title: Title, ActionTitle: ActionTitle, Action: Action)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 20 * Scale) {
                    ForEach(Games) { Game in
                        TVGameTile(Name: Game.Name, Subtitle: Game.Categories.prefix(2).joined(separator: " · "), Artwork: Game.ArtworkURL, Width: 300 * Scale) { Store.OpenGame(Game) }
                    }
                }.padding(.horizontal, 40 * Scale).padding(.vertical, 8 * Scale)
            }.scrollIndicators(.hidden)
        }
    }
}
