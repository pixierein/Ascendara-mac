import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var Store: AppStore
    @State private var Section = "Appearance"
    @State private var ShowingCompatibility = false
    @State private var SaveTask: Task<Void, Never>?
    private let Sections = [("Appearance", "paintpalette"), ("General", "slider.horizontal.3"), ("Downloads", "arrow.down.circle"), ("Compatibility", "desktopcomputer"), ("Integrations", "point.3.connected.trianglepath.dotted"), ("Backups", "externaldrive"), ("About", "info.circle")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeading(Title: "Preferences", Subtitle: "Make Ascendara yours.")
                HStack(alignment: .top, spacing: 28) {
                    VStack(spacing: 4) {
                        ForEach(Sections, id: \.0) { Title, Symbol in
                            Button { Section = Title } label: {
                                Label(Title, systemImage: Symbol).font(.system(size: 13, weight: Section == Title ? .semibold : .regular)).frame(maxWidth: .infinity, alignment: .leading).padding(13)
                                    .foregroundStyle(Section == Title ? Theme.Accent : Theme.Foreground)
                                    .background(Section == Title ? Theme.Accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(MotionButtonStyle())
                        }
                        Divider().padding(.vertical, 12)
                        Button { Store.CurrentRoute = .Sources } label: { Label("External sources", systemImage: "externaldrive.connected.to.line.below").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(MotionButtonStyle()).padding(13)
                        Button { Store.CurrentRoute = .Tools } label: { Label("Tools & dependencies", systemImage: "wrench.and.screwdriver").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(MotionButtonStyle()).padding(13)
                    }.frame(width: 195)
                    ZStack(alignment: .topLeading) {
                        Group {
                            switch Section {
                            case "General": General
                            case "Downloads": Downloads
                            case "Compatibility": Compatibility
                            case "Integrations": Integrations
                            case "Backups": Backups
                            case "About": About
                            default: Appearance
                            }
                        }.id(Section).MotionTransition()
                    }.frame(maxWidth: .infinity)
                }
            }.padding(30).padding(.bottom, 100).frame(maxWidth: 1250).frame(maxWidth: .infinity)
        }.MotionAnimation(Section)
            .MotionAnimation(Store.Settings.Theme)
            .onChange(of: Store.Settings) { _, _ in
            SaveTask?.cancel()
            SaveTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled { Store.SaveSettings() }
            }
        }.onDisappear { SaveTask?.cancel(); Store.SaveSettings() }
            .sheet(isPresented: $ShowingCompatibility) { CompatibilityView().environmentObject(Store) }
    }
    private var Appearance: some View {
        Panel {
            VStack(alignment: .leading, spacing: 24) {
                SettingsHeading("Appearance", "Choose the colors and feel of your library.", "paintpalette")
                Text("Theme").font(.system(size: 13, weight: .semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), spacing: 12)], spacing: 12) {
                    ForEach(["purple", "light", "blue", "emerald", "rose", "amber", "dark", "midnight", "cyberpunk", "ocean", "forest", "sunset"], id: \.self) { Name in
                        Button { Store.Settings.Theme = Name } label: {
                            VStack(spacing: 9) {
                                RoundedRectangle(cornerRadius: 7).fill(ThemeSwatch(Name)).frame(height: 42)
                                    .overlay(alignment: .topTrailing) {
                                        if Store.Settings.Theme == Name { Image(systemName: "checkmark.circle.fill").foregroundStyle(.white).shadow(radius: 2).padding(6) }
                                    }
                                Text(Name.capitalized).font(.system(size: 11, weight: .medium))
                            }.padding(8).background(Theme.Background, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Store.Settings.Theme == Name ? Theme.Accent : Theme.Border, lineWidth: Store.Settings.Theme == Name ? 2 : 1))
                        }.buttonStyle(MotionButtonStyle())
                    }
                }
                Divider()
                Toggle("Reduce motion", isOn: $Store.Settings.ReduceMotion)
                HStack {
                    Text("Navigation size").font(.system(size: 13))
                    Spacer()
                    Slider(value: $Store.Settings.DockScale, in: 0.65...1.15, step: 0.05).frame(width: 190)
                    Text("\(Int(Store.Settings.DockScale * 100))%").font(.system(size: 11)).monospacedDigit().frame(width: 38)
                }
            }
        }
    }
    private var General: some View {
        Panel {
            VStack(alignment: .leading, spacing: 22) {
                SettingsHeading("General", "Personalize your profile and starting page.", "slider.horizontal.3")
                SettingsField("Display name", Text: $Store.Settings.DisplayName)
                Picker("Default landing page", selection: $Store.Settings.DefaultPage) {
                    ForEach(["Home", "Search", "Library", "Downloads"], id: \.self) { Page in Text(Page).tag(Page) }
                }
                Toggle("Show Workshop in navigation", isOn: $Store.Settings.ShowWorkshop)
                Divider()
                Button("Show welcome setup") { Store.ShowingWelcome = true }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }
    private var Downloads: some View {
        Panel {
            VStack(alignment: .leading, spacing: 22) {
                SettingsHeading("Downloads", "Choose where and how files arrive.", "arrow.down.circle")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Download directory").font(.system(size: 12, weight: .medium))
                    HStack {
                        TextField("Download directory", text: $Store.Settings.DownloadDirectory).textFieldStyle(.roundedBorder)
                        Button("Choose…") { Store.ChooseDownloadDirectory() }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                Stepper("Concurrent downloads: \(Store.Settings.ConcurrentDownloads)", value: $Store.Settings.ConcurrentDownloads, in: 1...8)
                Toggle("Extract supported archives when downloads finish", isOn: $Store.Settings.AutoExtract)
                Toggle("Keep this Mac awake during downloads", isOn: $Store.Settings.KeepAwake)
                Notice(Message: "ZIP and tar archives use macOS tools. Additional formats use the 7-Zip helper prepared by Setup and included in packaged builds.")
            }
        }
    }
    private var Compatibility: some View {
        Panel {
            VStack(alignment: .leading, spacing: 22) {
                SettingsHeading("Game compatibility", "Run native apps and configure Windows compatibility tools.", "desktopcomputer")
                SettingsField("Wine executable", Text: $Store.Settings.WinePath, Placeholder: "/opt/homebrew/bin/wine")
                SettingsField("Highball executable", Text: $Store.Settings.HighballPath, Placeholder: "/path/to/highball")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Default launch arguments").font(.system(size: 12, weight: .medium))
                    TextEditor(text: $Store.Settings.LaunchArguments).font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden).frame(height: 65).padding(8).background(Theme.Background, in: RoundedRectangle(cornerRadius: 8))
                    Text("One argument per line. Used when a game has no arguments of its own.").font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
                }
                Notice(Message: "Each game has its own launch mode, executable, arguments, and optional Wine prefix. Highball requires Apple Silicon and a separately installed runtime.")
                Button("Check compatibility runtimes") { ShowingCompatibility = true }.buttonStyle(SecondaryButtonStyle())
                Divider()
                Text("Retro games").font(.system(size: 15, weight: .semibold))
                SettingsField("Emulator executable", Text: $Store.Settings.RetroEmulatorPath, Placeholder: "/path/to/emulator")
                SettingsField("Emulator arguments", Text: $Store.Settings.RetroArguments, Placeholder: "{rom}")
            }
        }
    }
    private var Integrations: some View {
        VStack(spacing: 18) {
            Panel {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsHeading("TorBox", "Connect your account to use its download service.", "server.rack")
                    SecureField("TorBox API key", text: $Store.Settings.TorBoxAPIKey).textFieldStyle(.roundedBorder)
                    Button("Open TorBox downloads") { Store.CurrentRoute = .TorBox }.buttonStyle(SecondaryButtonStyle())
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsHeading("qBittorrent", "Connect to a running qBittorrent Web UI.", "network")
                    SettingsField("Web UI URL", Text: $Store.Settings.QBitTorrentURL)
                    SettingsField("Username", Text: $Store.Settings.QBitTorrentUsername)
                    SecureField("Password", text: $Store.Settings.QBitTorrentPassword).textFieldStyle(.roundedBorder)
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 18) {
                    SettingsHeading("Steam Workshop", "Use an installed SteamCMD for supported Workshop items.", "shippingbox")
                    SettingsField("SteamCMD executable", Text: $Store.Settings.SteamCMDPath, Placeholder: "/path/to/steamcmd")
                    Button("Open Workshop") { Store.CurrentRoute = .Workshop }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }
    private var Backups: some View {
        Panel {
            VStack(alignment: .leading, spacing: 22) {
                SettingsHeading("Backups", "Keep copies of your games and library metadata.", "externaldrive")
                HStack {
                    SettingsField("Backup directory", Text: $Store.Settings.BackupDirectory)
                    Button("Choose…") { ChooseBackupDirectory() }.buttonStyle(SecondaryButtonStyle()).padding(.top, 21)
                }
                Notice(Message: "Use a game's options menu to create or restore a backup. Library export saves entries and launch settings; game files are backed up separately.")
                HStack {
                    Button("Export library…") { Store.ExportLibrary() }.buttonStyle(SecondaryButtonStyle())
                    Button("Import library…") { Store.ImportLibrary() }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }
    private var About: some View {
        Panel {
            VStack(alignment: .leading, spacing: 20) {
                SettingsHeading("Ascendara for Mac", "A native SwiftUI client for your games.", "gamecontroller")
                Text("Native interface · macOS 14 or later").font(.system(size: 13)).foregroundStyle(Theme.SecondaryText)
                Text("Your library, profile, preferences, and cached game index are stored locally. Account integrations connect only when configured.").font(.system(size: 13)).foregroundStyle(Theme.SecondaryText).lineSpacing(5)
                HStack {
                    Button("Ascendara website ↗") { Store.OpenExternal("https://ascendara.app") }.buttonStyle(SecondaryButtonStyle())
                    Button("Source code ↗") { Store.OpenExternal("https://github.com/pixierein/ascendara") }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }
    private func ThemeSwatch(_ Name: String) -> Color {
        switch Name {
        case "purple": return .purple
        case "light": return Color(white: 0.85)
        case "blue": return .blue
        case "emerald", "forest": return .green
        case "rose", "cyberpunk": return .pink
        case "midnight": return .indigo
        case "ocean": return .cyan
        case "sunset", "amber": return .orange
        default: return Color(white: 0.2)
        }
    }
    private func ChooseBackupDirectory() {
        let Panel = NSOpenPanel()
        Panel.canChooseDirectories = true; Panel.canChooseFiles = false; Panel.canCreateDirectories = true
        if Panel.runModal() == .OK, let URL = Panel.url { Store.Settings.BackupDirectory = URL.path }
    }
}

struct SettingsHeading: View {
    let Title: String
    let Subtitle: String
    let Symbol: String
    init(_ Title: String, _ Subtitle: String, _ Symbol: String) { self.Title = Title; self.Subtitle = Subtitle; self.Symbol = Symbol }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Symbol).font(.system(size: 18)).foregroundStyle(Theme.Accent).frame(width: 40, height: 40).background(Theme.Accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(Title).font(.system(size: 17, weight: .semibold))
                Text(Subtitle).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
            }
        }
    }
}

struct SettingsField: View {
    let Title: String
    @Binding var Text: String
    var Placeholder = ""
    init(_ Title: String, Text: Binding<String>, Placeholder: String = "") { self.Title = Title; self._Text = Text; self.Placeholder = Placeholder }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SwiftUI.Text(Title).font(.system(size: 12, weight: .medium))
            TextField(Placeholder.isEmpty ? Title : Placeholder, text: $Text).textFieldStyle(.roundedBorder)
        }
    }
}

struct SourcesView: View {
    @EnvironmentObject var Store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(Title: "External sources", Subtitle: "Choose the index that powers your game discovery.")
                Panel {
                    VStack(alignment: .leading, spacing: 22) {
                        SettingsHeading("Game index", "Switch sources or bring your own catalog.", "square.stack.3d.up")
                        Picker("Source", selection: $Store.Settings.CatalogSource) {
                            Text("Ascendara community index").tag("community")
                            Text("Custom URL").tag("custom")
                            Text("Imported local index").tag("local")
                        }.pickerStyle(.radioGroup)
                        if Store.Settings.CatalogSource == "custom" {
                            SettingsField("Catalog URL", Text: $Store.Settings.CustomCatalogURL, Placeholder: "https://example.com/games.json")
                            Notice(Message: "Supports Ascendara JSON indexes and Hydra-style source catalogs.")
                        }
                        if Store.Settings.CatalogSource == "local" {
                            Text(Store.Settings.LocalCatalogPath.isEmpty ? "No local index selected" : Store.Settings.LocalCatalogPath).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText).textSelection(.enabled)
                            Button("Import JSON index…") { Store.ImportCatalog() }.buttonStyle(SecondaryButtonStyle())
                        }
                        HStack {
                            Button { Store.SaveSettings(); Store.RefreshCatalog() } label: { Label("Load selected source", systemImage: "arrow.clockwise") }.buttonStyle(PrimaryButtonStyle()).disabled(Store.IsLoading)
                            if Store.IsLoading { ProgressView().controlSize(.small) }
                            Spacer()
                            Text("\(Store.Games.count.formatted()) games indexed").font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                        }
                    }
                }
                if let Warning = Store.CatalogWarning { Notice(Message: Warning, Symbol: "exclamationmark.triangle") }
                Panel {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("Your existing library stays with you").font(.system(size: 16, weight: .semibold))
                        Text("Changing your source refreshes discovery and search. Your installed games and launch settings remain available in your library.").font(.system(size: 13)).foregroundStyle(Theme.SecondaryText)
                        Button("Open library") { Store.CurrentRoute = .Library }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }.padding(30).padding(.bottom, 100).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }.onChange(of: Store.Settings) { _, _ in Store.SaveSettings() }
    }
}

