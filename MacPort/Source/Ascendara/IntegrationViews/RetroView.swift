import AppKit
import SwiftUI

struct RetroView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.BigPictureActive) private var IsTV
    @Environment(\.TVScale) private var Scale
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
        Group {
            if IsTV { TVBody } else { DesktopBody }
        }.background(Theme.Background)
            .MotionAnimation(Tab)
            .MotionAnimation(SelectedPlatform)
            .MotionAnimation(FavoritesOnly)
            .sheet(item: $Editing) { Platform in RetroSetupView(Service: Service, Platform: Platform).environmentObject(Store) }
    }

    private var DesktopBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    PageHeading(Title: I18n.T("Retro"), Subtitle: I18n.T("Your classic games, consoles, and emulators in one place."))
                    if Service.Scanning { ProgressView().controlSize(.small) }
                    Menu {
                        ForEach(Service.Platforms) { Platform in Button(Platform.Name) { Import(Platform) } }
                    } label: {
                        Label(I18n.T("Add ROM folder"), systemImage: "folder.badge.plus")
                            .padding(10)
                            .background(Theme.Card, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .disabled(Service.Scanning)
                }
                HStack(spacing: 12) {
                    ForEach(["Library", "Consoles", "Emulators"], id: \.self) { Name in
                        Button { Tab = Name } label: {
                            Text(Name)
                                .fontWeight(Tab == Name ? .semibold : .regular)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .background(Tab == Name ? Theme.Accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(MotionButtonStyle())
                    }
                    Spacer()
                    Text(I18n.Interpolated("\(Service.Games.count) games · \(Service.Platforms.count) consoles")).font(.caption).foregroundStyle(Theme.SecondaryText)
                }
                if let Error = Service.ErrorMessage { Notice(Message: Error, Symbol: "exclamationmark.triangle") }
                if Tab == "Library" { Library }
                else if Tab == "Consoles" { Consoles }
                else { Emulators }
            }.padding(30)
        }
    }

    private var TVBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30 * Scale) {
                HStack(alignment: .center, spacing: 24 * Scale) {
                    TVPageHeading(Title: I18n.T("Retro"), Subtitle: I18n.Interpolated("\(Service.Games.count) games. \(Service.Platforms.count) consoles. Your classics, together."))
                    Spacer(minLength: 0)
                    if Service.Scanning { ProgressView().controlSize(.large) }
                    Menu {
                        ForEach(Service.Platforms) { Platform in Button(Platform.Name) { Import(Platform) } }
                    } label: { Label(I18n.T("Add ROM folder"), systemImage: "folder.badge.plus") }
                        .menuStyle(.borderlessButton).buttonStyle(TVButtonStyle(Prominent: true)).fixedSize().disabled(Service.Scanning)
                }
                TVIntegrationTabs(Titles: ["Library", "Consoles", "Emulators"], Selection: $Tab)
                if let Error = Service.ErrorMessage {
                    Label(Error, systemImage: "exclamationmark.triangle").font(.system(size: 21 * Scale)).foregroundStyle(.orange)
                }
                if Tab == "Library" { TVLibrary }
                else if Tab == "Consoles" { TVConsoles }
                else { TVEmulators }
            }.padding(.horizontal, 56 * Scale).padding(.vertical, 32 * Scale)
        }
    }

    private var TVLibrary: some View {
        VStack(alignment: .leading, spacing: 28 * Scale) {
            HStack(spacing: 18 * Scale) {
                TextField(I18n.T("Find a classic"), text: $Query).modifier(TVIntegrationFieldStyle())
                Picker(I18n.T("Console"), selection: $SelectedPlatform) {
                    Text(I18n.T("All consoles")).tag("all")
                    ForEach(Service.Platforms) { Platform in Text(Platform.Name).tag(Platform.Id) }
                }.labelsHidden().font(.system(size: 21 * Scale)).controlSize(.large).frame(maxWidth: 300 * Scale)
                Button { FavoritesOnly.toggle() } label: { Label(I18n.T("Favorites"), systemImage: FavoritesOnly ? "heart.fill" : "heart") }
                    .buttonStyle(TVButtonStyle(Selected: FavoritesOnly))
            }
            if Games.isEmpty {
                TVEmptyState(Symbol: "arcade.stick.console", Title: Service.Games.isEmpty ? "Bring your classics home" : "No matching games",
                             Message: I18n.T("Add a ROM folder for its console, then choose your emulator in Consoles."))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300 * Scale, maximum: 460 * Scale), spacing: 24 * Scale)], spacing: 28 * Scale) {
                    ForEach(Games) { Game in TVGameCard(Game) }
                }
            }
        }
    }

    private func TVGameCard(_ Game: RetroGame) -> some View {
        TVPanel {
            VStack(alignment: .leading, spacing: 18 * Scale) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [TVStyle.Accent.opacity(0.36), TVStyle.Panel], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "gamecontroller.fill").font(.system(size: 80 * Scale, weight: .light))
                        .foregroundStyle(.white.opacity(0.3)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(Service.Platforms.first(where: { $0.Id == Game.PlatformId })?.Name ?? Game.PlatformId)
                        .font(.system(size: 18 * Scale, weight: .medium)).padding(18 * Scale)
                }.frame(height: 180 * Scale).clipShape(RoundedRectangle(cornerRadius: 12 * Scale))
                Text(Game.Name).font(.system(size: 27 * Scale, weight: .semibold)).lineLimit(2)
                    .frame(minHeight: 66 * Scale, alignment: .topLeading)
                if !Game.IsInstalled || !Game.MissingDependencies.isEmpty {
                    Label(I18n.T("Missing game files"), systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                } else if Game.PlayTimeSeconds > 0 {
                    Text(I18n.Interpolated("\(Int(Game.PlayTimeSeconds / 60)) minutes played")).foregroundStyle(TVStyle.Secondary)
                } else { Text(I18n.T("Ready to play")).foregroundStyle(TVStyle.Secondary) }
                HStack(spacing: 12 * Scale) {
                    if Service.RunningIds.contains(Game.Id) {
                        Button(I18n.T("Stop")) { Task { do { try await Service.Stop(Game) } catch { Store.Report(error) } } }
                            .buttonStyle(TVButtonStyle(Prominent: true))
                    } else {
                        Button { Launch(Game) } label: { Label(I18n.T("Play"), systemImage: "play.fill") }
                            .buttonStyle(TVButtonStyle(Prominent: true)).disabled(!Game.IsInstalled)
                    }
                    Button { Perform { try Service.ToggleFavorite(Game) } } label: { Image(systemName: Game.Favorite ? "heart.fill" : "heart") }
                        .buttonStyle(TVButtonStyle(Selected: Game.Favorite)).accessibilityLabel(Game.Favorite ? "Remove favorite" : "Add favorite")
                }
                Menu {
                    ForEach(Game.FilePaths, id: \.self) { Path in Button(I18n.T("Play ") + URL(fileURLWithPath: Path).lastPathComponent) { Launch(Game, File: Path) } }
                    Divider()
                    Button(I18n.T("Console setup")) { Editing = Service.Platforms.first { $0.Id == Game.PlatformId } }
                    Button(I18n.T("Show in Finder")) { if let Path = Game.FilePaths.first { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Path)]) } }
                    Button(I18n.T("Remove from library")) { Perform { try Service.Remove(Game) } }
                } label: { Label(I18n.T("Game options"), systemImage: "ellipsis") }
                    .menuStyle(.borderlessButton).buttonStyle(TVButtonStyle()).fixedSize()
            }.font(.system(size: 19 * Scale))
        }
    }

    private var TVConsoles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 420 * Scale), spacing: 24 * Scale)], spacing: 24 * Scale) {
            ForEach(Service.Platforms) { Platform in
                TVPanel {
                    VStack(alignment: .leading, spacing: 22 * Scale) {
                        HStack {
                            Image(systemName: "arcade.stick.console").font(.system(size: 38 * Scale)).foregroundStyle(TVStyle.Accent)
                            Spacer()
                            Text(I18n.Interpolated("\(Service.Games.filter { $0.PlatformId == Platform.Id }.count)"))
                                .font(.system(size: 44 * Scale, weight: .semibold, design: .rounded))
                        }
                        Text(Platform.Name).font(.system(size: 29 * Scale, weight: .semibold))
                        Text(Service.Profile(for: Platform).ExecutablePath.isEmpty ? "Choose an emulator to start playing" : URL(fileURLWithPath: Service.Profile(for: Platform).ExecutablePath).lastPathComponent)
                            .font(.system(size: 20 * Scale)).foregroundStyle(TVStyle.Secondary).lineLimit(2)
                        HStack(spacing: 14 * Scale) {
                            Button(I18n.T("Console setup")) { Editing = Platform }.buttonStyle(TVButtonStyle(Prominent: true))
                            Button(I18n.T("Scan folder")) { Import(Platform) }.buttonStyle(TVButtonStyle()).disabled(Service.Scanning)
                        }
                    }
                }
            }
        }
    }

    private var TVEmulators: some View {
        VStack(alignment: .leading, spacing: 24 * Scale) {
            Text(I18n.T("Use an installed macOS emulator. Set up console firmware and RetroArch cores in the emulator itself."))
                .font(.system(size: 21 * Scale)).foregroundStyle(TVStyle.Secondary)
            ForEach(Service.Emulators) { Emulator in
                TVPanel {
                    HStack(spacing: 30 * Scale) {
                        Image(systemName: "desktopcomputer").font(.system(size: 42 * Scale)).foregroundStyle(TVStyle.Accent)
                        VStack(alignment: .leading, spacing: 12 * Scale) {
                            Text(Emulator.Name).font(.system(size: 28 * Scale, weight: .semibold))
                            Text(Service.Platforms.filter { Emulator.Platforms.contains($0.Id) }.map(\.Name).joined(separator: ", "))
                                .font(.system(size: 20 * Scale)).foregroundStyle(TVStyle.Secondary)
                        }
                        Spacer()
                        Button(I18n.T("Visit website")) { Store.OpenExternal(Emulator.Website) }.buttonStyle(TVButtonStyle())
                    }
                }
            }
        }
    }

    private var Library: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                TextField(I18n.T("Search your retro games"), text: $Query).textFieldStyle(.roundedBorder).frame(maxWidth: 340)
                Picker(I18n.T("Console"), selection: $SelectedPlatform) {
                    Text(I18n.T("All consoles")).tag("all")
                    ForEach(Service.Platforms) { Platform in Text(Platform.Name).tag(Platform.Id) }
                }.frame(maxWidth: 260)
                Toggle(I18n.T("Favorites"), isOn: $FavoritesOnly).toggleStyle(.checkbox)
                Spacer()
            }
            if Games.isEmpty {
                EmptyPanel(Symbol: "gamecontroller", Title: Service.Games.isEmpty ? "Your retro library starts here" : "No matching games",
                           Message: I18n.T("Choose Add ROM folder, select its console, and scan your local games. Configure an installed emulator in Consoles."))
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
                    Button(I18n.T("Stop")) { Task { do { try await Service.Stop(Game) } catch { Store.Report(error) } } }.buttonStyle(PrimaryButtonStyle())
                } else {
                    Button { Launch(Game) } label: { Label(I18n.T("Play"), systemImage: "play.fill") }.buttonStyle(PrimaryButtonStyle()).disabled(!Game.IsInstalled)
                }
                Spacer()
                Menu {
                    ForEach(Game.FilePaths, id: \.self) { Path in Button(I18n.T("Play ") + URL(fileURLWithPath: Path).lastPathComponent) { Launch(Game, File: Path) } }
                    Divider()
                    Button(I18n.T("Console setup")) { Editing = Service.Platforms.first { $0.Id == Game.PlatformId } }
                    Button(I18n.T("Show in Finder")) { if let Path = Game.FilePaths.first { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: Path)]) } }
                    Button(I18n.T("Remove from library")) { Perform { try Service.Remove(Game) } }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }.menuStyle(.borderlessButton).fixedSize()
            }
            if !Game.IsInstalled || !Game.MissingDependencies.isEmpty { Text(I18n.T("Missing game files")).font(.caption).foregroundStyle(.orange) }
            else if Game.PlayTimeSeconds > 0 { Text(I18n.Interpolated("\(Int(Game.PlayTimeSeconds / 60)) minutes played")).font(.caption).foregroundStyle(Theme.SecondaryText) }
        }.padding(15).background(Theme.Card, in: RoundedRectangle(cornerRadius: 13))
    }

    private var Consoles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 18)], spacing: 18) {
            ForEach(Service.Platforms) { Platform in
                Panel(Padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(Platform.Name, systemImage: "gamecontroller").font(.headline)
                        Text(I18n.Interpolated("\(Service.Games.filter { $0.PlatformId == Platform.Id }.count) games")).font(.caption).foregroundStyle(Theme.SecondaryText)
                        Text(Service.Profile(for: Platform).ExecutablePath.isEmpty ? "Choose an emulator to start playing" : URL(fileURLWithPath: Service.Profile(for: Platform).ExecutablePath).lastPathComponent)
                            .font(.caption).foregroundStyle(Theme.SecondaryText).lineLimit(1)
                        HStack {
                            Button(I18n.T("Set up")) { Editing = Platform }.buttonStyle(SecondaryButtonStyle())
                            Button(I18n.T("Scan folder")) { Import(Platform) }.buttonStyle(SecondaryButtonStyle()).disabled(Service.Scanning)
                        }
                    }
                }
            }
        }
    }

    private var Emulators: some View {
        VStack(alignment: .leading, spacing: 15) {
            Notice(Message: I18n.T("Use an installed macOS emulator, or select Custom for an alternative. Console firmware and RetroArch cores are configured in their emulator."))
            ForEach(Service.Emulators) { Emulator in
                Panel(Padding: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Emulator.Name).font(.headline)
                            Text(Service.Platforms.filter { Emulator.Platforms.contains($0.Id) }.map(\.Name).joined(separator: ", ")).font(.caption).foregroundStyle(Theme.SecondaryText)
                        }
                        Spacer()
                        Button(I18n.T("Website")) { Store.OpenExternal(Emulator.Website) }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private func Import(_ Platform: RetroPlatform) {
        guard let Folder = Store.ChooseFolder(Title: I18n.Interpolated("Choose your \(Platform.Name) ROM folder")) else { return }
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

struct RetroSetupView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.dismiss) private var Dismiss
    @Environment(\.BigPictureActive) private var IsTV
    @Environment(\.TVScale) private var Scale
    @ObservedObject var Service: RetroService
    let Platform: RetroPlatform
    @State private var Profile: RetroProfile
    @State private var Arguments: String
    @StateObject private var Installer = EmulatorInstaller()

    init(Service: RetroService, Platform: RetroPlatform) {
        self.Service = Service
        self.Platform = Platform
        let Profile = Service.Profile(for: Platform)
        _Profile = State(initialValue: Profile)
        _Arguments = State(initialValue: Profile.Arguments.joined(separator: "\n"))
    }

    var body: some View {
        Group {
            if IsTV { TVBody } else { DesktopBody }
        }
        .onAppear {
            if Profile.ExecutablePath.isEmpty, let App = Installer.FindInstalled(Profile.Adapter) { Profile.ExecutablePath = App.path }
        }
    }

    private var TVBody: some View {
        VStack(alignment: .leading, spacing: 24 * Scale) {
            TVPageHeading(Title: Platform.Name, Subtitle: I18n.T("Choose how your classics play."))
            ScrollView {
                VStack(alignment: .leading, spacing: 24 * Scale) {
                    TVPanel {
                        VStack(alignment: .leading, spacing: 22 * Scale) {
                            Picker(I18n.T("Emulator"), selection: $Profile.Adapter) {
                                ForEach(Service.Emulators.filter { $0.Platforms.contains(Platform.Id) }) { Emulator in Text(Emulator.Name).tag(Emulator.Id) }
                                Text(I18n.T("Custom")).tag("custom")
                            }.controlSize(.large)
                            Text(I18n.T("Emulator app or executable")).fontWeight(.medium)
                            AutomaticSetup
                            HStack(spacing: 16 * Scale) {
                                TextField(I18n.T("Choose an emulator"), text: $Profile.ExecutablePath).modifier(TVIntegrationFieldStyle())
                                Button(I18n.T("Choose…")) { ChooseExecutable() }.buttonStyle(TVButtonStyle())
                            }
                            if Profile.Adapter == "retroarch" {
                                Text(I18n.T("RetroArch core")).fontWeight(.medium)
                                HStack(spacing: 16 * Scale) {
                                    TextField(I18n.T("Core path"), text: $Profile.CorePath).modifier(TVIntegrationFieldStyle())
                                    Button(I18n.T("Choose…")) { ChooseCore() }.buttonStyle(TVButtonStyle())
                                }
                            }
                            Toggle(I18n.T("Launch fullscreen"), isOn: $Profile.Fullscreen).toggleStyle(.switch).controlSize(.large)
                            if Profile.Adapter == "custom" {
                                Text(I18n.T("One argument per line. Use {rom} for the game file.")).foregroundStyle(TVStyle.Secondary)
                                TextEditor(text: $Arguments).font(.system(size: 20 * Scale, design: .monospaced))
                                    .scrollContentBackground(.hidden).frame(height: 140 * Scale)
                                    .padding(16 * Scale).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12 * Scale))
                            }
                        }
                    }
                    if !Profile.Folders.isEmpty {
                        TVPanel {
                            VStack(alignment: .leading, spacing: 14 * Scale) {
                                Text(I18n.T("ROM folders")).font(.system(size: 26 * Scale, weight: .semibold))
                                ForEach(Profile.Folders, id: \.self) { Folder in
                                    Text(Folder).foregroundStyle(TVStyle.Secondary).textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 18 * Scale) {
                Spacer()
                Button(I18n.T("Cancel")) { Dismiss() }.buttonStyle(TVButtonStyle()).keyboardShortcut(.cancelAction)
                Button(I18n.T("Save console")) { Save() }.buttonStyle(TVButtonStyle(Prominent: true))
            }
        }.font(.system(size: 21 * Scale)).padding(32 * Scale)
            .frame(width: 900 * Scale, height: 720 * Scale).background(TVStyle.Background)
    }

    private var DesktopBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionHeading(Title: Platform.Name, Subtitle: I18n.T("Console setup"), Symbol: "gamecontroller")
            Form {
                Picker(I18n.T("Emulator preset"), selection: $Profile.Adapter) {
                    ForEach(Service.Emulators.filter { $0.Platforms.contains(Platform.Id) }) { Emulator in Text(Emulator.Name).tag(Emulator.Id) }
                    Text(I18n.T("Custom")).tag("custom")
                }
                HStack {
                    TextField(I18n.T("Emulator app or executable"), text: $Profile.ExecutablePath)
                    Button(I18n.T("Choose…")) { ChooseExecutable() }
                }
                AutomaticSetup
                if Profile.Adapter == "retroarch" {
                    HStack {
                        TextField(I18n.T("RetroArch core path"), text: $Profile.CorePath)
                        Button(I18n.T("Choose…")) { ChooseCore() }
                    }
                }
                Toggle(I18n.T("Launch fullscreen"), isOn: $Profile.Fullscreen)
                if Profile.Adapter == "custom" {
                    Text(I18n.T("One argument per line. Use {rom} where the game file belongs.")).font(.caption).foregroundStyle(Theme.SecondaryText)
                    TextEditor(text: $Arguments).font(.system(.body, design: .monospaced)).frame(height: 110).border(Theme.Border)
                }
            }.formStyle(.grouped)
            if !Profile.Folders.isEmpty {
                Text(I18n.T("ROM folders")).font(.headline)
                ForEach(Profile.Folders, id: \.self) { Folder in Text(Folder).font(.caption).textSelection(.enabled).foregroundStyle(Theme.SecondaryText) }
            }
            HStack {
                Spacer()
                Button(I18n.T("Cancel")) { Dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Button(I18n.T("Save")) { Save() }.buttonStyle(PrimaryButtonStyle())
            }
        }.padding(28).frame(width: 620).background(Theme.Background)
    }

    private var AutomaticSetup: some View {
        VStack(alignment: .leading, spacing: 8) {
            if EmulatorInstaller.Supports(Profile.Adapter) {
                Button(I18n.T(Installer.Installing ? "Installing…" : "Set up emulator automatically")) {
                    let Adapter = Profile.Adapter
                    Task {
                        do {
                            let Result = try await Installer.Install(Adapter: Adapter, Platform: Platform.Id)
                            guard Profile.Adapter == Adapter else { return }
                            Profile.ExecutablePath = Result.App.path
                            if let Core = Result.Core { Profile.CorePath = Core.path }
                            try Service.SaveProfile(Profile)
                        } catch { Store.Report(error) }
                    }
                }.disabled(Installer.Installing)
                if !Installer.Status.isEmpty { Text(I18n.T(Installer.Status)).font(.caption).foregroundStyle(Theme.SecondaryText) }
            }
        }
    }

    private func Save() {
        do {
            Profile.Arguments = try RetroService.CustomArguments(Arguments)
            try Service.SaveProfile(Profile)
            Dismiss()
        } catch { Store.Report(error) }
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
