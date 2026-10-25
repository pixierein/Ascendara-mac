import AppKit
import SwiftUI
import AscendaraCore

struct CustomizationView: View {
    @EnvironmentObject private var Store: AppStore
    @State private var Language = "en"
    @State private var EditingTheme = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeading(I18n.T("Language & Themes"), "Use Ascendara translations and create your own palette.", "paintpalette")
            Panel {
                VStack(alignment: .leading, spacing: 16) {
                    Picker(I18n.T("Language"), selection: $Language) {
                        ForEach(I18n.Languages) { Item in
                            Text(Item.NativeName + (I18n.IsInstalled(Item.Id) ? "" : " · JSON import")).tag(Item.Id)
                        }
                    }
                    Text(I18n.T("The 12 original Ascendara languages are bundled. Additional upstream languages can be enabled by importing their i18next JSON file. Missing strings use English."))
                        .font(.caption).foregroundStyle(Theme.SecondaryText)
                    HStack {
                        Button(I18n.T("Import translation…")) { ImportLanguage() }
                        Button(I18n.T("Export translation…")) {
                            let Panel = NSSavePanel(); Panel.nameFieldStringValue = Language + ".json"
                            if Panel.runModal() == .OK, let File = Panel.url {
                                do { try I18n.Export(Language, To: File) } catch { Store.Report(error) }
                            }
                        }
                    }
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 16) {
                    Text(Store.Settings.CustomTheme?.Name ?? "Custom theme").font(.headline)
                    Button(I18n.T("Edit theme…")) { EditingTheme = true }.buttonStyle(PrimaryButtonStyle())
                    if Store.Settings.CustomTheme != nil {
                        Button(I18n.T("Use saved custom theme")) { Store.Settings.Theme = "custom"; Store.SaveSettings() }
                    }
                    HStack {
                        Button(I18n.T("Import theme…")) {
                            let Panel = NSOpenPanel(); Panel.allowedContentTypes = [.json]
                            guard Panel.runModal() == .OK, let File = Panel.url else { return }
                            do {
                                let Palette = try AppPaths.Read(ThemePalette.self, From: File)
                                try Palette.Validate()
                                Store.Settings.CustomTheme = Palette; Store.Settings.Theme = "custom"; Store.SaveSettings()
                            } catch { Store.Report(error) }
                        }
                        Button(I18n.T("Export theme…")) {
                            let Panel = NSSavePanel(); Panel.nameFieldStringValue = "Ascendara-Theme.json"
                            guard Panel.runModal() == .OK, let File = Panel.url else { return }
                            do { try AppPaths.Write(Theme.Palette(), To: File) } catch { Store.Report(error) }
                        }
                    }
                }
            }
        }
        .onAppear { Language = Store.Settings.Language }
        .onChange(of: Language) { _, Code in
            guard I18n.IsInstalled(Code) else { return }
            Store.Settings.Language = Code; Store.SaveSettings()
        }
        .sheet(isPresented: $EditingTheme) { ThemeEditorView(Palette: Theme.Palette()).environmentObject(Store) }
    }

    private func ImportLanguage() {
        let Panel = NSOpenPanel(); Panel.allowedContentTypes = [.json]
        Panel.title = "Import \(Language) i18next translations"
        guard Panel.runModal() == .OK, let File = Panel.url else { return }
        do { try I18n.Import(File, Code: Language); Store.Settings.Language = Language; Store.SaveSettings() }
        catch { Store.Report(error) }
    }
}

struct ThemeEditorView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.dismiss) private var Dismiss
    @State var Palette: ThemePalette
    private let Names = ["Background", "Text", "Accent", "Muted background", "Secondary text", "Border", "Card", "Card text"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(I18n.T("Theme editor")).font(.title2.bold())
            TextField(I18n.T("Theme name"), text: $Palette.Name).textFieldStyle(.roundedBorder)
            Toggle(I18n.T("Dark appearance"), isOn: $Palette.Dark)
            ForEach(Names.indices, id: \.self) { Index in
                ColorPicker(Names[Index], selection: Binding(get: { Color(Hex: Palette.Colors[Index]) }, set: { Color in
                    if let RGB = NSColor(Color).usingColorSpace(.deviceRGB) {
                        Palette.Colors[Index] = String(format: "#%02X%02X%02X", Int((RGB.redComponent * 255).rounded()), Int((RGB.greenComponent * 255).rounded()), Int((RGB.blueComponent * 255).rounded()))
                    }
                }), supportsOpacity: false)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(I18n.T("Preview")).font(.headline).foregroundStyle(Color(Hex: Palette.Colors[1]))
                Text(I18n.T("Your library, your colors.")).foregroundStyle(Color(Hex: Palette.Colors[4]))
                Text(I18n.T("Play game")).padding(8).background(Color(Hex: Palette.Colors[2]), in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(.white)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(Hex: Palette.Colors[0]), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Button(I18n.T("Cancel")) { Dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(I18n.T("Save theme")) {
                    do {
                        try Palette.Validate()
                        Store.Settings.CustomTheme = Palette; Store.Settings.Theme = "custom"; Store.SaveSettings(); Dismiss()
                    } catch { Store.Report(error) }
                }.buttonStyle(PrimaryButtonStyle()).disabled((try? Palette.Validate()) == nil)
            }
        }.padding(26).frame(width: 480)
    }
}

