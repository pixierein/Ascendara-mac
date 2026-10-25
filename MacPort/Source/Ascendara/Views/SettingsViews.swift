import AppKit
import SwiftUI

struct SettingsHeading: View {
    let Title: String
    let Subtitle: String
    let Symbol: String
    init(_ Title: String, _ Subtitle: String, _ Symbol: String) { self.Title = Title; self.Subtitle = Subtitle; self.Symbol = Symbol }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: Symbol).font(.system(size: 18)).foregroundStyle(Theme.Accent).frame(width: 40, height: 40).background(Theme.Accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(I18n.T(Title)).font(.system(size: 17, weight: .semibold))
                Text(I18n.T(Subtitle)).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
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
            SwiftUI.Text(I18n.T(Title)).font(.system(size: 12, weight: .medium))
            TextField(Placeholder.isEmpty ? Title : Placeholder, text: $Text).textFieldStyle(.roundedBorder)
        }
    }
}

struct SourcesView: View {
    @EnvironmentObject var Store: AppStore
    @Environment(\.BigPictureActive) private var IsTV
    @Environment(\.TVScale) private var Scale
    var body: some View {
        Group {
            if IsTV { TVBody } else { DesktopBody }
        }.onChange(of: Store.Settings) { _, _ in Store.SaveSettings() }
    }

