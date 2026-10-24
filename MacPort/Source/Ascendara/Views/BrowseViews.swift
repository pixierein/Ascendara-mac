import SwiftUI

struct HomeView: View {
    @EnvironmentObject var Store: AppStore

    var body: some View {
        GeometryReader { Geometry in
            let Home = Store.HomeCatalog
            let Width = max(0, Geometry.size.width - 56)
            let CardWidth = max(240, (Width - 54) / 3.6)
            ScrollView {
                VStack(alignment: .leading, spacing: 38) {
                    if !Home.Highlights.isEmpty {
                        HomeFeaturedSection(Games: Home.Highlights, Width: Width)
                    }
                    if Store.Settings.ShowHomeSearchBar { QuickActions(Width: Width) }
                    if Store.Games.isEmpty {
                        CatalogEmptyView()
                    } else {
                        GameRow(Title: "Top Games", Subtitle: "", Symbol: "arrow.up.right", Games: Home.Top, TotalCount: Store.Games.count, CardWidth: CardWidth) {
                            OpenSearch()
                        }
                        GameRow(Title: "Most Recently Updated", Subtitle: "", Symbol: "arrow.triangle.2.circlepath", Games: Home.Updated, TotalCount: Home.UpdatedCount, CardWidth: CardWidth) {
                            OpenSearch(Sort: "Recently updated")
                        }
                        GameRow(Title: "Online Games", Subtitle: "", Symbol: "globe", Games: Home.Online, TotalCount: Home.OnlineCount, CardWidth: CardWidth) {
                            OpenSearch(Online: true)
                        }
                        GameRow(Title: "Action Games", Subtitle: "", Symbol: "bolt", Games: Home.Action, TotalCount: Home.ActionCount, CardWidth: CardWidth) {
                            OpenSearch(Genre: Home.Categories.first { $0.Name.caseInsensitiveCompare("Action") == .orderedSame }?.Name ?? "Action")
                        }
                        if !Home.Categories.isEmpty {
                            VStack(alignment: .leading, spacing: 26) {
                                HStack(spacing: 14) {
                                    HeadingIcon("flame")
                                    Text("Popular Categories").font(.system(size: 23, weight: .bold))
                                }
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 22), count: 3), spacing: 22) {
                                    ForEach(Home.Categories, id: \.Name) { Category in CategoryCard(Category) }
                                }
                            }.padding(.top, 6)
                        }
                    }
                    Footer.padding(.top, 12)
                }
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 115)
                .frame(maxWidth: .infinity)
            }
        }.background(Theme.Background).foregroundStyle(Theme.Foreground)
    }

    private func QuickActions(Width: CGFloat) -> some View {
        HStack(spacing: 16) {
            Rectangle().fill(Theme.Border.opacity(0.55)).frame(height: 1)
            HStack(spacing: 12) {
                Button { OpenSearch() } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "magnifyingglass").font(.system(size: 23, weight: .regular))
                            .foregroundStyle(Theme.Accent).frame(width: 48, height: 48)
                            .background(Theme.Accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Search for games...").font(.system(size: 18, weight: .medium))
                            Text("Press to start searching").font(.system(size: 12)).foregroundStyle(Theme.SecondaryText.opacity(0.65))
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 20).frame(maxWidth: .infinity).frame(height: 86)
                        .background(Theme.Card.opacity(0.65), in: RoundedRectangle(cornerRadius: 17))
                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Theme.Border.opacity(0.45), lineWidth: 2))
                        .shadow(color: Theme.Accent.opacity(0.05), radius: 3, y: 2)
                }.buttonStyle(MotionButtonStyle())
                QuickLink("Library", "books.vertical") { Store.CurrentRoute = .Library }
                QuickLink("Discord", "bubble") { Store.OpenExternal("https://ascendara.app/discord") }
                QuickLink("Help", "questionmark.circle") { Store.OpenExternal("https://ascendara.app/docs") }
            }.frame(width: min(Width, max(760, Width * 0.82)))
            Rectangle().fill(Theme.Border.opacity(0.55)).frame(height: 1)
        }
        .padding(.bottom, 2)
    }

    private func QuickLink(_ Title: String, _ Symbol: String, Action: @escaping () -> Void) -> some View {
        Button(action: Action) {
            VStack(spacing: 8) {
                Image(systemName: Symbol).font(.system(size: 18))
                    .foregroundStyle(Theme.Accent).frame(width: 36, height: 36)
                    .background(Theme.Accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                Text(Title).font(.system(size: 12, weight: .medium))
            }.frame(width: 78, height: 86)
                .background(Theme.Card.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Border.opacity(0.45), lineWidth: 2))
                .shadow(color: Theme.Accent.opacity(0.05), radius: 3, y: 2)
        }.buttonStyle(MotionButtonStyle())
    }

    private func HeadingIcon(_ Symbol: String) -> some View {
        Image(systemName: Symbol).font(.system(size: 19, weight: .medium)).foregroundStyle(Theme.Accent)
            .frame(width: 42, height: 42).background(Theme.Accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private func CategoryCard(_ Category: HomeCategorySection) -> some View {
        return VStack(alignment: .leading, spacing: 18) {
            Button { OpenSearch(Genre: Category.Name) } label: {
                HStack(spacing: 13) {
                    HeadingIcon("gamecontroller")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Category.Name).font(.system(size: 18, weight: .semibold))
                        Text("\(Category.Count) games").font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(MotionButtonStyle()).help("Browse \(Category.Name) games")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Category.Preview) { Game in
                    Button { Store.OpenGame(Game) } label: {
                        ZStack(alignment: .bottomLeading) {
                            GameArtwork(URL: Game.ArtworkURL, Name: Game.Name, CornerRadius: 8)
                            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                            Text(Game.Name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                                .foregroundStyle(.white).padding(8)
                        }.aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(MotionButtonStyle()).help(Game.Name).accessibilityLabel(Game.Name)
                }
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Card.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Border.opacity(0.13)))
        .shadow(color: .black.opacity(0.045), radius: 3, y: 2)
    }

    private var Footer: some View {
        VStack(spacing: 24) {
            Rectangle().fill(Theme.Border.opacity(0.4)).frame(height: 1).padding(.bottom, 18)
            Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.Accent).frame(width: 66, height: 66)
                .background(Theme.Accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
            Text("Consider Spreading the Word").font(.system(size: 23, weight: .semibold))
            Text("Sharing Ascendara with others helps the project grow and reach more players.")
                .font(.system(size: 15)).foregroundStyle(Theme.SecondaryText)
                .multilineTextAlignment(.center).lineSpacing(5).frame(maxWidth: 820)
            HStack(spacing: 36) {
                Button { Store.OpenExternal("https://www.ascendara.app/support") } label: { Label("Support Development", systemImage: "heart") }
                Button { Store.OpenExternal("https://github.com/pixierein/ascendara") } label: { Label("View on GitHub", systemImage: "arrow.up.right.square") }
            }.buttonStyle(MotionButtonStyle()).font(.system(size: 15, weight: .medium)).padding(.vertical, 12)
            VStack(spacing: 8) {
                Text("Made with <3 by Santiago & Contributors")
                Text("macOS port by Aether")
            }.font(.system(size: 12)).foregroundStyle(Theme.SecondaryText.opacity(0.65))
        }.frame(maxWidth: .infinity).padding(.bottom, 24)
    }

    private func OpenSearch(Genre: String = "All genres", Sort: String = "Relevance", Online: Bool = false) {
        Store.SearchQuery = ""
        Store.SelectedGenre = Genre
        Store.SortOrder = Sort
        Store.OnlineOnly = Online
        Store.DlcOnly = false
        Store.VerifiedOnly = false
        Store.SelectedProvider = "All providers"
        Store.MaximumSizeGB = 0
        Store.CurrentRoute = .Search
    }
}

struct HomeFeaturedSection: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.MotionEnabled) private var MotionEnabled
    @State private var Slide = 0
    let Games: [Game]
    let Width: CGFloat
    private var Featured: Game { Games[min(Slide, Games.count - 1)] }
    private var Recent: [LibraryGame] {
        Array(Store.Library.filter { $0.LastPlayedAt != nil }.sorted {
            ($0.LastPlayedAt ?? .distantPast) > ($1.LastPlayedAt ?? .distantPast)
        }.prefix(3))
    }

    var body: some View {
        let Height = min(490, max(350, Width * 0.37))
        HStack(alignment: .top, spacing: 18) {
            ZStack(alignment: .bottomLeading) {
                GameArtwork(URL: Featured.ArtworkURL, Name: Featured.Name, CornerRadius: 19)
                LinearGradient(colors: [.clear, .black.opacity(0.32), .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 16) {
                    Spacer()
                    if Featured.Online {
                        Label("Online", systemImage: "globe")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                    }
                    Text(Featured.Name).font(.system(size: min(37, max(26, Width * 0.025)), weight: .bold))
                        .lineLimit(2).shadow(color: .black.opacity(0.7), radius: 6)
                    HStack(spacing: 8) {
                        ForEach(Array(Featured.Categories.prefix(4)), id: \.self) { Category in
                            Text(Category).font(.system(size: 12)).lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.black.opacity(0.56), in: Capsule())
                        }
                    }
                    HStack(alignment: .bottom) {
                        Button { Store.OpenGame(Featured) } label: {
                            Text("View Game").font(.system(size: 14, weight: .semibold))
                                .frame(minWidth: 130).padding(.vertical, 11)
                        }.buttonStyle(PrimaryButtonStyle())
                        Spacer()
                        Carousel
                    }
                }.foregroundStyle(.white).padding(26)
            }
            .frame(width: max(0, Width * 0.66), height: Height)
            .clipShape(RoundedRectangle(cornerRadius: 19))
            .id(Featured.Id)
            .MotionTransition(Distance: 0)
            RecentPanel.frame(width: max(0, Width * 0.34 - 18), height: Height)
        }
        .frame(width: Width)
        .MotionAnimation(Slide)
        .onChange(of: Games.map(\.Id)) { _, _ in Slide = min(Slide, max(0, Games.count - 1)) }
    }

    private var Carousel: some View {
        HStack(spacing: 5) {
            Button { Move(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 34, height: 34)
                    .background(.black.opacity(0.58), in: Circle())
            }.accessibilityLabel("Previous highlighted game")
            ForEach(Array(Games.enumerated()), id: \.element.Id) { Index, Game in
                Button { Slide = Index } label: {
                    Capsule().fill(Slide == Index ? Theme.Accent : .white.opacity(0.56))
                        .frame(width: Slide == Index ? 24 : 6, height: 6)
                        .frame(minWidth: Slide == Index ? 24 : 15, minHeight: 34)
                }.accessibilityLabel("Show \(Game.Name)")
                    .accessibilityAddTraits(Slide == Index ? .isSelected : [])
            }
            Button { Move(1) } label: {
                Image(systemName: "chevron.right").frame(width: 34, height: 34)
                    .background(.black.opacity(0.58), in: Circle())
            }.accessibilityLabel("Next highlighted game")
        }.buttonStyle(MotionButtonStyle())
    }

    private var RecentPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Recent Games", systemImage: "play")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.Foreground)
            if Recent.isEmpty {
                VStack(spacing: 9) {
                    Spacer()
                    Image(systemName: "play").font(.system(size: 28, weight: .light))
                    Text("Your top 3 recent games show here").font(.system(size: 13, weight: .medium))
                    Text("Start playing to see your games").font(.system(size: 12)).opacity(0.65)
                    Spacer()
                }.frame(maxWidth: .infinity)
                    .foregroundStyle(Theme.SecondaryText)
                    .background(Theme.Card.opacity(0.4), in: RoundedRectangle(cornerRadius: 17))
                    .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Theme.Border.opacity(0.75), style: StrokeStyle(lineWidth: 1.3, dash: [5, 4])))
            } else {
                VStack(spacing: 9) {
                    ForEach(Recent) { Game in
                        Button { OpenRecent(Game) } label: {
                            HStack(spacing: 10) {
                                GameArtwork(URL: Game.ArtworkURL, Name: Game.Name, CornerRadius: 7)
                                    .frame(width: 80, height: 49)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(Game.Name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    if let LastPlayed = Game.LastPlayedAt {
                                        Text("Played \(LastPlayed.formatted(.relative(presentation: .named)))")
                                            .font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 10))
                            }.padding(8).background(Theme.Card.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(MotionButtonStyle())
                    }
                    Spacer(minLength: 0)
                    Button { Store.CurrentRoute = .Library } label: { Label("Open Library", systemImage: "books.vertical") }
                        .buttonStyle(MotionButtonStyle()).font(.system(size: 12, weight: .medium))
                }.padding(13).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Card.opacity(0.4), in: RoundedRectangle(cornerRadius: 17))
                    .overlay(RoundedRectangle(cornerRadius: 17).stroke(Theme.Border.opacity(0.55)))
            }
        }
    }

    private func Move(_ Offset: Int) {
        guard !Games.isEmpty else { return }
        withAnimation(MotionEnabled ? AppMotion.Standard : nil) {
            Slide = (Slide + Offset + Games.count) % Games.count
        }
    }

    private func OpenRecent(_ Game: LibraryGame) {
        if let Match = Store.Games.first(where: { $0.Id == Game.CatalogId || $0.Name.caseInsensitiveCompare(Game.Name) == .orderedSame }) {
            Store.OpenGame(Match)
        } else {
            Store.SelectedLibraryId = Game.Id
            Store.CurrentRoute = .Library
        }
    }
}

