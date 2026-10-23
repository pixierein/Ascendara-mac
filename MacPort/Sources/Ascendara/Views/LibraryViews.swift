import AppKit
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var Store: AppStore
    @State private var Query = ""
    @State private var Scope = "All games"
    @State private var Sort = "Recently played"
    @State private var Editor: LibraryGame?
    @State private var ListLayout = false
    @State private var ShowingUpdates = false
    @State private var HoveredGame: UUID?
    private var Games: [LibraryGame] {
        Store.Library.filter { Game in
            (Query.isEmpty || Game.Name.localizedCaseInsensitiveContains(Query)) &&
            (Scope != "Favorites" || Game.Favorite) &&
            (Scope != "Recently played" || Game.LastPlayedAt != nil) &&
            (!Scope.hasPrefix("Collection: ") || Game.Collection == String(Scope.dropFirst(12)))
        }.sorted { Left, Right in
            if Sort == "Name" { return Left.Name.localizedStandardCompare(Right.Name) == .orderedAscending }
            if Sort == "Playtime" { return Left.PlayTimeSeconds > Right.PlayTimeSeconds }
            return (Left.LastPlayedAt ?? Left.AddedAt) > (Right.LastPlayedAt ?? Right.AddedAt)
        }
    }
    var body: some View {
        GeometryReader { Geometry in
            let Columns = Geometry.size.width >= 1280 ? 6 : Geometry.size.width >= 1024 ? 5 : 4
            HStack(spacing: 0) {
                Sidebar.frame(width: 218)
                Divider().overlay(Theme.Border)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            PageHeading(Title: Scope == "All games" ? "Your Library" : Scope.replacingOccurrences(of: "Collection: ", with: ""), Subtitle: "\(Games.count) games · Ready when you are")
                            IconButton(Symbol: "arrow.triangle.2.circlepath", Help: "Check library updates") { ShowingUpdates = true }
                            Button { Store.ImportGame() } label: { Label("Add game", systemImage: "plus") }.buttonStyle(PrimaryButtonStyle())
                        }
                        HStack(spacing: 14) {
                            SearchField(Text: $Query, Placeholder: "Search your library…")
                            Picker("Sort", selection: $Sort) {
                                ForEach(["Recently played", "Name", "Playtime"], id: \.self) { Value in Text(Value).tag(Value) }
                            }.frame(width: 200)
                            IconButton(Symbol: ListLayout ? "square.grid.2x2" : "list.bullet", Help: "Toggle library layout") { ListLayout.toggle() }
                        }
                        if Store.Library.isEmpty {
                            EmptyPanel(Symbol: "books.vertical", Title: "Make yourself at home", Message: "Add a macOS app, executable, or Windows game to start building your library.", ActionTitle: "Add your first game", Action: Store.ImportGame)
                        } else if Games.isEmpty {
                            EmptyPanel(Symbol: "magnifyingglass", Title: "No games here yet", Message: Scope == "Favorites" ? "Mark a game as a favorite to find it here." : "Try another search or choose All games.")
                        } else if ListLayout {
                            LazyVStack(spacing: 9) { ForEach(Games) { Game in LibraryRow(Game) } }
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: Columns), spacing: 16) {
                                ForEach(Games) { Game in LibraryCard(Game) }
                            }
                        }
                    }.padding(28).padding(.bottom, 100)
                }
            }
        }.MotionAnimation(ListLayout)
            .MotionAnimation(Scope)
            .MotionAnimation(Sort)
            .sheet(item: $Editor) { Game in LibraryEditorView(Game: Game).environmentObject(Store) }
            .sheet(isPresented: $ShowingUpdates) { LibraryUpdatesView().environmentObject(Store) }

    }
    private var Sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { Store.CurrentRoute = .Profile } label: {
                HStack(spacing: 11) {
                    Image(systemName: "person.fill").foregroundStyle(Theme.Accent).frame(width: 35, height: 35).background(Theme.Accent.opacity(0.13), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Store.Settings.DisplayName).font(.system(size: 13, weight: .semibold))
                        Text("\(Store.Library.count) games").font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
                    }
                    Spacer()
                }.padding(15).background(Theme.Muted.opacity(0.25))
            }.buttonStyle(MotionButtonStyle())
            ForEach([("All games", "square.stack.3d.up"), ("Favorites", "star"), ("Recently played", "clock")], id: \.0) { Title, Symbol in
                Button { Scope = Title } label: {
                    HStack(spacing: 10) {
                        Image(systemName: Symbol).frame(width: 18)
                        Text(Title).font(.system(size: 12, weight: Scope == Title ? .semibold : .regular))
                        Spacer()
                        if Title == "Favorites" { Text("\(Store.Library.filter(\.Favorite).count)").font(.system(size: 11)) }
                    }.padding(.horizontal, 13).padding(.vertical, 11)
                        .foregroundStyle(Scope == Title ? Theme.Accent : Theme.Foreground)
                        .background(Scope == Title ? Theme.Accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(MotionButtonStyle()).padding(.horizontal, 9)
            }
            Divider().padding(.horizontal, 18).padding(.vertical, 8)
            if !Store.Library.filter({ !$0.Collection.isEmpty }).isEmpty {
                Text("COLLECTIONS").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.SecondaryText).padding(.horizontal, 22).padding(.top, 4)
                ForEach(Array(Set(Store.Library.map(\.Collection).filter { !$0.isEmpty })).sorted(), id: \.self) { Collection in
                    Button { Scope = "Collection: " + Collection } label: {
                        Label(Collection, systemImage: "folder").font(.system(size: 12)).padding(.horizontal, 22).padding(.vertical, 8)
                            .foregroundStyle(Scope == "Collection: " + Collection ? Theme.Accent : Theme.Foreground)
                    }.buttonStyle(MotionButtonStyle())
                }
                Divider().padding(.horizontal, 18).padding(.vertical, 8)
            }
            SidebarLink("Play Later", "bookmark", .Wishlist)
            SidebarLink("Retro games", "gamecontroller", .Retro)
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text("MANAGE LIBRARY").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Theme.SecondaryText)
                Button { Store.ScanSteamLibrary() } label: { Label("Scan Steam library", systemImage: "arrow.triangle.2.circlepath") }.buttonStyle(MotionButtonStyle())
                Button { Store.ImportLibrary() } label: { Label("Import library…", systemImage: "square.and.arrow.down") }.buttonStyle(MotionButtonStyle())
                Button { Store.ExportLibrary() } label: { Label("Export library…", systemImage: "square.and.arrow.up") }.buttonStyle(MotionButtonStyle())
            }.font(.system(size: 11)).padding(20).padding(.bottom, 90)
        }.frame(maxHeight: .infinity).background(Theme.Card.opacity(0.25))
    }
    private func SidebarLink(_ Title: String, _ Symbol: String, _ Route: AppRoute) -> some View {
        Button { Store.CurrentRoute = Route } label: { Label(Title, systemImage: Symbol).font(.system(size: 12)).padding(.horizontal, 22).padding(.vertical, 9) }.buttonStyle(MotionButtonStyle())
    }
    private func LibraryCard(_ Game: LibraryGame) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                Button { Editor = Game } label: {
                    GameArtwork(URL: Game.ArtworkURL, Name: Game.Name, CornerRadius: 0).aspectRatio(2 / 3, contentMode: .fit)
                }.buttonStyle(MotionButtonStyle())
                if HoveredGame == Game.Id {
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom).allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(Game.Name).font(.system(size: 13, weight: .semibold)).lineLimit(2).foregroundStyle(.white)
                        HStack(spacing: 7) {
                            Button { Store.IsRunning(Game) ? Store.StopGame(Game) : Store.LaunchGame(Game) } label: {
                                Label(Store.IsRunning(Game) ? "Stop" : "Play", systemImage: Store.IsRunning(Game) ? "stop.fill" : "play.fill").frame(maxWidth: .infinity)
                            }.buttonStyle(PrimaryButtonStyle())
                            Button { Editor = Game } label: { Image(systemName: "gearshape").frame(width: 32, height: 35).background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(.white) }.buttonStyle(MotionButtonStyle()).help("Game options")
                        }
                    }.padding(12).MotionTransition()
                }
            }.overlay(alignment: .topLeading) {
                if Store.IsRunning(Game) {
                    Label("Running", systemImage: "play.fill").font(.system(size: 9, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 5).background(.green, in: Capsule()).foregroundStyle(.white).padding(9)
                } else if Game.LastPlayedAt == nil {
                    Text("NEW").font(.system(size: 9, weight: .bold)).padding(.horizontal, 7).padding(.vertical, 4).background(Theme.Accent, in: Capsule()).foregroundStyle(.white).padding(9)
                }
            }.overlay(alignment: .topTrailing) {
                if Game.Favorite { Image(systemName: "star.fill").foregroundStyle(.yellow).shadow(radius: 2).padding(10) }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(Game.Name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                HStack {
                    Text(Game.LastPlayedAt == nil ? "You haven't played this game yet" : FormatPlayTime(Game.PlayTimeSeconds))
                        .font(.system(size: 10)).foregroundStyle(Theme.SecondaryText).lineLimit(1)
                    Spacer(minLength: 2)
                    Menu { GameActions(Game) } label: { Image(systemName: "ellipsis").frame(width: 15, height: 12) }.menuStyle(.borderlessButton).frame(width: 18)
                }
            }.padding(11)
        }.background(Theme.Card, in: RoundedRectangle(cornerRadius: 12)).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(HoveredGame == Game.Id ? Theme.Accent.opacity(0.5) : Theme.Border.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(HoveredGame == Game.Id ? 0.12 : 0.05), radius: HoveredGame == Game.Id ? 10 : 3, y: 3)
            .onHover { HoveredGame = $0 ? Game.Id : nil }
            .MotionAnimation(HoveredGame == Game.Id, Animation: AppMotion.Quick)
            .MotionAnimation(Game.Favorite, Animation: AppMotion.Spring)
            .contextMenu { GameActions(Game) }
    }
    private func LibraryRow(_ Game: LibraryGame) -> some View {
        HStack(spacing: 15) {
            GameArtwork(URL: Game.ArtworkURL, Name: Game.Name).frame(width: 104, height: 61)
            VStack(alignment: .leading, spacing: 6) {
                Text(Game.Name).font(.system(size: 14, weight: .semibold))
                Text("\(FormatPlayTime(Game.PlayTimeSeconds)) played · \(Game.LaunchMode.rawValue)").font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
            }
            Spacer()
            if Game.Favorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
            Button { Store.IsRunning(Game) ? Store.StopGame(Game) : Store.LaunchGame(Game) } label: { Label(Store.IsRunning(Game) ? "Stop" : "Play", systemImage: Store.IsRunning(Game) ? "stop.fill" : "play.fill") }.buttonStyle(PrimaryButtonStyle())
            IconButton(Symbol: "slider.horizontal.3", Help: "Game options") { Editor = Game }
        }.padding(11).background(Theme.Card, in: RoundedRectangle(cornerRadius: 11)).contextMenu { GameActions(Game) }
    }
    @ViewBuilder private func GameActions(_ Game: LibraryGame) -> some View {
        Button(Store.IsRunning(Game) ? "Stop game" : "Play game") { Store.IsRunning(Game) ? Store.StopGame(Game) : Store.LaunchGame(Game) }
        Button("Game options…") { Editor = Game }
        Button(Game.Favorite ? "Remove from favorites" : "Add to favorites") { Store.ToggleLibraryFavorite(Game) }
        Button("Show in Finder") { Store.RevealGame(Game) }
        Divider()
        Button("Create backup…") { Store.CreateBackup(Game) }
        Button("Restore backup…") { Store.RestoreBackup(Game) }
        Divider()
        Button("Remove from library…", role: .destructive) { Store.RemoveGame(Game) }
    }
}