private extension Color {
    init(Hex: String) {
        let Value = Int(Hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((Value >> 16) & 255) / 255, green: Double((Value >> 8) & 255) / 255, blue: Double(Value & 255) / 255)
    }
}

struct UpdatesNotificationsView: View {
    @EnvironmentObject private var Store: AppStore
    @State private var Permission = ""
    @State private var ShowingHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeading(I18n.T("Updates & Notifications"), "Check the active game index and choose which events you receive.", "bell")
            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    Text(I18n.Interpolated("Installed app: \(AppVersion.Current)"))
                    if let Version = Store.CatalogMetadata.AppVersion {
                        Text(I18n.Interpolated("App version in index: \(Version)"))
                        if VersionComparison.IsNewer(Version, than: AppVersion.Current), let Link = Store.CatalogMetadata.AppDownloadURL {
                            Button(I18n.T("Open app update")) { Store.OpenExternal(Link) }
                        }
                    } else { Text(I18n.T("The active index does not publish an app version.")).foregroundStyle(Theme.SecondaryText) }
                    Toggle(I18n.T("Check game updates when refreshing the index"), isOn: $Store.Settings.AutomaticallyCheckGameUpdates)
                    Text(I18n.T("Enable automatic installation for individual managed games in Game options. Updates retain playtime and achievements, and wait while the game is running.")).font(.caption).foregroundStyle(Theme.SecondaryText)
                    Button(I18n.T("Refresh index and check updates")) { Store.RefreshCatalog() }.disabled(Store.IsLoading)
                    Button(I18n.T("Refresh installed sizes")) { Store.MeasureLibrary() }
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(I18n.T("Download and installation notifications"), isOn: $Store.Settings.NotifyDownloads)
                    Toggle(I18n.T("Failures"), isOn: $Store.Settings.NotifyFailures)
                    Toggle(I18n.T("Updates"), isOn: $Store.Settings.NotifyUpdates)
                    Toggle(I18n.T("Achievements"), isOn: $Store.Settings.NotifyAchievements)
                    Toggle(I18n.T("macOS notifications"), isOn: $Store.Settings.SystemNotifications)
                    HStack {
                        Button(I18n.T("Allow macOS notifications")) {
                            Task {
                                do { Permission = try await Store.Notifications.RequestPermission() ? "Notifications allowed." : "Notifications are disabled in System Settings." }
                                catch { Permission = error.localizedDescription }
                            }
                        }
                        Button(I18n.T("Notification history")) { ShowingHistory = true }
                    }
                    if !Permission.isEmpty { Text(I18n.T(Permission)).font(.caption).foregroundStyle(Theme.SecondaryText) }
                }
            }
        }.sheet(isPresented: $ShowingHistory) { NotificationHistoryView(Center: Store.Notifications) }
    }
}

struct NotificationHistoryView: View {
    @ObservedObject var Center: NotificationService
    @Environment(\.dismiss) private var Dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(I18n.T("Notifications")).font(.title2.bold())
                Spacer()
                Button(I18n.T("Mark all read")) { Center.MarkRead() }
                Button(I18n.T("Clear history")) { Center.Clear() }
                Button(I18n.T("Done")) { Dismiss() }
            }
            List(Center.Items) { Item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { if !Item.Read { Circle().fill(Theme.Accent).frame(width: 6, height: 6) }; Text(I18n.T(Item.Title)).bold() }
                    Text(Item.Message)
                    Text(Item.Date.formatted()).font(.caption).foregroundStyle(Theme.SecondaryText)
                }.padding(.vertical, 6)
            }
        }.padding(24).frame(minWidth: 650, minHeight: 450)
    }
}

struct NotificationBell: View {
    @ObservedObject var Center: NotificationService
    @State private var ShowingHistory = false
    var body: some View {
        Button { ShowingHistory = true } label: {
            Image(systemName: Center.UnreadCount > 0 ? "bell.badge.fill" : "bell")
                .frame(width: 30, height: 30)
        }.buttonStyle(MotionButtonStyle()).help(I18n.T("Notifications"))
            .sheet(isPresented: $ShowingHistory) { NotificationHistoryView(Center: Center) }
    }
}

struct DownloadQueueControls: View {
    @EnvironmentObject private var Store: AppStore
    @ObservedObject var Service: DownloadService
    var body: some View {
        HStack(spacing: 12) {
            Button(Service.QueuePaused ? "Start queue" : "Pause queue") { Service.SetQueuePaused(!Service.QueuePaused) }
            Button(I18n.T("Pause all")) { Service.PauseAll() }
            Button(I18n.T("Resume all")) { Service.ResumeAll() }
            Button(I18n.T("Retry failed")) { Service.RetryFailed() }
            Button(I18n.T("Clear finished")) { do { try Service.ClearFinished() } catch { Store.Report(error) } }
            Spacer()
            if Service.QueuePaused { Text(I18n.T("Queue paused")).font(.caption).foregroundStyle(.orange) }
        }.buttonStyle(SecondaryButtonStyle())
    }
}