    private var TVBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30 * Scale) {
                TVPageHeading(Title: I18n.T("Game sources"), Subtitle: I18n.T("Choose where your next discovery comes from."))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300 * Scale), spacing: 24 * Scale)], spacing: 24 * Scale) {
                    TVSource("Community index", "Explore the Ascendara community catalog.", "globe", "community")
                    TVSource("Custom source", "Connect a catalog with its web address.", "link", "custom")
                    TVSource("Local index", "Bring a JSON catalog from this Mac.", "externaldrive", "local")
                }
                TVPanel {
                    VStack(alignment: .leading, spacing: 24 * Scale) {
                        if Store.Settings.CatalogSource == "custom" {
                            Text(I18n.T("Your catalog address")).font(.system(size: 28 * Scale, weight: .semibold))
                            TextField(I18n.T("https://example.com/games.json"), text: $Store.Settings.CustomCatalogURL)
                                .modifier(TVIntegrationFieldStyle())
                            Text(I18n.T("Ascendara JSON indexes and Hydra-style catalogs are supported."))
                                .font(.system(size: 21 * Scale)).foregroundStyle(TVStyle.Secondary)
                        } else if Store.Settings.CatalogSource == "local" {
                            Text(I18n.T("Your local catalog")).font(.system(size: 28 * Scale, weight: .semibold))
                            Text(Store.Settings.LocalCatalogPath.isEmpty ? "Choose a JSON index to get started." : Store.Settings.LocalCatalogPath)
                                .font(.system(size: 21 * Scale)).foregroundStyle(TVStyle.Secondary).textSelection(.enabled)
                            Button(I18n.T("Choose JSON index…")) { Store.ImportCatalog() }.buttonStyle(TVButtonStyle())
                        } else {
                            Text(I18n.T("The community catalog")).font(.system(size: 28 * Scale, weight: .semibold))
                            Text(I18n.T("Load the latest index to refresh Home, discovery, and search."))
                                .font(.system(size: 21 * Scale)).foregroundStyle(TVStyle.Secondary)
                        }
                        HStack(spacing: 24 * Scale) {
                            Button { Store.SaveSettings(); Store.RefreshCatalog() } label: { Label(I18n.T("Load selected source"), systemImage: "arrow.clockwise") }
                                .buttonStyle(TVButtonStyle(Prominent: true)).disabled(Store.IsLoading)
                            if Store.IsLoading { ProgressView().controlSize(.large) }
                            Spacer()
                            Text(I18n.Interpolated("\(Store.Games.count.formatted()) games")).font(.system(size: 24 * Scale, weight: .medium)).foregroundStyle(TVStyle.Secondary)
                        }
                    }
                }
                if let Warning = Store.CatalogWarning {
                    TVPanel {
                        Label(Warning, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 21 * Scale)).foregroundStyle(.orange)
                    }
                }
                TVPanel {
                    HStack(spacing: 28 * Scale) {
                        VStack(alignment: .leading, spacing: 12 * Scale) {
                            Text(I18n.T("Your library stays with you")).font(.system(size: 28 * Scale, weight: .semibold))
                            Text(I18n.T("Installed games, notes, and launch settings stay in your library when you change sources."))
                                .font(.system(size: 21 * Scale)).foregroundStyle(TVStyle.Secondary)
                        }
                        Spacer()
                        Button(I18n.T("Open library")) { Store.CurrentRoute = .Library }.buttonStyle(TVButtonStyle())
                    }
                }
            }.padding(.horizontal, 56 * Scale).padding(.vertical, 32 * Scale)
        }
    }

    private func TVSource(_ Title: String, _ Description: String, _ Symbol: String, _ Value: String) -> some View {
        Button { Store.Settings.CatalogSource = Value } label: {
            VStack(alignment: .leading, spacing: 20 * Scale) {
                HStack {
                    Image(systemName: Symbol).font(.system(size: 42 * Scale))
                    Spacer()
                    if Store.Settings.CatalogSource == Value { Image(systemName: "checkmark.circle.fill").font(.system(size: 26 * Scale)) }
                }
                Text(I18n.T(Title)).font(.system(size: 27 * Scale, weight: .semibold))
                Text(Description).font(.system(size: 20 * Scale)).opacity(0.8).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, minHeight: 220 * Scale, alignment: .topLeading)
        }.buttonStyle(TVButtonStyle(Selected: Store.Settings.CatalogSource == Value))
    }

    private var DesktopBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(Title: I18n.T("External sources"), Subtitle: I18n.T("Choose the index that powers your game discovery."))
                Panel {
                    VStack(alignment: .leading, spacing: 22) {
                        SettingsHeading(I18n.T("Game index"), "Switch sources or bring your own catalog.", "square.stack.3d.up")
                        Picker(I18n.T("Source"), selection: $Store.Settings.CatalogSource) {
                            Text(I18n.T("Ascendara community index")).tag("community")
                            Text(I18n.T("Custom URL")).tag("custom")
                            Text(I18n.T("Imported local index")).tag("local")
                        }.pickerStyle(.radioGroup)
                        if Store.Settings.CatalogSource == "custom" {
                            SettingsField("Catalog URL", Text: $Store.Settings.CustomCatalogURL, Placeholder: I18n.T("https://example.com/games.json"))
                            Notice(Message: I18n.T("Supports Ascendara JSON indexes and Hydra-style source catalogs."))
                        }
                        if Store.Settings.CatalogSource == "local" {
                            Text(Store.Settings.LocalCatalogPath.isEmpty ? "No local index selected" : Store.Settings.LocalCatalogPath).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText).textSelection(.enabled)
                            Button(I18n.T("Import JSON index…")) { Store.ImportCatalog() }.buttonStyle(SecondaryButtonStyle())
                        }
                        HStack {
                            Button { Store.SaveSettings(); Store.RefreshCatalog() } label: { Label(I18n.T("Load selected source"), systemImage: "arrow.clockwise") }.buttonStyle(PrimaryButtonStyle()).disabled(Store.IsLoading)
                            if Store.IsLoading { ProgressView().controlSize(.small) }
                            Spacer()
                            Text(I18n.Interpolated("\(Store.Games.count.formatted()) games indexed")).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                        }
                    }
                }
                if let Warning = Store.CatalogWarning { Notice(Message: Warning, Symbol: "exclamationmark.triangle") }
                Panel {
                    VStack(alignment: .leading, spacing: 13) {
                        Text(I18n.T("Your existing library stays with you")).font(.system(size: 16, weight: .semibold))
                        Text(I18n.T("Changing your source refreshes discovery and search. Your installed games and launch settings remain available in your library.")).font(.system(size: 13)).foregroundStyle(Theme.SecondaryText)
                        Button(I18n.T("Open library")) { Store.CurrentRoute = .Library }.buttonStyle(SecondaryButtonStyle())
                    }
                }
            }.padding(30).padding(.bottom, 100).frame(maxWidth: 1100).frame(maxWidth: .infinity)
        }
    }
}