struct LibraryEditorView: View {
    @EnvironmentObject var Store: AppStore
    @Environment(\.dismiss) private var Dismiss
    @State var Game: LibraryGame
    @State private var Arguments = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Game options").font(.system(size: 24, weight: .bold))
                Spacer()
                IconButton(Symbol: "xmark", Help: "Close") { Dismiss() }
            }
            HStack(spacing: 18) {
                GameArtwork(URL: Game.ArtworkURL, Name: Game.Name).frame(width: 160, height: 100)
                VStack(alignment: .leading, spacing: 8) {
                    Text(Game.Name).font(.system(size: 19, weight: .bold))
                    Text("\(FormatPlayTime(Game.PlayTimeSeconds)) played").foregroundStyle(Theme.SecondaryText)
                    if let LastPlayed = Game.LastPlayedAt { Text("Last played \(LastPlayed.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11)).foregroundStyle(Theme.SecondaryText) }
                }
            }
            Form {
                TextField("Name", text: $Game.Name)
                HStack {
                    TextField("Executable", text: $Game.ExecutablePath)
                    Button("Choose…") { ChooseExecutable() }
                }
                Picker("Launch with", selection: $Game.LaunchMode) {
                    ForEach(LaunchMode.allCases) { Mode in Text(Mode.rawValue).tag(Mode) }
                }
                LabeledContent("Launch arguments") {
                    VStack(alignment: .leading, spacing: 5) {
                        TextEditor(text: $Arguments).font(.system(size: 11, design: .monospaced)).frame(height: 45)
                        Text("One argument per line; spaces are preserved.").font(.system(size: 10)).foregroundStyle(Theme.SecondaryText)
                    }.frame(width: 360)
                }
                TextField("Collection", text: $Game.Collection)
                TextField("Save directory", text: Binding(get: { Game.SaveDirectory ?? "" }, set: { Game.SaveDirectory = $0.isEmpty ? nil : $0 }))
                if Game.LaunchMode == .Wine {
                    TextField("Wine prefix", text: Binding(get: { Game.WinePrefixPath ?? "" }, set: { Game.WinePrefixPath = $0.isEmpty ? nil : $0 }))
                }
                if Game.LaunchMode == .Highball {
                    TextField("Highball bottle", text: $Game.HighballBottle)
                    Picker("Renderer", selection: $Game.Renderer) {
                        ForEach(["auto", "dxmt", "d3dmetal", "dxvk", "wined3d"], id: \.self) { Renderer in Text(Renderer).tag(Renderer) }
                    }
                }
                Toggle("Favorite", isOn: $Game.Favorite)
            }.formStyle(.grouped)
            VStack(alignment: .leading, spacing: 7) {
                Text("Private notes").font(.system(size: 12, weight: .medium))
                TextEditor(text: $Game.Notes).font(.system(size: 12)).frame(height: 72).padding(5).background(Theme.Card).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button("Show in Finder") { Store.RevealGame(Game) }.buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Cancel") { Dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("Save changes") {
                    Game.LaunchArguments = Arguments.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    Store.UpdateGame(Game)
                    Dismiss()
                }.buttonStyle(PrimaryButtonStyle()).disabled(Game.Name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 660).background(Theme.Background).foregroundStyle(Theme.Foreground)
            .onAppear { Arguments = Game.LaunchArguments.joined(separator: "\n") }
    }
    private func ChooseExecutable() {
        let Panel = NSOpenPanel()
        Panel.title = "Choose the game application or executable"
        Panel.canChooseFiles = true
        Panel.canChooseDirectories = false
        Panel.treatsFilePackagesAsDirectories = false
        if Panel.runModal() == .OK, let URL = Panel.url { Game.ExecutablePath = URL.path; Game.DirectoryPath = URL.deletingLastPathComponent().path }
    }
}