struct GameRow: View {
    @EnvironmentObject var Store: AppStore
    @Environment(\.MotionEnabled) private var MotionEnabled
    @State private var Position: String?
    let Title: String
    let Subtitle: String
    let Symbol: String
    let Games: [Game]
    var TotalCount: Int? = nil
    var CardWidth: CGFloat = 280
    var Action: (() -> Void)? = nil
    private var Index: Int { Games.firstIndex { $0.Id == Position } ?? 0 }
    private var Count: String { "\(Games.count)" + ((TotalCount ?? Games.count) > Games.count ? "+" : "") }

    var body: some View {
        if !Games.isEmpty {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(systemName: Symbol).font(.system(size: 19, weight: .medium)).foregroundStyle(Theme.Accent)
                        .frame(width: 42, height: 42).background(Theme.Accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    Button { if let Action { Action() } else { Store.CurrentRoute = .Search } } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Title).font(.system(size: 22, weight: .bold))
                            if !Subtitle.isEmpty { Text(Subtitle).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText) }
                        }
                    }.buttonStyle(MotionButtonStyle())
                    Text(Count).font(.system(size: 12, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Theme.Accent.opacity(0.1), in: Capsule())
                    Spacer()
                    Button { Move(-3) } label: { Image(systemName: "chevron.left").frame(width: 30, height: 36) }
                        .disabled(Index == 0).accessibilityLabel("Previous \(Title)")
                    Button { Move(3) } label: { Image(systemName: "chevron.right").frame(width: 30, height: 36) }
                        .disabled(Games.count <= 3 || Index >= max(1, Games.count - 4)).accessibilityLabel("Next \(Title)")
                }.buttonStyle(MotionButtonStyle())
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 18) {
                        ForEach(Games) { Game in Card(Game).id(Game.Id) }
                    }.scrollTargetLayout().padding(.vertical, 3)
                }
                .scrollPosition(id: $Position, anchor: .leading)
                .frame(height: CardWidth * 9 / 16 + 6)
            }.foregroundStyle(Theme.Foreground)
                .onChange(of: Games.map(\.Id)) { _, Ids in if let Position, !Ids.contains(Position) { self.Position = nil } }
        }
    }

    private func Card(_ Game: Game) -> some View {
        Button { Store.OpenGame(Game) } label: {
            ZStack(alignment: .bottomLeading) {
                GameArtwork(URL: Game.ArtworkURL, Name: Game.Name, CornerRadius: 11)
                LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom)
                if let Status = Store.MacCompatibility(for: Game) {
                    VStack {
                        HStack { Spacer(); MacCompatibilityBadge(Status: Status, Compact: true) }
                        Spacer()
                    }.padding(10)
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        if Game.Online { Image(systemName: "globe").padding(5).background(Theme.Accent, in: Circle()) }
                        if Game.Dlc { Image(systemName: "gift").padding(5).background(.orange, in: Circle()) }
                    }.font(.system(size: 11)).foregroundStyle(.white)
                    Text(Game.Name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                }.padding(13)
            }
            .frame(width: CardWidth, height: CardWidth * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.Border.opacity(0.2)))
        }
        .buttonStyle(MotionButtonStyle()).help(Game.Name).accessibilityLabel(Game.Name)
        .contextMenu {
            Button("View game") { Store.OpenGame(Game) }
            Button(Store.Wishlist.contains(Game.Id) ? "Remove from Play Later" : "Add to Play Later") { Store.ToggleWishlist(Game) }
        }
    }

    private func Move(_ Offset: Int) {
        guard !Games.isEmpty else { return }
        let Target = min(max(0, Index + Offset), Games.count - 1)
        withAnimation(MotionEnabled ? AppMotion.Standard : nil) { Position = Games[Target].Id }
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
                    Text(Game.Name).font(.system(size: Store.ShowingBigPicture ? 17 : 13, weight: .semibold)).foregroundStyle(.white).lineLimit(Store.ShowingBigPicture ? 2 : 1)
                    Text(Game.Categories.prefix(2).joined(separator: " · ")).font(.system(size: Store.ShowingBigPicture ? 13 : 10)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
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
                EmptyPanel(Symbol: "square.stack.3d.up", Title: "Your next game is waiting", Message: Store.CatalogWarning ?? "Load the Ascendara index or import your own source to start browsing.", ActionTitle: "Refresh game index", Action: { Store.RefreshCatalog() })
                HStack {
                    Button("Manage sources") { Store.CurrentRoute = .Sources }.buttonStyle(SecondaryButtonStyle())
                    Button("Use bundled Ascendara index") { Store.UseBundledCatalog() }.buttonStyle(SecondaryButtonStyle())
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
        GeometryReader { Geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if Store.ShowingBigPicture {
                        HStack {
                            PageHeading(Title: "Search", Subtitle: "Find something worth playing.")
                            IconButton(Symbol: "arrow.clockwise", Help: "Refresh game index", Action: { Store.RefreshCatalog() })
                        }
                        SearchField(Text: $Store.SearchQuery, Placeholder: "Search \(Store.Games.count.formatted()) games…")
                        VStack(spacing: 18) {
                            HStack(spacing: 20) {
                                GenrePicker.frame(maxWidth: .infinity)
                                SortPicker.frame(maxWidth: .infinity)
                            }
                            HStack(spacing: 22) {
                                Toggle("Online", isOn: $Store.OnlineOnly).toggleStyle(.checkbox)
                                Toggle("Includes DLC", isOn: $Store.DlcOnly).toggleStyle(.checkbox)
                                FilterButton
                                Spacer(minLength: 0)
                                ResultCount
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text("\(Store.Games.count.formatted()) Games Indexed")
                                .font(.system(size: 15, weight: .medium))
                            Image(systemName: "info.circle")
                                .help("Games in your currently selected catalogue")
                            Spacer()
                            IconButton(Symbol: "arrow.clockwise", Help: "Refresh game index", Action: { Store.RefreshCatalog() })
                        }.foregroundStyle(Theme.SecondaryText)
                        HStack(spacing: 16) {
                            SearchField(Text: $Store.SearchQuery, Placeholder: "Search games…")
                            FilterButton
                        }
                    }
                    if ShowFilters {
                        Panel(Padding: Store.ShowingBigPicture ? 22 : 18) {
                            if Store.ShowingBigPicture {
                                VStack(spacing: 20) {
                                    HStack(spacing: 24) {
                                        ProviderPicker.frame(maxWidth: .infinity)
                                        Toggle("Verified games", isOn: $Store.VerifiedOnly).toggleStyle(.checkbox)
                                    }
                                    HStack(spacing: 24) {
                                        SizeFilter
                                        Button("Reset filters") { ResetFilters() }.buttonStyle(SecondaryButtonStyle())
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 15) {
                                    HStack(spacing: 16) {
                                        GenrePicker.frame(maxWidth: .infinity)
                                        SortPicker.frame(maxWidth: .infinity)
                                        ProviderPicker.frame(maxWidth: .infinity)
                                    }
                                    HStack(spacing: 18) {
                                        Toggle("Online", isOn: $Store.OnlineOnly).toggleStyle(.checkbox)
                                        Toggle("Includes DLC", isOn: $Store.DlcOnly).toggleStyle(.checkbox)
                                        Toggle("Verified", isOn: $Store.VerifiedOnly).toggleStyle(.checkbox)
                                        SizeFilter.frame(maxWidth: 210)
                                        Spacer(minLength: 0)
                                        Button("Reset") { ResetFilters() }.buttonStyle(MotionButtonStyle()).foregroundStyle(Theme.Accent)
                                    }
                                }
                            }
                        }.MotionTransition(Distance: -6)
                    }
                    if !Store.ShowingBigPicture && !Store.Games.isEmpty { ResultCount }
                    if let Warning = Store.CatalogWarning { Notice(Message: Warning) }
                    if Store.Games.isEmpty { CatalogEmptyView() }
                    else if Results.isEmpty {
                        EmptyPanel(Symbol: "magnifyingglass", Title: "No games found", Message: "Try another title or clear your filters.", ActionTitle: "Clear filters") {
                            Store.SearchQuery = ""; ResetFilters()
                        }
                    } else if Store.ShowingBigPicture {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 225), spacing: 18)], spacing: 20) {
                            ForEach(Array(Results.prefix(VisibleCount))) { Game in GameCard(Game: Game) }
                        }
                    } else {
                        DesktopSearchResults(Games: Array(Results.prefix(VisibleCount)), Width: min(1440, max(0, Geometry.size.width - 60)))
                    }
                    if Results.count > VisibleCount {
                        Button("Load more games") { VisibleCount += 80 }.buttonStyle(SecondaryButtonStyle()).frame(maxWidth: .infinity)
                    }
                }
                .padding(30).padding(.bottom, Store.ShowingBigPicture ? 30 : 100)
                .frame(maxWidth: 1500).frame(maxWidth: .infinity)
            }
        }.background(Theme.Background).MotionAnimation(ShowFilters)
            .onChange(of: Store.SearchQuery) { _, _ in VisibleCount = 80 }
            .onChange(of: Store.SelectedGenre) { _, _ in VisibleCount = 80 }
    }
    private var GenrePicker: some View {
        Picker("Genre", selection: $Store.SelectedGenre) {
            ForEach(Store.Genres, id: \.self) { Genre in Text(Genre).tag(Genre) }
        }
    }
    private var SortPicker: some View {
        Picker("Sort", selection: $Store.SortOrder) {
            ForEach(["Relevance", "Name A–Z", "Recently updated", "Smallest size"], id: \.self) { Order in Text(Order).tag(Order) }
        }
    }
    private var FilterButton: some View {
        Button { ShowFilters.toggle() } label: {
            Label("Filters", systemImage: "slider.horizontal.3")
                .font(.system(size: Store.ShowingBigPicture ? 18 : 14, weight: .medium))
                .frame(minWidth: Store.ShowingBigPicture ? 0 : 95)
                .padding(.horizontal, Store.ShowingBigPicture ? 0 : 14)
                .padding(.vertical, Store.ShowingBigPicture ? 0 : 12)
                .background(Store.ShowingBigPicture ? Color.clear : Theme.Accent.opacity(ShowFilters ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(MotionButtonStyle()).foregroundStyle(Theme.Accent)
    }
    private var ResultCount: some View {
        Text("\(Results.count.formatted()) games").font(.system(size: Store.ShowingBigPicture ? 14 : 12)).foregroundStyle(Theme.SecondaryText)
    }
    private var ProviderPicker: some View {
        Picker("Provider", selection: $Store.SelectedProvider) {
            ForEach(Store.Providers, id: \.self) { Provider in Text(Provider).tag(Provider) }
        }
    }
    private var SizeFilter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Store.MaximumSizeGB == 0 ? "Maximum size: Any" : "Maximum size: \(Int(Store.MaximumSizeGB)) GB")
                .font(.system(size: Store.ShowingBigPicture ? 14 : 11))
            Slider(value: $Store.MaximumSizeGB, in: 0...250, step: 5)
        }
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

struct DesktopSearchResults: View {
    let Games: [Game]
    let Width: CGFloat
    private let Spacing: CGFloat = 18
    private var Columns: Int { Width >= 1160 ? 4 : Width >= 800 ? 3 : 2 }
    private var CardWidth: CGFloat { max(0, (Width - CGFloat(Columns - 1) * Spacing) / CGFloat(Columns)) }
    private var CardHeight: CGFloat { max(450, CardWidth * 1.7) }
    private var FirstRowCount: Int { min(Games.count, Columns - 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: Spacing) {
                if let Featured = Games.first {
                    SearchHighlightedCard(Game: Featured)
                        .frame(width: CardWidth * 2 + Spacing, height: CardHeight)
                }
                ForEach(Array(Games.dropFirst().prefix(max(0, FirstRowCount - 1)))) { Game in
                    SearchDetailCard(Game: Game, Width: CardWidth, Height: CardHeight)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing), count: Columns), spacing: 18) {
                ForEach(Array(Games.dropFirst(FirstRowCount))) { Game in
                    SearchDetailCard(Game: Game, Width: CardWidth, Height: CardHeight)
                }
            }
        }.frame(width: Width, alignment: .leading)
    }
}