struct ToolsView: View {
    @EnvironmentObject var Store: AppStore
    @Environment(\.BigPictureActive) private var IsTV
    @Environment(\.TVScale) private var Scale
    @State private var ShowingCompatibility = false
    var body: some View {
        Group {
            if IsTV { TVBody } else { DesktopBody }
        }.sheet(isPresented: $ShowingCompatibility) { CompatibilityView().environmentObject(Store) }
    }

    private var TVBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30 * Scale) {
                TVPageHeading(Title: I18n.T("Library tools"), Subtitle: I18n.T("Bring your games together. Get everything ready to play."))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 370 * Scale), spacing: 26 * Scale)], spacing: 26 * Scale) {
                    TVTool("Steam library", "Find installed Steam games on this Mac.", "gamecontroller", "Scan library", Store.ScanSteamLibrary)
                    TVTool("Bring your library", "Import games from an existing Ascendara installation.", "books.vertical", "Import library", Store.ImportLegacyLibrary)
                    TVTool("Compatibility", "Set up the runtime for your Windows games.", "desktopcomputer", "Configure runtimes") { ShowingCompatibility = true }
                    TVTool("Retro games", "Connect an emulator and return to your classics.", "arcade.stick.console", "Open Retro") { Store.CurrentRoute = .Retro }
                    TVTool("Cloud downloads", "Manage TorBox and your qBittorrent queue.", "server.rack", "Open downloads") { Store.CurrentRoute = .TorBox }
                    TVTool("Workshop", "Discover and download Steam community creations.", "shippingbox", "Open Workshop") { Store.CurrentRoute = .Workshop }
                    TVTool("Game sources", "Choose a community, web, or local catalog.", "globe", "Manage sources") { Store.CurrentRoute = .Sources }
                    TVTool("Library backup", "Save your library entries, notes, and launch settings.", "externaldrive", "Export library", Store.ExportLibrary)
                }
            }.padding(.horizontal, 56 * Scale).padding(.vertical, 32 * Scale)
        }
    }

    private func TVTool(_ Title: String, _ Description: String, _ Symbol: String, _ ActionTitle: String, _ Action: @escaping () -> Void) -> some View {
        Button(action: Action) {
            VStack(alignment: .leading, spacing: 20 * Scale) {
                Image(systemName: Symbol).font(.system(size: 44 * Scale)).foregroundStyle(TVStyle.Accent)
                Text(I18n.T(Title)).font(.system(size: 29 * Scale, weight: .semibold))
                Text(Description).font(.system(size: 21 * Scale)).foregroundStyle(TVStyle.Secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12 * Scale)
                HStack {
                    Text(ActionTitle).font(.system(size: 21 * Scale, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.right")
                }
            }.frame(maxWidth: .infinity, minHeight: 250 * Scale, alignment: .topLeading)
        }.buttonStyle(TVButtonStyle())
    }

    private var DesktopBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(Title: I18n.T("Tools & dependencies"), Subtitle: I18n.T("Connect your library, compatibility runtimes, and download services."))
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
        }
    }
    private func Tool(_ Title: String, _ Description: String, _ Symbol: String, _ ActionTitle: String, _ Action: @escaping () -> Void) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 15) {
                Image(systemName: Symbol).font(.system(size: 23)).foregroundStyle(Theme.Accent)
                Text(I18n.T(Title)).font(.system(size: 17, weight: .semibold))
                Text(Description).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText).frame(minHeight: 38, alignment: .topLeading)
                Button(ActionTitle, action: Action).buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}
