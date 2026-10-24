import AppKit
import GameController
import ServiceManagement
import SwiftUI

struct PreferencesDashboardView: View {
    @EnvironmentObject private var Store: AppStore
    @State private var Section = "General"
    @State private var ShowingCompatibility = false
    @State private var SaveTask: Task<Void, Never>?
    @State private var NewBlockedId = ""
    @State private var QBitStatus: String?
    @State private var CheckingQBit = false
    @State private var BackupCount = 0
    @State private var LightThemesExpanded = false
    @State private var DarkThemesExpanded = false
    @State private var OpensAtLogin = false
    @State private var LoginItemError: String?
    @State private var SupportNoteExpanded = false
    @State private var TorBoxDraft = ""
    @State private var RuntimeStatus = CompatibilityStatus()
    @State private var InstallingCompatibility = false
    @State private var CompatibilityResult: String?

    private let Sections: [(String, String)] = [
        ("General", "slider.horizontal.3"), ("Game Index", "externaldrive"),
        ("Downloads", "arrow.down.to.line"), ("Gaming", "gamecontroller"),
        ("Saves & Backups", "folder.badge.gearshape"), ("Compatibility", "terminal"),
        ("Tools", "shippingbox"), ("Advanced", "flask")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Ascendara Preferences").font(.system(size: 30, weight: .bold))
                    Spacer()
                    Text("v\(AppVersion.Current)")
                        .font(.system(size: 13)).foregroundStyle(Theme.SecondaryText)
                }
                HStack(alignment: .top, spacing: 28) {
                    Sidebar.frame(width: 218)
                    VStack(alignment: .leading, spacing: 18) {
                        switch Section {
                        case "Game Index": GameIndex
                        case "Downloads": Downloads
                        case "Gaming": Gaming
                        case "Saves & Backups": Saves
                        case "Compatibility": Compatibility
                        case "Tools": Tools
                        case "Advanced": Advanced
                        default: General
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .id(Section)
                    .MotionTransition()
                }
            }
            .padding(30).padding(.bottom, 115)
            .frame(maxWidth: 1450).frame(maxWidth: .infinity)
        }
        .background(Theme.Background)
        .MotionAnimation(Section)
        .onChange(of: Store.Settings) { _, _ in
            SaveTask?.cancel()
            SaveTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled { Store.SaveSettings() }
            }
        }
        .onDisappear { SaveTask?.cancel(); Store.SaveSettings() }
        .sheet(isPresented: $ShowingCompatibility) { CompatibilityView().environmentObject(Store) }
        .task { OpensAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private var Sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Sections, id: \.0) { Title, Symbol in
                Button { Section = Title } label: {
                    Label(Title, systemImage: Symbol)
                        .font(.system(size: 13, weight: Section == Title ? .semibold : .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .foregroundStyle(Section == Title ? Theme.Accent : Theme.SecondaryText)
                        .background(Section == Title ? Theme.Accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(MotionButtonStyle())
            }
            VStack(alignment: .leading, spacing: 11) {
                Label("Hey there, please read this!", systemImage: "hand.raised")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.orange)
                Text("Please support the developers by purchasing games you enjoy.")
                    .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                if SupportNoteExpanded {
                    Text("Ascendara is made possible by developers and publishers. Buy games you enjoy whenever you can.")
                        .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                }
                Button(SupportNoteExpanded ? "Show less" : "Read more") { SupportNoteExpanded.toggle() }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.5)))
            .padding(.top, 18)
        }
    }

    private var General: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeading("General", "Appearance, startup behavior and language.", "slider.horizontal.3")
            TwoColumns {
                PreferenceCard {
                    VStack(alignment: .leading, spacing: 20) {
                        CardTitle("APPEARANCE")
                        Text("App Themes").font(.system(size: 13, weight: .semibold))
                        Button {
                            let Show = !(LightThemesExpanded && DarkThemesExpanded)
                            LightThemesExpanded = Show
                            DarkThemesExpanded = Show
                        } label: {
                            Label("Choose Theme", systemImage: "paintpalette")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(SecondaryButtonStyle())
                        ThemeChoices("Light Themes", Names: ["light", "purple", "blue", "emerald", "rose", "amber"], Expanded: $LightThemesExpanded)
                        ThemeChoices("Dark Themes", Names: ["dark", "midnight", "cyberpunk", "ocean", "forest", "sunset"], Expanded: $DarkThemesExpanded)
                        PreferenceToggle("Smooth Transitions", "Animate navigation and page changes.", Value: Binding(
                            get: { !Store.Settings.ReduceMotion }, set: { Store.Settings.ReduceMotion = !$0 }))
                        PreferenceToggle("Side Scroll Bar", "Show a scroll bar beside pages.", Value: $Store.Settings.ShowScrollBar)
                        PreferenceToggle("Home Search Bar", "Show search and quick links on Home.", Value: $Store.Settings.ShowHomeSearchBar)
                    }
                }
            } Right: {
                PreferenceCard {
                    VStack(alignment: .leading, spacing: 22) {
                        CardTitle("APPLICATION")
                        Picker("Default Landing Page", selection: $Store.Settings.DefaultPage) {
                            ForEach(["Home", "Search", "Library", "Downloads"], id: \.self) { Text($0).tag($0) }
                        }
                        Text("Choose which page opens when you start Ascendara.")
                            .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                        PreferenceToggle("Open Ascendara on Startup", "Launch Ascendara when you sign in to this Mac.", Value: Binding(
                            get: { OpensAtLogin }, set: { SetLoginItem($0) }))
                        if let LoginItemError {
                            Label(LoginItemError, systemImage: "exclamationmark.triangle")
                                .font(.system(size: 11)).foregroundStyle(.orange)
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Onboarding").font(.system(size: 13, weight: .semibold))
                            Text("Run the welcome setup again to test a new installation.")
                                .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                            Button("Show onboarding again") { Store.ReplayWelcome() }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
            }
        }
    }

    private var GameIndex: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeading("Game Index", "The game list Ascendara searches, kept up to date while the app is open.", "externaldrive")
            TwoColumns {
                VStack(spacing: 16) {
                    PreferenceCard {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Text("Ascendara Index").font(.system(size: 16, weight: .semibold))
                                Text(Store.Settings.CatalogSource == "local" ? "Local file" : Store.Settings.CatalogSource == "custom" ? "Custom source" : "Community source")
                                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.green)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                            }
                            Text("Games from the currently selected index.")
                                .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                            HStack(spacing: 10) {
                                IndexMetric("GAMES", "\(Store.Games.count.formatted())")
                                IndexMetric("LAST REFRESH", LastIndexRefresh)
                                IndexMetric("INDEX AGE", IndexAge)
                            }
                            Button { Store.RefreshCatalog() } label: {
                                Label(Store.IsLoading ? "Refreshing…" : "Refresh now", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }.buttonStyle(PrimaryButtonStyle()).disabled(Store.IsLoading)
                            HStack {
                                Button("Use bundled Ascendara index") { Store.UseBundledCatalog() }
                                    .buttonStyle(SecondaryButtonStyle())
                                Button("Import JSON file…") { Store.ImportCatalog() }
                                    .buttonStyle(SecondaryButtonStyle())
                            }
                            if let Warning = Store.CatalogWarning {
                                Text(Warning).font(.system(size: 11)).foregroundStyle(.orange)
                            }
                        }
                    }
                    PreferenceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("External Sources", systemImage: "globe")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Choose the community index, a custom source, or a local JSON catalogue.")
                                .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                            Button("Manage sources →") { Store.CurrentRoute = .Sources }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
            } Right: {
                PreferenceCard {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Settings").font(.system(size: 16, weight: .semibold))
                        PreferenceToggle("Keep Index Up to Date", "Refresh the game index hourly while Ascendara is open.", Value: $Store.Settings.AutoRefreshIndex)
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Storage Location").font(.system(size: 13, weight: .semibold))
                            Text("Where index files are saved on this Mac.").font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                            HStack {
                                Text(AppPaths.Support.appendingPathComponent("CatalogCache").path)
                                    .font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button {
                                    let Folder = AppPaths.Support.appendingPathComponent("CatalogCache")
                                    try? FileManager.default.createDirectory(at: Folder, withIntermediateDirectories: true)
                                    NSWorkspace.shared.open(Folder)
                                } label: { Image(systemName: "folder") }
                                    .buttonStyle(.plain)
                            }.padding(10).background(Theme.Background, in: RoundedRectangle(cornerRadius: 8))
                        }
                        Divider()
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Blacklisted Games").font(.system(size: 13, weight: .semibold))
                            Text("Game IDs listed here will not appear in search or Home.")
                                .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                            HStack {
                                TextField("Game ID", text: $NewBlockedId).textFieldStyle(.roundedBorder)
                                Button { AddBlockedId() } label: { Image(systemName: "plus") }
                                    .buttonStyle(SecondaryButtonStyle()).disabled(NewBlockedId.isEmpty)
                            }
                            FlowBlockedIds
                        }
                    }
                }
            }
        }
    }

    private var FlowBlockedIds: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Store.Settings.BlacklistedGameIds, id: \.self) { Id in
                HStack {
                    Text(Id).font(.system(size: 11, design: .monospaced))
                    Spacer()
                    Button { RemoveBlockedId(Id) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                }.padding(.horizontal, 9).padding(.vertical, 6)
                    .background(Theme.Muted.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var Downloads: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeading("Downloads", "How games download, where they go, and torrent and debrid services.", "arrow.down.to.line")
            TwoColumns {
                VStack(spacing: 16) {
                    PreferenceCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("Download Manager").font(.system(size: 16, weight: .semibold))
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Concurrent Downloads").font(.system(size: 13, weight: .semibold))
                                Text("Choose how many games Ascendara downloads at once.")
                                    .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                                HStack {
                                    Button { Store.Settings.ConcurrentDownloads = max(1, Store.Settings.ConcurrentDownloads - 1) } label: { Image(systemName: "chevron.left") }
                                        .disabled(Store.Settings.ConcurrentDownloads <= 1)
                                    Spacer()
                                    Text("\(Store.Settings.ConcurrentDownloads)").font(.system(size: 25, weight: .semibold)).monospacedDigit()
                                    Text(Store.Settings.ConcurrentDownloads == 1 ? "game" : "games").font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                                    Spacer()
                                    Button { Store.Settings.ConcurrentDownloads = min(8, Store.Settings.ConcurrentDownloads + 1) } label: { Image(systemName: "chevron.right") }
                                        .disabled(Store.Settings.ConcurrentDownloads >= 8)
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .padding(14).background(Theme.Muted.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                            }
                            PreferenceToggle("Single Stream Download", "Use one connection per file. Turn off to split supported files into parallel ranges.", Value: $Store.Settings.SingleStreamDownload)
                            if !Store.Settings.SingleStreamDownload {
                                Stepper("Connections per file: \(Store.Settings.DownloadThreads)", value: $Store.Settings.DownloadThreads, in: 1...32)
                            }
                            HStack {
                                Text("Speed limit (KB/s)").font(.system(size: 13))
                                Spacer()
                                TextField("0 = unlimited", value: $Store.Settings.DownloadSpeedLimitKBps, format: .number)
                                    .textFieldStyle(.roundedBorder).frame(width: 145)
                            }
                            PreferenceToggle("Extract after Download", "Unpack supported archives when a download finishes.", Value: $Store.Settings.AutoExtract)
                            PreferenceToggle("Prevent Sleep", "Keep this Mac awake during downloads and gameplay.", Value: $Store.Settings.KeepAwake)
                        }
                    }
                    PreferenceCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Download Locations").font(.system(size: 16, weight: .semibold))
                            Text("Default Download Location").font(.system(size: 13, weight: .semibold))
                            HStack {
                                Text(Store.Settings.DownloadDirectory).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10).background(Theme.Background, in: RoundedRectangle(cornerRadius: 7))
                                Button("Select Directory") { Store.ChooseDownloadDirectory() }.buttonStyle(PrimaryButtonStyle())
                            }
                        }
                    }
                }
            } Right: {
                VStack(spacing: 16) {
                    PreferenceCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("TorBox").font(.system(size: 16, weight: .semibold))
                            Text("Debrid services convert supported links into direct downloads. Set your TorBox API key to enable available routes.")
                                .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                            HStack {
                                SecureField("Paste TorBox API key", text: $TorBoxDraft)
                                    .textFieldStyle(.roundedBorder)
                                Button("Set") { Store.Settings.TorBoxAPIKey = TorBoxDraft; Store.SaveSettings() }
                                    .buttonStyle(SecondaryButtonStyle())
                                    .disabled(TorBoxDraft == Store.Settings.TorBoxAPIKey)
                            }
                            HStack {
                                Button("Learn how to get your API key ↗") { Store.OpenExternal("https://ascendara.app/docs/features/torbox-integration") }
                                    .buttonStyle(.plain).foregroundStyle(Theme.Accent)
                                Spacer()
                                Button("Open TorBox") { Store.CurrentRoute = .TorBox }.buttonStyle(.plain).foregroundStyle(Theme.Accent)
                            }.font(.system(size: 12))
                        }
                    }
                    PreferenceCard {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Torrenting").font(.system(size: 16, weight: .semibold))
                            Text("Connect a running qBittorrent Web UI to send magnet links from Ascendara.")
                                .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                            HStack {
                                Circle().fill(QBitStatus == "Connected" ? Color.green : Theme.SecondaryText).frame(width: 8, height: 8)
                                Text("qBittorrent Web UI \(QBitStatus == "Connected" ? "Active" : QBitStatus == nil ? "Not checked" : "Inactive")")
                                    .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                            }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.Muted.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                            SettingsField("Web UI URL", Text: $Store.Settings.QBitTorrentURL)
                            SettingsField("Username", Text: $Store.Settings.QBitTorrentUsername)
                            SecureField("Password", text: $Store.Settings.QBitTorrentPassword).textFieldStyle(.roundedBorder)
                            HStack {
                                Button(CheckingQBit ? "Checking…" : "Test connection") { TestQBit() }
                                    .buttonStyle(SecondaryButtonStyle()).disabled(CheckingQBit)
                                if let QBitStatus { Text(QBitStatus).font(.system(size: 11)).foregroundStyle(Theme.SecondaryText) }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { TorBoxDraft = Store.Settings.TorBoxAPIKey }
    }

    private var Gaming: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeading("Gaming", "Launching games, Discord status, Big Picture and achievement tracking.", "gamecontroller")
            TwoColumns {
                PreferenceCard {
                    VStack(alignment: .leading, spacing: 21) {
                        PreferenceToggle("Hide on Game Launch", "Hide Ascendara after starting a game.", Value: $Store.Settings.HideOnGameLaunch)
                        PreferenceToggle("Prevent Sleep", "Keep this Mac awake while a game is running.", Value: $Store.Settings.KeepAwake)
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Default launch arguments").font(.system(size: 13, weight: .semibold))
                            TextEditor(text: $Store.Settings.LaunchArguments)
                                .font(.system(size: 11, design: .monospaced))
                                .scrollContentBackground(.hidden).frame(height: 75).padding(8)
                                .background(Theme.Background, in: RoundedRectangle(cornerRadius: 8))
                            Text("One argument per line when a game has no custom arguments.")
                                .font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
                        }
                    }
                }
            } Right: {
                PreferenceCard {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Big Picture Mode").font(.system(size: 16, weight: .semibold))
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "gamecontroller").font(.system(size: 18)).foregroundStyle(Theme.Accent)
                                .frame(width: 34, height: 34).background(Theme.Accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(GCController.controllers().isEmpty ? "No Controller Detected" : "Controller Connected")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(GCController.controllers().isEmpty ? "Connect a controller or use the keyboard to navigate Big Picture." : "Your controller is ready for Big Picture.")
                                    .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                            }
                            Spacer()
                        }.padding(13).background(Theme.Muted.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
                        Button { Store.ShowingBigPicture = true } label: {
                            Label("Enter Big Picture", systemImage: "gamecontroller").frame(maxWidth: .infinity)
                        }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
        }
    }

    private var Saves: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeading("Saves & Backups", "Back up game files and library metadata.", "folder.badge.gearshape")
            PreferenceCard {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Game Backups").font(.system(size: 16, weight: .semibold))
                    HStack(alignment: .bottom) {
                        SettingsField("Backup Location", Text: $Store.Settings.BackupDirectory)
                        Button("Select Directory") { ChooseBackupDirectory() }.buttonStyle(PrimaryButtonStyle())
                    }
                    Text("\(BackupCount) local backups. Use a game's library menu to create or restore its files.")
                        .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                    Divider()
                    Text("Library Metadata").font(.system(size: 15, weight: .semibold))
                    HStack {
                        Button("Export library…") { Store.ExportLibrary() }.buttonStyle(SecondaryButtonStyle())
                        Button("Import library…") { Store.ImportLibrary() }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .task { BackupCount = (try? await BackupService(StorageDirectory: URL(fileURLWithPath: Store.Settings.BackupDirectory)).List().count) ?? 0 }
        }
    }

    private var Compatibility: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeading("Compatibility", "Play supported Windows games on your Mac.", "terminal")
            PreferenceCard {
                VStack(alignment: .leading, spacing: 19) {
                    HStack(spacing: 12) {
                        Image(systemName: Store.Compatibility.IsReady ? "checkmark.shield.fill" : "shippingbox")
                            .font(.system(size: 25)).foregroundStyle(Store.Compatibility.IsReady ? .green : Theme.Accent)
                            .frame(width: 52, height: 52)
                            .background(Theme.Accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Store.Compatibility.IsReady ? "Ready to play" : "Compatibility files needed")
                                .font(.system(size: 17, weight: .semibold))
                            Text(Store.Compatibility.IsReady
                                 ? (Store.Compatibility.IsHighballReady ? "Highball and its game environment are ready." : "Wine is ready.")
                                 : (RuntimeStatus.AppleSilicon
                                    ? "Download once to set up Windows game support automatically."
                                    : "Highball requires Apple Silicon. Choose an installed Wine runtime in Advanced options."))
                                .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                        }
                        Spacer()
                    }
                    if !Store.Compatibility.IsReady && RuntimeStatus.AppleSilicon {
                        Button {
                            InstallingCompatibility = true
                            CompatibilityResult = nil
                            Task {
                                defer { InstallingCompatibility = false }
                                do {
                                    try await Store.Compatibility.EnsureReady()
                                    RuntimeStatus = await Store.Compatibility.Detect()
                                    guard Store.Compatibility.IsReady else {
                                        throw RuntimeError.Message("Setup finished, but the game environment could not be verified.")
                                    }
                                    CompatibilityResult = "Windows game support is ready."
                                } catch { Store.Report(error) }
                            }
                        } label: {
                            HStack {
                                if InstallingCompatibility { ProgressView().controlSize(.small) }
                                Text(InstallingCompatibility ? "Setting up…" : "Download")
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(PrimaryButtonStyle()).disabled(InstallingCompatibility)
                    }
                    if InstallingCompatibility {
                        CompatibilitySetupProgressView(Service: Store.Compatibility)
                    }
                    if let CompatibilityResult {
                        Label(CompatibilityResult, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12)).foregroundStyle(.green)
                    }
                    HStack(spacing: 17) {
                        Button("Advanced options") { ShowingCompatibility = true }
                        Button("Check again") { Task { RuntimeStatus = await Store.Compatibility.Detect() } }
                    }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.Accent)
                    .disabled(InstallingCompatibility)
                    Text("Game support varies by title. Highball is a free, open source project.")
                        .font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
                }
            }
            .task { RuntimeStatus = await Store.Compatibility.Detect() }
        }
    }

    private var Tools: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeading("Tools", "Game sources, Workshop downloader and app components.", "shippingbox")
            TwoColumns {
                PreferenceCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Ascendara Timemachine", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Explore older download links when your chosen catalogue has history available.")
                            .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                        Button("Open game sources") { Store.CurrentRoute = .Sources }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            } Right: {
                PreferenceCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Workshop Downloader", systemImage: "shippingbox")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Download public Steam Workshop items with your installed SteamCMD.")
                            .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                        SettingsField("SteamCMD executable", Text: $Store.Settings.SteamCMDPath, Placeholder: "/path/to/steamcmd")
                        PreferenceToggle("Show in Navigation Bar", "Add Workshop to the bottom dock.", Value: $Store.Settings.ShowWorkshop)
                        Button("Open Workshop") { Store.CurrentRoute = .Workshop }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private var Advanced: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeading("Advanced", "Update branch, support and developer options.", "flask")
            TwoColumns {
                PreferenceCard {
                    VStack(alignment: .leading, spacing: 17) {
                        Label("App Branch", systemImage: "flask").font(.system(size: 16, weight: .semibold))
                        Text("Choose your release channel. Branch switching is not available on macOS in the original Ascendara build.")
                            .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                        BranchRow("Live", "The stable release. Recommended for all users.", Color.green, Active: true)
                        BranchRow("Public Testing", "Early access to upcoming features before they ship to Live.", Color.yellow, Active: false)
                        BranchRow("Experimental", "Cutting-edge builds with the latest changes.", Color.red, Active: false)
                        Button("Open app data folder") { NSWorkspace.shared.open(AppPaths.Support) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            } Right: {
                PreferenceCard {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Quick Support", systemImage: "questionmark.bubble")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Get help with Ascendara or report a problem with this Mac build.")
                            .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                        Button("Get Help") { Store.OpenExternal("https://ascendara.app/docs") }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
        }
    }

    private func TwoColumns<Left: View, Right: View>(@ViewBuilder _ LeftContent: () -> Left, @ViewBuilder Right RightContent: () -> Right) -> some View {
        HStack(alignment: .top, spacing: 16) {
            LeftContent().frame(maxWidth: .infinity, alignment: .topLeading)
            RightContent().frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func CardTitle(_ Title: String) -> some View {
        Text(Title).font(.system(size: 11, weight: .bold)).tracking(1.3).foregroundStyle(Theme.SecondaryText)
    }

    private func ThemeChoices(_ Title: String, Names: [String], Expanded: Binding<Bool>) -> some View {
        DisclosureGroup(Title, isExpanded: Expanded) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ForEach(Names, id: \.self) { Name in
                    Button { Store.Settings.Theme = Name } label: {
                        HStack(spacing: 5) {
                            Circle().fill(ThemeSwatch(Name)).frame(width: 12, height: 12)
                            Text(ThemeTitle(Name)).font(.system(size: 11)).lineLimit(1)
                        }
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Store.Settings.Theme == Name ? Theme.Accent.opacity(0.15) : Theme.Background, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                }
            }.padding(.top, 9)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(13).background(Theme.Background, in: RoundedRectangle(cornerRadius: 9))
    }

    private func ThemeSwatch(_ Name: String) -> Color {
        switch Name {
        case "light": .white
        case "blue": .blue
        case "emerald", "forest": .green
        case "rose", "cyberpunk": .pink
        case "midnight": .indigo
        case "ocean": .cyan
        case "sunset", "amber": .orange
        default: .purple
        }
    }

    private func ThemeTitle(_ Name: String) -> String {
        switch Name {
        case "light": "Arctic Sky"
        case "blue": "Ocean Blue"
        case "purple": "Ascendara Purple"
        case "amber": "Amber Sand"
        case "dark": "Dark Blue"
        case "ocean": "Deep Ocean"
        default: Name.capitalized
        }
    }

    private func PreferenceToggle(_ Title: String, _ Detail: String, Value: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Title).font(.system(size: 13, weight: .semibold))
                Text(Detail).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
            }
            Spacer(minLength: 0)
            Toggle(Title, isOn: Value).labelsHidden().tint(Theme.Accent)
        }
    }

    private func RuntimeRow(_ Title: String, Detail: String, Available: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: Available ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(Available ? Color.green : Theme.SecondaryText)
            VStack(alignment: .leading, spacing: 4) {
                Text(Title).font(.system(size: 13, weight: .semibold))
                Text(Detail).font(.system(size: 11)).foregroundStyle(Theme.SecondaryText).lineLimit(2)
            }
            Spacer(minLength: 0)
        }.padding(12).background(Theme.Muted.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func BranchRow(_ Title: String, _ Detail: String, _ Tint: Color, Active: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(Tint).frame(width: 10, height: 10).padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(Title).font(.system(size: 13, weight: .semibold))
                    if Active {
                        Text("Active").font(.system(size: 10, weight: .semibold)).foregroundStyle(.green)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }
                Text(Detail).font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 8).opacity(Active ? 1 : 0.72)
    }

    private func IndexMetric(_ Name: String, _ Value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(Name).font(.system(size: 9, weight: .bold)).tracking(0.9).foregroundStyle(Theme.SecondaryText)
            Text(Value).font(.system(size: 15, weight: .semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12).background(Theme.Muted.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var LastIndexRefresh: String {
        guard let CacheTime = CatalogCacheDate else { return "Not yet" }
        return CacheTime.formatted(date: .abbreviated, time: .shortened)
    }

    private var IndexAge: String {
        guard let Raw = Store.CatalogMetadata.GetDate ?? Store.CatalogMetadata.UpdatedAt, !Raw.isEmpty else { return "Unknown" }
        return String(Raw.prefix(10))
    }

    private var CatalogCacheDate: Date? {
        let Folder = AppPaths.Support.appendingPathComponent("CatalogCache")
        guard let Files = try? FileManager.default.contentsOfDirectory(at: Folder, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        return Files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.compactMap { $0 }.max()
    }

    private func SetLoginItem(_ Enabled: Bool) {
        do {
            if Enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            OpensAtLogin = SMAppService.mainApp.status == .enabled
            LoginItemError = nil
        } catch {
            OpensAtLogin = SMAppService.mainApp.status == .enabled
            LoginItemError = error.localizedDescription
        }
    }

    private func AddBlockedId() {
        let Id = NewBlockedId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !Id.isEmpty, !Store.Settings.BlacklistedGameIds.contains(Id) else { return }
        Store.Settings.BlacklistedGameIds.append(Id)
        NewBlockedId = ""
        Store.SaveSettings()
        Store.RefreshCatalog()
    }

    private func RemoveBlockedId(_ Id: String) {
        Store.Settings.BlacklistedGameIds.removeAll { $0 == Id }
        Store.SaveSettings()
        Store.RefreshCatalog()
    }

    private func TestQBit() {
        CheckingQBit = true
        QBitStatus = nil
        Task {
            do { _ = try await TorrentService.List(Settings: Store.Settings); QBitStatus = "Connected" }
            catch { QBitStatus = error.localizedDescription }
            CheckingQBit = false
        }
    }

    private func ChooseBackupDirectory() {
        let Panel = NSOpenPanel()
        Panel.canChooseDirectories = true
        Panel.canChooseFiles = false
        Panel.canCreateDirectories = true
        if Panel.runModal() == .OK, let URL = Panel.url {
            Store.Settings.BackupDirectory = URL.path
            Store.SaveSettings()
        }
    }
}

private struct PreferenceCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.Card, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.Border.opacity(0.25)))
    }
}
