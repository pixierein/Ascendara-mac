import AppKit
import Combine
import SwiftUI

struct LibraryDashboardView: View {
    @EnvironmentObject private var Store: AppStore
    @StateObject private var Retro = RetroService.Shared
    @State private var Section: String
    @State private var Query = ""
    @State private var Sort = "Recently played"
    @State private var ListLayout = false
    @State private var InstalledOnly = false
    @State private var ManagedOnly = false
    @State private var RetroSetupOnly = false
    @State private var RetroFavoritesOnly = false
    @State private var SelectionMode = false
    @State private var SelectedIds: Set<UUID> = []
    @State private var Editor: LibraryGame?
    @State private var ShowingUpdates = false
    @State private var ShowingLibraryValue = false
    @State private var Disk = LibraryDiskSpace()
    @State private var HoveredGame: UUID?

    init(InitialSection: String = "All Games") {
        _Section = State(initialValue: InitialSection)
    }

    private var LocalGames: [LibraryGame] {
        Store.Library.filter { Game in
            (Query.isEmpty || Game.Name.localizedCaseInsensitiveContains(Query)) &&
            (Section != "Favorites" || Game.Favorite) &&
            (Section != "History" || Game.LastPlayedAt != nil) &&
            (!Section.hasPrefix("Collection: ") || Game.Collection == String(Section.dropFirst(12))) &&
            (!InstalledOnly || Game.IsInstalled) && (!ManagedOnly || Game.IsManaged)
        }.sorted { Left, Right in
            if Sort == "Name" { return Left.Name.localizedStandardCompare(Right.Name) == .orderedAscending }
            if Sort == "Playtime" { return Left.PlayTimeSeconds > Right.PlayTimeSeconds }
            return (Left.LastPlayedAt ?? Left.AddedAt) > (Right.LastPlayedAt ?? Right.AddedAt)
        }
    }

    private var PlayLaterGames: [Game] {
        Store.WishlistGames.filter { Query.isEmpty || $0.Name.localizedCaseInsensitiveContains(Query) }
    }

    private var Title: String {
        Section.hasPrefix("Collection: ") ? String(Section.dropFirst(12)) : Section
    }

    private var Subtitle: String {
        switch Section {
        case "All Games": "All your installed games in one place."
        case "Favorites": "The games you always come back to."
        case "Play Later": "Games saved for your next adventure."
        case "History": "Your recently played games."
        case "Retro": "Your classic games, consoles, and emulators."
        default: "Games in this collection."
        }
    }

    private var Symbol: String {
        switch Section {
        case "All Games": "books.vertical"
        case "Favorites": "heart"
        case "Play Later": "clock"
        case "History": "clock.arrow.circlepath"
        case "Retro": "gamecontroller"
        default: "folder"
        }
    }