struct ToolsView: View {
    @EnvironmentObject var Store: AppStore
    @State private var ShowingCompatibility = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(Title: "Tools & dependencies", Subtitle: "Connect your library, compatibility runtimes, and download services.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 18)], spacing: 18) {
                    Tool("Steam library", "Discover installed Steam games on this Mac and add them to your library.", "gamecontroller", "Scan library", Store.ScanSteamLibrary)
                    Tool("Existing Ascendara library", "Import a library from an existing Ascendara installation.", "books.vertical", "Import existing library…", Store.ImportLegacyLibrary)
                    Tool("Compatibility runtimes", "Configure Wine or Highball, then choose a launch mode in each game's options.", "desktopcomputer", "Configure runtimes") { ShowingCompatibility = true }
                    Tool("Retro games", "Configure an emulator and launch your own ROM library.", "arcade.stick.console", "Open Retro") { Store.CurrentRoute = .Retro }
                    Tool("TorBox", "Manage downloads using your TorBox API key.", "server.rack", "Open TorBox") { Store.CurrentRoute = .TorBox }
                    Tool("Steam Workshop", "Download supported Workshop content using an installed SteamCMD.", "shippingbox", "Open Workshop") { Store.CurrentRoute = .Workshop }
                    Tool("External sources", "Choose the community index, a local JSON file, or a custom source.", "externaldrive.connected.to.line.below", "Manage sources") { Store.CurrentRoute = .Sources }
                    Tool("Library backup", "Export the local library manifest, including notes and launch settings.", "externaldrive", "Export library…", Store.ExportLibrary)
                }
            }.padding(30).padding(.bottom, 100).frame(maxWidth: 1300).frame(maxWidth: .infinity)
        }.sheet(isPresented: $ShowingCompatibility) { CompatibilityView().environmentObject(Store) }
    }
    private func Tool(_ Title: String, _ Description: String, _ Symbol: String, _ ActionTitle: String, _ Action: @escaping () -> Void) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: Symbol).font(.system(size: 23)).foregroundStyle(Theme.Accent)
                Text(Title).font(.system(size: 17, weight: .semibold))
                Text(Description).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText).frame(minHeight: 38, alignment: .topLeading)
                Button(ActionTitle, action: Action).buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