struct SearchHighlightedCard: View {
    @EnvironmentObject private var Store: AppStore
    let Game: Game

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GameArtwork(URL: Game.ArtworkURL, Name: Game.Name, CornerRadius: 15)
            LinearGradient(colors: [.black.opacity(0.1), .clear, .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    Label("HIGHLIGHTED GAME", systemImage: "sparkles")
                        .font(.system(size: 12, weight: .bold)).tracking(0.5)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .background(Theme.Accent, in: Capsule())
                    if Store.VerifiedIds.contains(Game.Id) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 15)).padding(9)
                            .background(Theme.Accent, in: Circle())
                            .help("Verified game")
                    }
                    Spacer()
                    if let Status = Store.MacCompatibility(for: Game) {
                        MacCompatibilityBadge(Status: Status)
                    }
                }
                Spacer(minLength: 0)
                Text(Game.Name).font(.system(size: 28, weight: .bold)).lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 4)
                HStack(spacing: 7) {
                    if Game.Online { FeatureBadge("Online multiplayer", "gamecontroller") }
                    if Game.Dlc { FeatureBadge("Includes DLC", "gift") }
                    if let Size = Game.Size { FeatureBadge("Download: \(Size)", "internaldrive") }
                }
                if !Game.Categories.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(Game.Categories.prefix(4)), id: \.self) { Category in
                            Text(Category).font(.system(size: 11)).lineLimit(1)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(.white.opacity(0.17), in: Capsule())
                        }
                    }
                }
                Button { Store.OpenGame(Game) } label: {
                    Label("View Details", systemImage: "info.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minWidth: 135).padding(.vertical, 10)
                }.buttonStyle(PrimaryButtonStyle())
            }.foregroundStyle(.white).padding(24)
        }
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.Border.opacity(0.3)))
        .contextMenu {
            Button("View game") { Store.OpenGame(Game) }
            Button(Store.Wishlist.contains(Game.Id) ? "Remove from Play Later" : "Add to Play Later") { Store.ToggleWishlist(Game) }
        }
    }

    private func FeatureBadge(_ Title: String, _ Symbol: String) -> some View {
        Label(Title, systemImage: Symbol).font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.black.opacity(0.62), in: Capsule())
    }
}