    var body: some View {
        GeometryReader { Geometry in
            HStack(spacing: 0) {
                Sidebar.frame(width: Geometry.size.width < 1050 ? 220 : 252, height: Geometry.size.height)
                Rectangle().fill(Theme.Border.opacity(0.45)).frame(width: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        TopBar
                        Heading
                        if Section == "Retro" {
                            RetroLibraryDashboard(Service: Retro, GlobalQuery: Query,
                                                  SetupOnly: $RetroSetupOnly, FavoritesOnly: $RetroFavoritesOnly)
                        } else if Section == "Play Later" {
                            PlayLaterContent
                        } else {
                            LocalContent(Width: Geometry.size.width - (Geometry.size.width < 1050 ? 220 : 252))
                        }
                    }
                    .padding(.horizontal, Geometry.size.width < 1000 ? 22 : 32)
                    .padding(.top, 18)
                    .padding(.bottom, 130)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(Theme.Background)
        .sheet(item: $Editor) { Game in LibraryEditorView(Game: Game).environmentObject(Store) }
        .sheet(isPresented: $ShowingUpdates) { LibraryUpdatesView().environmentObject(Store) }
        .sheet(isPresented: $ShowingLibraryValue) { LibraryValueView(Games: Store.Library) }
        .task(id: DiskRequestKey) {
            let Request = DiskRequestKey
            Disk = LibraryDiskSpace.Drive(at: Store.Settings.DownloadDirectory)
            let Paths = Store.Library.map {
                LibraryDiskSpace.GamePath(Executable: $0.ExecutablePath, Directory: $0.DirectoryPath)
            }
            let Bytes = await LibraryDiskSpace.GameBytes(Paths: Paths)
            if Request == DiskRequestKey { Disk.Games = Bytes }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            let Drive = LibraryDiskSpace.Drive(at: Store.Settings.DownloadDirectory)
            Disk.Available = Drive.Available
            Disk.Total = Drive.Total
        }
        .MotionAnimation(Section)
        .MotionAnimation(ListLayout)
    }

    private var Sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { Store.Route = .Profile } label: {
                HStack(spacing: 11) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 34)).foregroundStyle(Theme.Accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Store.Settings.DisplayName.isEmpty ? "Guest" : Store.Settings.DisplayName)
                            .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text("\(Store.Library.count) Total Games")
                            .font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "sparkles").foregroundStyle(Theme.Accent)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Card.opacity(0.6))
                .contentShape(Rectangle())
            }.buttonStyle(MotionButtonStyle())

            Menu {
                Button("Add a game…") { Store.ImportGame() }
                Button("Scan Steam library") { Store.ScanSteamLibrary() }
                Divider()
                Menu("Add Retro ROM folder") {
                    ForEach(Retro.Platforms) { Platform in
                        Button(Platform.Name) { Scan(Platform) }
                    }
                }
            } label: {
                Label("Add to Library", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .foregroundStyle(.white)
                    .background(Theme.Accent, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 18)

            Text("LIBRARY").font(.system(size: 10, weight: .bold)).tracking(1.8)
                .foregroundStyle(Theme.SecondaryText).padding(.leading, 16).padding(.bottom, 7)
            ForEach([
                ("All Games", "books.vertical"), ("Favorites", "heart"),
                ("Play Later", "clock"),
                ("History", "clock.arrow.circlepath"), ("Retro", "gamecontroller")
            ], id: \.0) { Name, Icon in
                SidebarButton(Name, Icon)
            }

            let Collections = Array(Set(Store.Library.map(\.Collection).filter { !$0.isEmpty })).sorted()
            if !Collections.isEmpty {
                Text("COLLECTIONS").font(.system(size: 10, weight: .bold)).tracking(1.8)
                    .foregroundStyle(Theme.SecondaryText).padding(.leading, 16).padding(.top, 19).padding(.bottom, 7)
                ForEach(Collections, id: \.self) { Name in SidebarButton("Collection: " + Name, "folder") }
            }
            Spacer(minLength: 16)
            Menu {
                Menu("Library Backups") {
                    Button("Export library backup…") { Store.ExportLibrary() }
                    Button("Restore library backup…") { Store.ImportLibrary() }
                }
                Button("Calculate Library Value") { ShowingLibraryValue = true }
                Divider()
                Button("Check game updates") { ShowingUpdates = true }
            } label: {
                HStack {
                    Label("Library tools", systemImage: "wrench")
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 10))
                }
                .font(.system(size: 12, weight: .medium)).padding(12)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 10).padding(.bottom, 14)
            DiskSpaceCard.padding(.horizontal, 10).padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Card.opacity(0.24))
    }

    private var DiskRequestKey: String {
        Store.Settings.DownloadDirectory + "|" + Store.Library.map {
            $0.ExecutablePath + ":" + $0.DirectoryPath
        }.joined(separator: "|")
    }

    private func SidebarButton(_ Name: String, _ Icon: String) -> some View {
        let Active = Section == Name
        return Button {
            Query = ""
            Section = Name
            if Store.Route == .Retro && Name != "Retro" { Store.Route = .Library }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: Icon).frame(width: 18)
                Text(Name.replacingOccurrences(of: "Collection: ", with: "")).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: Active ? .semibold : .medium))
            .foregroundStyle(Active ? Theme.Accent : Theme.SecondaryText)
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(Active ? Theme.Accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(MotionButtonStyle())
        .padding(.horizontal, 8)
    }

    private var DiskSpaceCard: some View {
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Available Space", systemImage: "externaldrive").lineLimit(1)
                Spacer(minLength: 3)
                Text(Disk.Total > 0 ? ByteCountFormatter.string(fromByteCount: Disk.Available, countStyle: .file) : "—")
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .semibold))
            if Disk.Total > 0 {
                ProgressView(value: min(Double(Disk.Games), Double(Disk.Total)), total: Double(Disk.Total))
                    .tint(Theme.Accent)
                HStack {
                    Text("\(ByteCountFormatter.string(fromByteCount: Disk.Games, countStyle: .file)) games")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Disk.Total, countStyle: .file))
                }.font(.system(size: 10)).foregroundStyle(Theme.SecondaryText).monospacedDigit()
            }
        }
        .padding(12).background(Theme.Card, in: RoundedRectangle(cornerRadius: 9))
    }

    private var TopBar: some View {
        HStack(spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.SecondaryText)
                TextField("Search your games…", text: $Query)
                    .textFieldStyle(.plain).font(.system(size: 13))
            }
            .padding(.horizontal, 14).frame(height: 40)
            .background(Theme.Card.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Border.opacity(0.7)))

            if Section != "Retro" && Section != "Play Later" {
                HStack(spacing: 1) {
                    LayoutButton("square.grid.2x2", List: false)
                    LayoutButton("list.bullet", List: true)
                }
                .padding(3).background(Theme.Card, in: RoundedRectangle(cornerRadius: 8))
            }
            Menu {
                if Section == "Retro" {
                    Toggle("Set up consoles only", isOn: $RetroSetupOnly)
                    Toggle("Favorites only", isOn: $RetroFavoritesOnly)
                } else if Section == "Play Later" {
                    Text("Search by game name above")
                } else {
                    Picker("Sort", selection: $Sort) {
                        Text("Recently played").tag("Recently played")
                        Text("Name").tag("Name")
                        Text("Playtime").tag("Playtime")
                    }
                    Divider()
                    Toggle("Installed only", isOn: $InstalledOnly)
                    Toggle("Managed by Ascendara", isOn: $ManagedOnly)
                }
            } label: {
                Label("Filters", systemImage: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 13).frame(height: 40)
                    .background(Theme.Card, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }.menuStyle(.borderlessButton)
            if Section != "Retro" && Section != "Play Later" {
                Button { SelectionMode.toggle(); SelectedIds.removeAll() } label: {
                    Image(systemName: SelectionMode ? "checkmark.circle.fill" : "checkmark.square")
                        .frame(width: 40, height: 40).background(Theme.Card, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(MotionButtonStyle()).help("Select games")
            }
        }
    }

    private func LayoutButton(_ Icon: String, List: Bool) -> some View {
        Button { ListLayout = List } label: {
            Image(systemName: Icon).frame(width: 32, height: 32)
                .foregroundStyle(ListLayout == List ? Theme.Accent : Theme.SecondaryText)
                .background(ListLayout == List ? Theme.Accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(MotionButtonStyle())
    }

    private var Heading: some View {
        HStack(spacing: 15) {
            Image(systemName: Symbol).font(.system(size: 23)).foregroundStyle(Theme.Accent)
                .frame(width: 48, height: 48).background(Theme.Accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(Title).font(.system(size: 27, weight: .bold))
                Text(Subtitle).font(.system(size: 13)).foregroundStyle(Theme.SecondaryText)
            }
            Spacer()
        }
    }

    @ViewBuilder private func LocalContent(Width: CGFloat) -> some View {
        if SelectionMode && !SelectedIds.isEmpty {
            HStack {
                Text("\(SelectedIds.count) selected").font(.system(size: 12, weight: .semibold))
                Button("Add to favorites") {
                    for Game in Store.Library where SelectedIds.contains(Game.Id) && !Game.Favorite { Store.ToggleLibraryFavorite(Game) }
                    SelectedIds.removeAll(); SelectionMode = false
                }
                Button("Clear selection") { SelectedIds.removeAll() }
            }.buttonStyle(SecondaryButtonStyle())
        }
        if LocalGames.isEmpty {
            LibraryBlank(Symbol: Section == "Favorites" ? "heart" : Section == "History" ? "clock" : "books.vertical",
                         Title: "No games found",
                         Detail: Query.isEmpty ? (Store.Library.isEmpty ? "Add a game to start building your library." : "There are no games in this section yet.") : "Try another search or adjust the filters.")
        } else if ListLayout {
            LazyVStack(spacing: 9) { ForEach(LocalGames) { Game in LocalRow(Game) } }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Width < 820 ? 175 : 205, maximum: 270), spacing: 16)], spacing: 16) {
                ForEach(LocalGames) { Game in LocalCard(Game) }
            }
        }
    }

    private func LocalCard(_ Game: LibraryGame) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                Button { SelectionMode ? ToggleSelection(Game) : (Editor = Game) } label: {
                GameArtwork(URL: Game.ArtworkURL, Name: Game.Name, CornerRadius: 0)
                    .aspectRatio(16 / 10, contentMode: .fit)
                }.buttonStyle(MotionButtonStyle())
                if !SelectionMode && (HoveredGame == Game.Id || Store.ShowingBigPicture) {
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70).allowsHitTesting(false)
                    HStack(spacing: 7) {
                        Button { Store.IsRunning(Game) ? Store.StopGame(Game) : Store.LaunchGame(Game) } label: {
                            Label(Store.BusyGameIds.contains(Game.Id) ? "Launching…" : Store.IsRunning(Game) ? "Stop" : "Play",
                                  systemImage: Store.BusyGameIds.contains(Game.Id) ? "hourglass" : Store.IsRunning(Game) ? "stop.fill" : "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .foregroundStyle(.white)
                                .background(Theme.Accent, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(MotionButtonStyle())
                            .disabled(Store.BusyGameIds.contains(Game.Id) || !Game.IsInstalled && !Store.IsRunning(Game))
                            .accessibilityLabel("\(Store.IsRunning(Game) ? "Stop" : "Play") \(Game.Name)")
                        Menu { LocalActions(Game) } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(RoundedRectangle(cornerRadius: 7))
                        }.menuStyle(.borderlessButton)
                            .frame(width: 34)
                            .help("More options for \(Game.Name)")
                            .accessibilityLabel("More options for \(Game.Name)")
                    }
                    .padding(9)
                }
            }
            .overlay(alignment: .topTrailing) {
                if SelectionMode {
                    Image(systemName: SelectedIds.contains(Game.Id) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22)).foregroundStyle(Theme.Accent).padding(10)
                } else if Game.Favorite {
                    Image(systemName: "heart.fill").foregroundStyle(.pink).padding(10)
                }
            }
            Button { SelectionMode ? ToggleSelection(Game) : (Editor = Game) } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text(Game.Name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(Game.LastPlayedAt == nil ? "Not played yet" : FormatPlayTime(Game.PlayTimeSeconds) + " played")
                        .font(.system(size: 11)).foregroundStyle(Theme.SecondaryText).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }.buttonStyle(MotionButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Card, in: RoundedRectangle(cornerRadius: 11))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(SelectedIds.contains(Game.Id) ? Theme.Accent : Theme.Border.opacity(0.45)))
        .onHover { Inside in
            if Inside { HoveredGame = Game.Id }
            else if HoveredGame == Game.Id { HoveredGame = nil }
        }
        .contextMenu { LocalActions(Game) }
    }

    private func LocalRow(_ Game: LibraryGame) -> some View {
        HStack(spacing: 13) {
            if SelectionMode {
                Button { ToggleSelection(Game) } label: {
                    Image(systemName: SelectedIds.contains(Game.Id) ? "checkmark.circle.fill" : "circle")
                }.buttonStyle(MotionButtonStyle())
            }
            GameArtwork(URL: Game.ArtworkURL, Name: Game.Name).frame(width: 100, height: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text(Game.Name).font(.system(size: 13, weight: .semibold))
                Text(Game.LastPlayedAt == nil ? "Not played yet" : FormatPlayTime(Game.PlayTimeSeconds) + " played")
                    .font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
            }
            Spacer()
            if Game.Favorite { Image(systemName: "heart.fill").foregroundStyle(.pink) }
            Button(Store.BusyGameIds.contains(Game.Id) ? "Launching…" : Store.IsRunning(Game) ? "Stop" : "Play") {
                Store.IsRunning(Game) ? Store.StopGame(Game) : Store.LaunchGame(Game)
            }.buttonStyle(PrimaryButtonStyle())
                .disabled(Store.BusyGameIds.contains(Game.Id) || !Game.IsInstalled && !Store.IsRunning(Game))
            Menu { LocalActions(Game) } label: {
                Image(systemName: "line.3.horizontal")
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).help("More options for \(Game.Name)")
        }
        .padding(10).background(Theme.Card, in: RoundedRectangle(cornerRadius: 10))
        .contextMenu { LocalActions(Game) }
    }

    @ViewBuilder private func LocalActions(_ Game: LibraryGame) -> some View {
        Button("Game options…") { Editor = Game }
        Button(Game.Favorite ? "Remove from favorites" : "Add to favorites") { Store.ToggleLibraryFavorite(Game) }
        Button("Show in Finder") { Store.RevealGame(Game) }
        Divider()
        Button("Create save backup…") { Store.CreateBackup(Game) }
        Button("Restore save backup…") { Store.RestoreBackup(Game) }
        Button("Remove from library…", role: .destructive) { Store.RemoveGame(Game) }
    }

    private var PlayLaterContent: some View {
        Group {
            if PlayLaterGames.isEmpty {
                LibraryBlank(Symbol: "clock", Title: "No games saved yet", Detail: "Save a game from Search to find it here later.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(PlayLaterGames) { Game in GameCard(Game: Game) }
                }
            }
        }
    }

    private func ToggleSelection(_ Game: LibraryGame) {
        if SelectedIds.contains(Game.Id) { SelectedIds.remove(Game.Id) }
        else { SelectedIds.insert(Game.Id) }
    }

    private func Scan(_ Platform: RetroPlatform) {
        guard let Folder = Store.ChooseFolder(Title: "Choose your \(Platform.Name) ROM folder") else { return }
        Task {
            do {
                let Count = try await Retro.Scan(Platform: Platform, Folder: Folder)
                Section = "Retro"
                Store.Notice = "Found \(Count) \(Platform.Name) games."
            } catch { Store.Report(error) }
        }
    }
}

