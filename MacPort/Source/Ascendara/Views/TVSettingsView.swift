import AppKit
import SwiftUI

struct TVSettingsView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.TVScale) private var Scale
    @State private var Section = "Appearance"
    @State private var ShowingCompatibility = false
    @State private var SaveTask: Task<Void, Never>?
    private let Sections = [("Appearance", "paintpalette"), ("General", "slider.horizontal.3"), ("Downloads", "arrow.down.circle"), ("Compatibility", "desktopcomputer"), ("Integrations", "network"), ("Backups", "externaldrive"), ("About", "info.circle")]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34 * Scale) {
                TVPageHeading(Title: I18n.T("Preferences"), Subtitle: I18n.T("Settle in. Make Ascendara yours."))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14 * Scale) {
                        ForEach(Sections, id: \.0) { Title, Symbol in
                            Button { Section = Title } label: { Label(I18n.T(Title), systemImage: Symbol) }
                                .buttonStyle(TVButtonStyle(Selected: Section == Title))
                        }
                    }.padding(.vertical, 6 * Scale)
                }
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
                HStack(spacing: 18 * Scale) {
                    Button { Store.CurrentRoute = .Sources } label: { Label(I18n.T("External sources"), systemImage: "externaldrive.connected.to.line.below") }.buttonStyle(TVButtonStyle())
                    Button { Store.CurrentRoute = .Tools } label: { Label(I18n.T("Tools & dependencies"), systemImage: "wrench.and.screwdriver") }.buttonStyle(TVButtonStyle())
                }
            }.padding(.horizontal, 56 * Scale).padding(.vertical, 32 * Scale).padding(.bottom, 48 * Scale)
        }.MotionAnimation(Section)
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
        VStack(alignment: .leading, spacing: 24 * Scale) {
            TVPanel {
                VStack(alignment: .leading, spacing: 26 * Scale) {
                    Heading("Desktop theme", "Your desktop colors. TV mode keeps its cinematic dark appearance.")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150 * Scale), spacing: 16 * Scale)], spacing: 16 * Scale) {
                        ForEach(["purple", "light", "blue", "emerald", "rose", "amber", "dark", "midnight", "cyberpunk", "ocean", "forest", "sunset"], id: \.self) { Name in
                            Button { Store.Settings.Theme = Name } label: {
                                VStack(alignment: .leading, spacing: 14 * Scale) {
                                    RoundedRectangle(cornerRadius: 12 * Scale).fill(ThemeSwatch(Name)).frame(height: 70 * Scale)
                                    HStack(spacing: 6 * Scale) {
                                        Text(Name.capitalized).font(.system(size: 19 * Scale, weight: .medium))
                                        Spacer(minLength: 0)
                                        if Store.Settings.Theme == Name { Image(systemName: "checkmark.circle.fill").foregroundStyle(TVStyle.Accent) }
                                    }
                                }.padding(14 * Scale).foregroundStyle(TVStyle.Text)
                                    .background(TVStyle.Background, in: RoundedRectangle(cornerRadius: 16 * Scale))
                                    .overlay(RoundedRectangle(cornerRadius: 16 * Scale).stroke(Store.Settings.Theme == Name ? TVStyle.Accent : .clear, lineWidth: 2 * Scale))
                            }.buttonStyle(MotionButtonStyle()).accessibilityLabel(I18n.Interpolated("\(Name.capitalized) theme"))
                        }
                    }
                }
            }
            TVSettingToggle(Title: I18n.T("Reduce motion"), Subtitle: I18n.T("Use quieter transitions throughout Ascendara."), Value: $Store.Settings.ReduceMotion)
            TVPanel {
                VStack(alignment: .leading, spacing: 22 * Scale) {
                    Heading("Desktop navigation size", "Choose how large the desktop navigation bar feels.")
                    HStack(spacing: 24 * Scale) {
                        Slider(value: $Store.Settings.DockScale, in: 0.65...1.15, step: 0.05).tint(TVStyle.Accent)
                        Text(I18n.Interpolated("\(Int(Store.Settings.DockScale * 100))%")).font(.system(size: 25 * Scale, weight: .medium)).monospacedDigit().foregroundStyle(TVStyle.Text)
                    }
                }
            }
        }
    }
    private var General: some View {
        VStack(alignment: .leading, spacing: 24 * Scale) {
            TVPanel {
                VStack(alignment: .leading, spacing: 28 * Scale) {
                    Heading("Your profile", "A familiar name every time you settle in.")
                    TVSettingsField(Title: I18n.T("Display name"), Value: $Store.Settings.DisplayName)
                }
            }
            TVPanel {
                VStack(alignment: .leading, spacing: 24 * Scale) {
                    Heading("Start here", "Choose the page Ascendara opens first.")
                    HStack(spacing: 16 * Scale) {
                        ForEach(["Home", "Search", "Library", "Downloads"], id: \.self) { Page in
                            Button(Page) { Store.Settings.DefaultPage = Page }.buttonStyle(TVButtonStyle(Selected: Store.Settings.DefaultPage == Page))
                        }
                    }
                }
            }
            TVSettingToggle(Title: I18n.T("Show Workshop"), Subtitle: I18n.T("Keep Steam Workshop in your navigation."), Value: $Store.Settings.ShowWorkshop)
            Button(I18n.T("Show welcome setup")) { Store.ReplayWelcome() }.buttonStyle(TVButtonStyle())
        }
    }
    private var Downloads: some View {
        VStack(alignment: .leading, spacing: 24 * Scale) {
            TVPanel {
                VStack(alignment: .leading, spacing: 24 * Scale) {
                    Heading("A home for your games", "Choose where downloaded files are stored.")
                    TVSettingsField(Title: I18n.T("Download directory"), Value: $Store.Settings.DownloadDirectory)
                    Button { Store.ChooseDownloadDirectory() } label: { Label(I18n.T("Choose folder"), systemImage: "folder") }.buttonStyle(TVButtonStyle())
                }
            }
            TVPanel {
                HStack(spacing: 24 * Scale) {
                    Heading("Concurrent downloads", "How many downloads can run at the same time.")
                    Spacer(minLength: 16 * Scale)
                    Button { Store.Settings.ConcurrentDownloads = max(1, Store.Settings.ConcurrentDownloads - 1) } label: { Image(systemName: "minus") }
                        .buttonStyle(TVButtonStyle()).disabled(Store.Settings.ConcurrentDownloads <= 1).accessibilityLabel(I18n.T("Fewer concurrent downloads"))
                    Text(I18n.Interpolated("\(Store.Settings.ConcurrentDownloads)")).font(.system(size: 36 * Scale, weight: .semibold)).foregroundStyle(TVStyle.Text).frame(width: 50 * Scale)
                    Button { Store.Settings.ConcurrentDownloads = min(8, Store.Settings.ConcurrentDownloads + 1) } label: { Image(systemName: "plus") }
                        .buttonStyle(TVButtonStyle()).disabled(Store.Settings.ConcurrentDownloads >= 8).accessibilityLabel(I18n.T("More concurrent downloads"))
                }
            }
            TVSettingToggle(Title: I18n.T("Extract archives automatically"), Subtitle: I18n.T("Prepare supported game archives when downloads finish."), Value: $Store.Settings.AutoExtract)
            TVSettingToggle(Title: I18n.T("Keep this Mac awake"), Subtitle: I18n.T("Let active downloads finish without interruption."), Value: $Store.Settings.KeepAwake)
        }
    }
    private var Compatibility: some View {
        VStack(alignment: .leading, spacing: 24 * Scale) {
            TVPanel {
                VStack(alignment: .leading, spacing: 26 * Scale) {
                    Heading("Windows games", "Connect a Wine or Highball runtime, then choose each game's launch mode in Library.")
                    TVSettingsField(Title: I18n.T("Wine executable"), Value: $Store.Settings.WinePath, Placeholder: I18n.T("/opt/homebrew/bin/wine"))
                    TVSettingsField(Title: I18n.T("Highball executable"), Value: $Store.Settings.HighballPath, Placeholder: I18n.T("/path/to/highball"))
                    Button(I18n.T("Check compatibility runtimes")) { ShowingCompatibility = true }.buttonStyle(TVButtonStyle(Prominent: true))
                }
            }
            TVPanel {
                VStack(alignment: .leading, spacing: 22 * Scale) {
                    Heading("Default launch arguments", "One argument per line. Used when a game has no arguments of its own.")
                    TextEditor(text: $Store.Settings.LaunchArguments).font(.system(size: 20 * Scale, design: .monospaced))
                        .scrollContentBackground(.hidden).foregroundStyle(TVStyle.Text).frame(height: 135 * Scale)
                        .padding(16 * Scale).background(TVStyle.Background, in: RoundedRectangle(cornerRadius: 12 * Scale))
                }
            }
            TVPanel {
                VStack(alignment: .leading, spacing: 26 * Scale) {
                    Heading("Retro games", "Bring your emulator and ROM collection together.")
                    TVSettingsField(Title: I18n.T("Emulator executable"), Value: $Store.Settings.RetroEmulatorPath, Placeholder: I18n.T("/path/to/emulator"))
                    TVSettingsField(Title: I18n.T("Emulator arguments"), Value: $Store.Settings.RetroArguments, Placeholder: I18n.T("{rom}"))
                    Button(I18n.T("Open Retro")) { Store.CurrentRoute = .Retro }.buttonStyle(TVButtonStyle())
                }
            }
        }
    }
    private var Integrations: some View {
        VStack(alignment: .leading, spacing: 24 * Scale) {
            TVPanel {
                VStack(alignment: .leading, spacing: 26 * Scale) {
                    Heading("TorBox", "Connect your account to its download service.")
                    TVSettingsField(Title: I18n.T("TorBox API key"), Value: $Store.Settings.TorBoxAPIKey, Secure: true)
                    Button(I18n.T("Open TorBox downloads")) { Store.CurrentRoute = .TorBox }.buttonStyle(TVButtonStyle())
                }
            }
            TVPanel {
                VStack(alignment: .leading, spacing: 26 * Scale) {
                    Heading("qBittorrent", "Connect to a running qBittorrent Web UI.")
                    TVSettingsField(Title: I18n.T("Web UI address"), Value: $Store.Settings.QBitTorrentURL)
                    TVSettingsField(Title: I18n.T("Username"), Value: $Store.Settings.QBitTorrentUsername)
                    TVSettingsField(Title: I18n.T("Password"), Value: $Store.Settings.QBitTorrentPassword, Secure: true)
                }
            }
            TVPanel {
                VStack(alignment: .leading, spacing: 26 * Scale) {
                    Heading("Steam Workshop", "Use your installed SteamCMD for supported Workshop items.")
                    TVSettingsField(Title: I18n.T("SteamCMD executable"), Value: $Store.Settings.SteamCMDPath, Placeholder: I18n.T("/path/to/steamcmd"))
                    Button(I18n.T("Open Workshop")) { Store.CurrentRoute = .Workshop }.buttonStyle(TVButtonStyle())
                }
            }
        }
    }
    private var Backups: some View {
        TVPanel {
            VStack(alignment: .leading, spacing: 28 * Scale) {
                Heading("Keep your collection safe", "Export launch settings and library entries. Game files can be backed up from each game's options.")
                TVSettingsField(Title: I18n.T("Backup directory"), Value: $Store.Settings.BackupDirectory)
                Button { ChooseBackupDirectory() } label: { Label(I18n.T("Choose backup folder"), systemImage: "folder") }.buttonStyle(TVButtonStyle())
                HStack(spacing: 18 * Scale) {
                    Button(I18n.T("Export library")) { Store.ExportLibrary() }.buttonStyle(TVButtonStyle(Prominent: true))
                    Button(I18n.T("Import library")) { Store.ImportLibrary() }.buttonStyle(TVButtonStyle())
                }
            }
        }
    }
    private var About: some View {
        TVPanel {
            VStack(alignment: .leading, spacing: 26 * Scale) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 60 * Scale)).foregroundStyle(TVStyle.Accent)
                Heading("Ascendara for Mac", "Your games. One place. Built natively for macOS.")
                Text(I18n.T("macOS 14 or later · Native SwiftUI interface")).font(.system(size: 22 * Scale)).foregroundStyle(TVStyle.Secondary)
                Text(I18n.T("Your library, profile, preferences, and cached game index are stored on this Mac."))
                    .font(.system(size: 21 * Scale)).foregroundStyle(TVStyle.Secondary).lineSpacing(6 * Scale)
                HStack(spacing: 18 * Scale) {
                    Button(I18n.T("Ascendara website")) { Store.OpenExternal("https://ascendara.app") }.buttonStyle(TVButtonStyle(Prominent: true))
                    Button(I18n.T("Source code")) { Store.OpenExternal("https://github.com/pixierein/ascendara") }.buttonStyle(TVButtonStyle())
                }
            }
        }
    }
    private func Heading(_ Title: String, _ Subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12 * Scale) {
            Text(I18n.T(Title)).font(.system(size: 28 * Scale, weight: .semibold)).foregroundStyle(TVStyle.Text)
            Text(I18n.T(Subtitle)).font(.system(size: 20 * Scale)).foregroundStyle(TVStyle.Secondary).fixedSize(horizontal: false, vertical: true)
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
        Panel.canChooseDirectories = true
        Panel.canChooseFiles = false
        Panel.canCreateDirectories = true
        if Panel.runModal() == .OK, let URL = Panel.url { Store.Settings.BackupDirectory = URL.path }
    }
}