struct SearchDetailCard: View {
    @EnvironmentObject private var Store: AppStore
    let Game: Game
    let Width: CGFloat
    let Height: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                GameArtwork(URL: Game.ArtworkURL, Name: Game.Name, CornerRadius: 0)
                LinearGradient(colors: [.black.opacity(0.4), .clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading) {
                    if Store.VerifiedIds.contains(Game.Id) {
                        Label("Verified", systemImage: "checkmark.shield")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.Accent, in: Capsule())
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        if Game.Dlc { ArtworkBadge("DLC included", "gift") }
                        Spacer()
                        if let Status = Store.MacCompatibility(for: Game) {
                            MacCompatibilityBadge(Status: Status, Compact: true)
                        }
                    }
                }.foregroundStyle(.white).padding(12)
            }.frame(width: Width, height: Height * 0.43).clipped()
            VStack(alignment: .leading, spacing: 12) {
                Text(Game.Name).font(.system(size: 18, weight: .semibold)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if Game.Online {
                    Label("Online", systemImage: "gamecontroller")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.Accent)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Theme.Accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
                HStack(spacing: 5) {
                    ForEach(Array(Game.Categories.prefix(3)), id: \.self) { Category in
                        Text(Category).lineLimit(1)
                            .font(.system(size: 11))
                            .padding(.horizontal, 7).padding(.vertical, 5)
                            .background(Theme.Accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                    }
                    if Game.Categories.count > 3 {
                        Text("+\(Game.Categories.count - 3)")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7).padding(.vertical, 5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.Border))
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    Metadata("DOWNLOAD", Game.Size, "internaldrive")
                    Metadata("VERSION", Game.Version, "tag")
                    Metadata("UPDATED", Game.LatestUpdate, "calendar")
                }.frame(height: 48)
                    .background(Theme.Accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 7))
                Divider().overlay(Theme.Border)
                HStack(spacing: 8) {
                    Button { Store.OpenGame(Game) } label: {
                        Label("View Details", systemImage: "info.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 34)
                    }.buttonStyle(PrimaryButtonStyle())
                    Button { Store.ToggleWishlist(Game) } label: {
                        Image(systemName: Store.Wishlist.contains(Game.Id) ? "heart.fill" : "heart")
                            .frame(width: 31, height: 34)
                    }.buttonStyle(MotionButtonStyle())
                        .accessibilityLabel(Store.Wishlist.contains(Game.Id) ? "Remove \(Game.Name) from Play Later" : "Add \(Game.Name) to Play Later")
                }
            }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Width, height: Height)
        .background(Theme.Card, in: RoundedRectangle(cornerRadius: 13))
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.Border.opacity(0.3)))
        .foregroundStyle(Theme.CardForeground)
        .contextMenu {
            Button("View game") { Store.OpenGame(Game) }
            Button(Store.Wishlist.contains(Game.Id) ? "Remove from Play Later" : "Add to Play Later") { Store.ToggleWishlist(Game) }
        }
    }

    private func ArtworkBadge(_ Title: String, _ Symbol: String) -> some View {
        Label(Title, systemImage: Symbol).font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.black.opacity(0.68), in: Capsule())
    }

    private func Metadata(_ Title: String, _ Value: String?, _ Symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(Title, systemImage: Symbol).font(.system(size: 9, weight: .medium)).lineLimit(1)
            Text(Value ?? "—").font(.system(size: 10, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(Theme.SecondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 7)
    }
}

struct MacCompatibilityBadge: View {
    let Status: MacCompatibility
    var Compact = false

    private var Tint: Color { Status.Kind == .Works ? .green : .cyan }

    var body: some View {
        Label(Status.Label, systemImage: Status.Kind == .Works ? "checkmark.circle.fill" : "questionmark.circle.fill")
            .font(.system(size: Compact ? 10 : 11, weight: .semibold))
            .foregroundStyle(Tint)
            .padding(.horizontal, Compact ? 8 : 10)
            .padding(.vertical, Compact ? 5 : 6)
            .background(.black.opacity(0.78), in: Capsule())
            .overlay(Capsule().stroke(Tint.opacity(0.6)))
            .help(Status.Evidence)
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
            }.padding(30).padding(.bottom, Store.ShowingBigPicture ? 30 : 100).frame(maxWidth: 1500).frame(maxWidth: .infinity)
        }
    }
}