private struct LibraryBlank: View {
    let Symbol: String
    let Title: String
    let Detail: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: Symbol).font(.system(size: 41)).foregroundStyle(Theme.SecondaryText.opacity(0.6))
            Text(Title).font(.system(size: 15, weight: .semibold))
            Text(Detail).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(24)
    }
}

private struct RetroLibraryDashboard: View {
    @EnvironmentObject private var Store: AppStore
    @ObservedObject var Service: RetroService
    let GlobalQuery: String
    @Binding var SetupOnly: Bool
    @Binding var FavoritesOnly: Bool
    @State private var SelectedPlatform = "all"
    @State private var ConsoleQuery = ""
    @State private var GameQuery = ""
    @State private var GameSort = "Title: A–Z"
    @State private var Tab = "My library"
    @State private var Editing: RetroPlatform?

    private var Platforms: [RetroPlatform] {
        Service.Platforms.filter { Platform in
            (ConsoleQuery.isEmpty || Platform.Name.localizedCaseInsensitiveContains(ConsoleQuery)) &&
            (!SetupOnly || !Service.Profile(for: Platform).ExecutablePath.isEmpty)
        }
    }

    private var Games: [RetroGame] {
        Service.Games.filter { Game in
            (SelectedPlatform == "all" || Game.PlatformId == SelectedPlatform) &&
            (GlobalQuery.isEmpty || Game.Name.localizedCaseInsensitiveContains(GlobalQuery)) &&
            (GameQuery.isEmpty || Game.Name.localizedCaseInsensitiveContains(GameQuery)) &&
            (!FavoritesOnly || Game.Favorite)
        }.sorted { Left, Right in
            GameSort == "Recently played"
                ? (Left.LastPlayedAt ?? .distantPast) > (Right.LastPlayedAt ?? .distantPast)
                : Left.Name.localizedStandardCompare(Right.Name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                Text("\(Service.Games.count) games in your library")
                Text("\(Service.Profiles.values.filter { !$0.ExecutablePath.isEmpty }.count) systems set up")
                Spacer()
                Button("All emulators") { Tab = "Emulators" }.buttonStyle(MotionButtonStyle())
            }.font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
            Rectangle().fill(Theme.Border.opacity(0.5)).frame(height: 1)
            HStack(alignment: .top, spacing: 18) {
                ConsolePanel.frame(width: 235)
                VStack(alignment: .leading, spacing: 18) {
                    Text(Tab == "Emulators" ? "Emulators" : "Your collection")
                        .font(.system(size: 19, weight: .semibold))
                    Text(Tab == "Emulators" ? "Choose an installed emulator for each console." : "Choose a console to manage its emulator, games and saves.")
                        .font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
                    HStack(spacing: 8) {
                        RetroTab("My library", "books.vertical")
                        RetroTab("Catalogue", "book")
                        RetroTab("Emulators", "desktopcomputer")
                    }
                    if Tab == "Emulators" {
                        EmulatorContent
                    } else if Tab == "Catalogue" {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your local console catalogue")
                                .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                            ForEach(Service.Platforms.filter { SelectedPlatform == "all" || $0.Id == SelectedPlatform }) { Platform in
                                Button { SelectedPlatform = Platform.Id; Tab = "My library" } label: {
                                    HStack {
                                        Image(systemName: "gamecontroller").foregroundStyle(Theme.Accent).frame(width: 24)
                                        Text(Platform.Name)
                                        Spacer()
                                        Text("\(Service.Games.filter { $0.PlatformId == Platform.Id }.count) games")
                                            .foregroundStyle(Theme.SecondaryText)
                                        Image(systemName: "chevron.right")
                                    }.font(.system(size: 12)).padding(12)
                                        .background(Theme.Card, in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(MotionButtonStyle())
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                TextField("Search your Retro library…", text: $GameQuery).textFieldStyle(.plain)
                            }
                            .padding(10).background(Theme.Card, in: RoundedRectangle(cornerRadius: 8))
                            Menu {
                                Button("Title: A–Z") { GameSort = "Title: A–Z" }
                                Button("Recently played") { GameSort = "Recently played" }
                            } label: { Label(GameSort, systemImage: "line.3.horizontal.decrease") }
                                .menuStyle(.borderlessButton)
                            Toggle("Favorites", isOn: $FavoritesOnly).toggleStyle(.checkbox)
                        }.font(.system(size: 11))
                        if Games.isEmpty {
                            VStack(spacing: 13) {
                                Image(systemName: "gamecontroller").font(.system(size: 38)).foregroundStyle(Theme.Accent)
                                Text("Bring your Retro library together").font(.system(size: 16, weight: .semibold))
                                Text("Choose a console, connect its emulator, and add a ROM folder. Your games will appear here.")
                                    .font(.system(size: 11)).foregroundStyle(Theme.SecondaryText).multilineTextAlignment(.center)
                                Button("Set up a console") {
                                    Editing = Service.Platforms.first { $0.Id == SelectedPlatform } ?? Service.Platforms.first
                                }.buttonStyle(PrimaryButtonStyle())
                            }
                            .frame(maxWidth: .infinity, minHeight: 330)
                            .padding(24)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.Border.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                                ForEach(Games) { Game in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Image(systemName: "gamecontroller.fill").font(.system(size: 32)).foregroundStyle(Theme.Accent)
                                            .frame(maxWidth: .infinity, minHeight: 95)
                                        Text(Game.Name).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                                        HStack {
                                            Button("Play") { Task { do { try await Service.Launch(Game) } catch { Store.Report(error) } } }
                                                .buttonStyle(PrimaryButtonStyle()).disabled(!Game.IsInstalled || !Game.MissingDependencies.isEmpty)
                                            Spacer()
                                            Button {
                                                do { try Service.ToggleFavorite(Game) } catch { Store.Report(error) }
                                            } label: {
                                                Image(systemName: Game.Favorite ? "heart.fill" : "heart")
                                                    .foregroundStyle(Game.Favorite ? .pink : Theme.SecondaryText)
                                            }.buttonStyle(MotionButtonStyle())
                                        }
                                    }.padding(12).background(Theme.Card, in: RoundedRectangle(cornerRadius: 10))
                                        .contextMenu {
                                            Button("Console setup") { Editing = Service.Platforms.first { $0.Id == Game.PlatformId } }
                                            Button("Show in Finder") {
                                                if let Path = Game.FilePaths.first {
                                                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Path)])
                                                }
                                            }
                                            Button("Remove from library…", role: .destructive) {
                                                do { try Service.Remove(Game) } catch { Store.Report(error) }
                                            }
                                        }
                                }
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(item: $Editing) { Platform in RetroSetupView(Service: Service, Platform: Platform).environmentObject(Store) }
    }

    private var ConsolePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Consoles").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(Service.Platforms.count)").foregroundStyle(Theme.SecondaryText)
            }
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Find a console", text: $ConsoleQuery).textFieldStyle(.plain)
            }.padding(9).background(Theme.Background, in: RoundedRectangle(cornerRadius: 7))
            HStack(spacing: 4) {
                Button("All") { SetupOnly = false }
                Button("Set up") { SetupOnly = true }
            }.buttonStyle(SecondaryButtonStyle())
            Button { SelectedPlatform = "all" } label: {
                Label("All consoles", systemImage: "books.vertical").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(MotionButtonStyle()).padding(9)
                .background(SelectedPlatform == "all" ? Theme.Accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Platforms) { Platform in
                        Button { SelectedPlatform = Platform.Id } label: {
                            HStack {
                                Image(systemName: "gamecontroller").frame(width: 17)
                                Text(Platform.Name).lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(Service.Games.filter { $0.PlatformId == Platform.Id }.count)")
                            }.padding(.horizontal, 9).padding(.vertical, 8)
                                .background(SelectedPlatform == Platform.Id ? Theme.Accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(MotionButtonStyle())
                    }
                }
            }.frame(height: 440)
        }
        .font(.system(size: 11)).padding(14)
        .background(Theme.Card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func RetroTab(_ Name: String, _ Icon: String) -> some View {
        Button { Tab = Name } label: { Label(Name, systemImage: Icon) }
            .buttonStyle(SecondaryButtonStyle())
            .foregroundStyle(Tab == Name ? Theme.Accent : Theme.Foreground)
    }

    private var EmulatorContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Service.Platforms.filter { SelectedPlatform == "all" || $0.Id == SelectedPlatform }) { Platform in
                HStack {
                    Image(systemName: "gamecontroller").foregroundStyle(Theme.Accent).frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Platform.Name).font(.system(size: 12, weight: .semibold))
                        Text(Service.Profile(for: Platform).ExecutablePath.isEmpty ? "No emulator selected" : URL(fileURLWithPath: Service.Profile(for: Platform).ExecutablePath).lastPathComponent)
                            .font(.system(size: 10)).foregroundStyle(Theme.SecondaryText)
                    }
                    Spacer()
                    Button("Set up") { Editing = Platform }.buttonStyle(SecondaryButtonStyle())
                }.padding(10).background(Theme.Card, in: RoundedRectangle(cornerRadius: 9))
            }
        }
    }
}