private struct TVSettingToggle: View {
    @Environment(\.TVScale) private var Scale
    let Title: String
    let Subtitle: String
    @Binding var Value: Bool
    var body: some View {
        Button { Value.toggle() } label: {
            HStack(spacing: 28 * Scale) {
                VStack(alignment: .leading, spacing: 12 * Scale) {
                    Text(I18n.T(Title)).font(.system(size: 25 * Scale, weight: .semibold))
                    Text(I18n.T(Subtitle)).font(.system(size: 19 * Scale)).foregroundStyle(TVStyle.Secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(Value ? "On" : "Off").font(.system(size: 21 * Scale, weight: .semibold))
                Image(systemName: Value ? "checkmark.circle.fill" : "circle").font(.system(size: 30 * Scale))
            }.padding(10 * Scale)
        }.buttonStyle(TVButtonStyle(Selected: Value)).accessibilityLabel(Title).accessibilityValue(Value ? "On" : "Off")
    }
}

private struct TVSettingsField: View {
    @Environment(\.TVScale) private var Scale
    let Title: String
    @Binding var Value: String
    var Placeholder = ""
    var Secure = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12 * Scale) {
            Text(I18n.T(Title)).font(.system(size: 20 * Scale, weight: .medium)).foregroundStyle(TVStyle.Secondary)
            Group {
                if Secure { SecureField(Placeholder.isEmpty ? Title : Placeholder, text: $Value) }
                else { TextField(Placeholder.isEmpty ? Title : Placeholder, text: $Value) }
            }.textFieldStyle(.plain).font(.system(size: 22 * Scale)).foregroundStyle(TVStyle.Text)
                .padding(18 * Scale).background(TVStyle.Background, in: RoundedRectangle(cornerRadius: 12 * Scale))
                .overlay(RoundedRectangle(cornerRadius: 12 * Scale).stroke(TVStyle.Text.opacity(0.16), lineWidth: 1))
                .accessibilityLabel(Title)
        }
    }
}
