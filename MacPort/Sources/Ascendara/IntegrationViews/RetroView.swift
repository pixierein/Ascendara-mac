import AppKit
import SwiftUI

struct RetroView: View {
    @EnvironmentObject private var Store: AppStore
    @StateObject private var Service = RetroService.Shared
    @State private var SelectedPlatform = "all"
    @State private var Query = ""
    @State private var FavoritesOnly = false
    @State private var Tab = "Library"
    @State private var Editing: RetroPlatform?

    private var Games: [RetroGame] {
        Service.Games.filter { (SelectedPlatform == "all" || $0.PlatformId == SelectedPlatform) &&
            (Query.isEmpty || $0.Name.localizedCaseInsensitiveContains(Query)) && (!FavoritesOnly || $0.Favorite) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    PageHeading(Title: "Retro", Subtitle: "Your classic games, consoles, and emulators in one place.")
                    if Service.Scanning { ProgressView().controlSize(.small) }
                    Menu {
                        ForEach(Service.Platforms) { Platform in Button(Platform.Name) { Import(Platform) } }
                    } label: { Label("Add ROM folder", systemImage: "folder.badge.plus") }
                    .menuStyle(.borderlessButton).fixedSize().padding(10).background(Theme.Card, in: RoundedRectangle(cornerRadius: 8))
                    .disabled(Service.Scanning)
                }
                HStack(spacing: 12) {
                    ForEach(["Library", "Consoles", "Emulators"], id: \.self) { Name in
                        Button(Name) { Tab = Name }.buttonStyle(MotionButtonStyle()).fontWeight(Tab == Name ? .semibold : .regular)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Tab == Name ? Theme.Accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }
                    Spacer()
                    Text("\(Service.Games.count) games · \(Service.Platforms.count) consoles").font(.caption).foregroundStyle(Theme.SecondaryText)
                }
                if let Error = Service.ErrorMessage { Notice(Message: Error, Symbol: "exclamationmark.triangle") }
                if Tab == "Library" { Library }
                else if Tab == "Consoles" { Consoles }
                else { Emulators }
            }.padding(30)
        }.background(Theme.Background)
            .MotionAnimation(Tab)
            .MotionAnimation(SelectedPlatform)
            .MotionAnimation(FavoritesOnly)
            .sheet(item: $Editing) { Platform in RetroSetupView(Service: Service, Platform: Platform).environmentObject(Store) }
    }

    private var Library: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                TextField("Search your retro games", text: $Query).textFieldStyle(.roundedBorder).frame(maxWidth: 340)
                Picker("Console", selection: $SelectedPlatform) {
                    Text("All consoles").tag("all")
                    ForEach(Service.Platforms) { Platform in Text(Platform.Name).tag(Platform.Id) }
                }.frame(maxWidth: 260)
                Toggle("Favorites", isOn: $FavoritesOnly).toggleStyle(.checkbox)
                Spacer()
            }
            if Games.isEmpty {
                EmptyPanel(Symbol: "gamecontroller", Title: Service.Games.isEmpty ? "Your retro library starts here" : "No matching games",
                           Message: "Choose Add ROM folder, select its console, and scan your local games. Configure an installed emulator in Consoles.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 245), spacing: 18)], spacing: 18) {
                    ForEach(Games) { Game in GameCard(Game) }
                }
            }
        }
    }

    private func GameCard(_ Game: RetroGame) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            ZStack {
                LinearGradient(colors: [Theme.Accent.opacity(0.26), Theme.Muted], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "gamecontroller.fill").font(.system(size: 55, weight: .light)).foregroundStyle(Theme.Accent.opacity(0.8))
            }.frame(height: 130).clipShape(RoundedRectangle(cornerRadius: 9))
            HStack(alignment: .top) {
                Text(Game.Name).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                Button { Perform { try Service.ToggleFavorite(Game) } } label: { Image(systemName: Game.Favorite ? "heart.fill" : "heart") }
                    .buttonStyle(MotionButtonStyle()).foregroundStyle(Game.Favorite ? Theme.Accent : Theme.SecondaryText)
            }
            Text(Service.Platforms.first(where: { $0.Id == Game.PlatformId })?.Name ?? Game.PlatformId).font(.caption).foregroundStyle(Theme.SecondaryText)
            HStack {
                if Service.RunningIds.contains(Game.Id) {
                    Button("Stop") { Task { do { try await Service.Stop(Game) } catch { Store.Report(error) } } }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Button { Launch(Game) } label: { Label("Play", systemImage: "play.fill") }.buttonStyle(PrimaryButtonStyle()).disabled(!Game.IsInstalled)
                }
                Spacer()
                Menu {
                    ForEach(Game.FilePaths, id: \.self) { Path in Button("Play " + URL(fileURLWithPath: Path).lastPathComponent) { Launch(Game, File: Path) } }
                    Divider()
                    Button("Console setup") { Editing = Service.Platforms.first { $0.Id == Game.PlatformId } }
                    Button("Show in Finder") { if let Path = Game.FilePaths.first { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Path)]) } }
                    Button("Remove from library") { Perform { try Service.Remove(Game) } }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
            }
            if !Game.IsInstalled || !Game.MissingDependencies.isEmpty { Text("Missing game files").font(.caption).foregroundStyle(.orange) }
            else if Game.PlayTimeSeconds > 0 { Text("\(Int(Game.PlayTimeSeconds / 60)) minutes played").font(.caption).foregroundStyle(Theme.SecondaryText) }
        }.padding(15).background(Theme.Card, in: RoundedRectangle(cornerRadius: 13))
    }

    private var Consoles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 18)], spacing: 18) {
            ForEach(Service.Platforms) { Platform in
                Panel(Padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(Platform.Name, systemImage: "gamecontroller").font(.headline)
                        Text("\(Service.Games.filter { $0.PlatformId == Platform.Id }.count) games").font(.caption).foregroundStyle(Theme.SecondaryText)
                        Text(Service.Profile(for: Platform).ExecutablePath.isEmpty ? "Choose an emulator to start playing" : URL(fileURLWithPath: Service.Profile(for: Platform).ExecutablePath).lastPathComponent)
                            .font(.caption).foregroundStyle(Theme.SecondaryText).lineLimit(1)
                        HStack {
                            Button("Set up") { Editing = Platform }.buttonStyle(SecondaryButtonStyle())
                            Button("Scan folder") { Import(Platform) }.buttonStyle(SecondaryButtonStyle()).disabled(Service.Scanning)
                        }
                    }
                }
            }
        }
    }

    private var Emulators: some View {
        VStack(alignment: .leading, spacing: 15) {
            Notice(Message: "Use an installed macOS emulator, or select Custom for an alternative. Console firmware and RetroArch cores are configured in their emulator.")
            ForEach(Service.Emulators) { Emulator in
                Panel(Padding: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Emulator.Name).font(.headline)
                            Text(Service.Platforms.filter { Emulator.Platforms.contains($0.Id) }.map(\.Name).joined(separator: ", ")).font(.caption).foregroundStyle(Theme.SecondaryText)
                        }
                        Spacer()
                        Button("Website") { Store.OpenExternal(Emulator.Website) }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private func Import(_ Platform: RetroPlatform) {
        guard let Folder = Store.ChooseFolder(Title: "Choose your \(Platform.Name) ROM folder") else { return }
        Task {
            do {
                let Count = try await Service.Scan(Platform: Platform, Folder: Folder)
                Store.Notice = "Found \(Count) \(Platform.Name) games."
                SelectedPlatform = Platform.Id
                Tab = "Library"
            } catch { Store.Report(error) }
        }
    }

    private func Launch(_ Game: RetroGame, File: String? = nil) {
        Task { do { try await Service.Launch(Game, FilePath: File) } catch { Store.Report(error) } }
    }
    private func Perform(_ Action: () throws -> Void) { do { try Action() } catch { Store.Report(error) } }
}

private struct RetroSetupView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.dismiss) private var Dismiss
    @ObservedObject var Service: RetroService
    let Platform: RetroPlatform
    @State private var Profile: RetroProfile
    @State private var Arguments: String

    init(Service: RetroService, Platform: RetroPlatform) {
        self.Service = Service
        self.Platform = Platform
        let Profile = Service.Profile(for: Platform)
        _Profile = State(initialValue: Profile)
        _Arguments = State(initialValue: Profile.Arguments.joined(separator: "\n"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(Title: Platform.Name, Subtitle: "Console setup", Symbol: "gamecontroller")
            Form {
                Picker("Emulator preset", selection: $Profile.Adapter) {
                    ForEach(Service.Emulators.filter { $0.Platforms.contains(Platform.Id) }) { Emulator in Text(Emulator.Name).tag(Emulator.Id) }
                    Text("Custom").tag("custom")
                }
                HStack {
                    TextField("Emulator app or executable", text: $Profile.ExecutablePath)
                    Button("Choose…") { ChooseExecutable() }
                }
                if Profile.Adapter == "retroarch" {
                    HStack {
                        TextField("RetroArch core path", text: $Profile.CorePath)
                        Button("Choose…") { ChooseCore() }
                    }
                }
                Toggle("Launch fullscreen", isOn: $Profile.Fullscreen)
                if Profile.Adapter == "custom" {
                    Text("One argument per line. Use {rom} where the game file belongs.").font(.caption).foregroundStyle(Theme.SecondaryText)
                    TextEditor(text: $Arguments).font(.system(.body, design: .monospaced)).frame(height: 110).border(Theme.Border)
                }
            }.formStyle(.grouped)
            if !Profile.Folders.isEmpty {
                Text("ROM folders").font(.headline)
                ForEach(Profile.Folders, id: \.self) { Folder in Text(Folder).font(.caption).textSelection(.enabled).foregroundStyle(Theme.SecondaryText) }
            }
            HStack {
                Spacer()
                Button("Cancel") { Dismiss() }.buttonStyle(SecondaryButtonStyle())
                Button("Save") {
                    do {
                        Profile.Arguments = try RetroService.CustomArguments(Arguments)
                        try Service.SaveProfile(Profile)
                        Dismiss()
                    } catch { Store.Report(error) }
                }.buttonStyle(PrimaryButtonStyle())
            }
        }.padding(28).frame(width: 620).background(Theme.Background)
    }

    private func ChooseExecutable() {
        let Panel = NSOpenPanel()
        Panel.title = "Choose the emulator app or executable"
        Panel.canChooseFiles = true
        Panel.canChooseDirectories = false
        Panel.treatsFilePackagesAsDirectories = false
        if Panel.runModal() == .OK, let URL = Panel.url { Profile.ExecutablePath = URL.path }
    }
    private func ChooseCore() {
        let Panel = NSOpenPanel()
        Panel.title = "Choose an installed RetroArch core"
        if Panel.runModal() == .OK, let URL = Panel.url { Profile.CorePath = URL.path }
    }
}
