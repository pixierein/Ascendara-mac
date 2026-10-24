import AppKit
import SwiftUI

struct WorkshopView: View {
    @EnvironmentObject var Store: AppStore
    @Environment(\.BigPictureActive) private var IsTV
    @Environment(\.TVScale) private var Scale
    @State private var Link = ""
    @State private var Item: WorkshopItem?
    @State private var IsBusy = false
    @State private var Log = ""
    @State private var InstalledDirectory: URL?

    var body: some View {
        Group {
            if IsTV { TVBody } else { DesktopBody }
        }.MotionAnimation(IsBusy).MotionAnimation(InstalledDirectory)
    }

    private var DesktopBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(Title: "Steam Workshop", Subtitle: "Look up community items and download them with SteamCMD.")
                Panel {
                    HStack(spacing: 12) {
                        TextField("Steam Workshop URL or item ID", text: $Link).textFieldStyle(.roundedBorder).onSubmit { Lookup() }
                        Button("Find item") { Lookup() }.buttonStyle(PrimaryButtonStyle()).disabled(IsBusy || Link.isEmpty)
                    }
                }
                Notice(Message: "Downloads use your installed SteamCMD for macOS. Public items that allow anonymous access are supported; items requiring ownership or sign-in must be downloaded through Steam.")
                if IsBusy { ProgressView(Log.isEmpty ? "Loading Workshop…" : "SteamCMD is downloading…").frame(maxWidth: .infinity).padding() }
                if let Item {
                    Panel {
                        HStack(alignment: .top, spacing: 24) {
                            GameArtwork(URL: Item.PreviewURL, Name: Item.Title).frame(width: 240, height: 180)
                            VStack(alignment: .leading, spacing: 14) {
                                Text(Item.Title).font(.title2.bold())
                                Text("App \(Item.AppId) · \(ByteCountFormatter.string(fromByteCount: Item.Size, countStyle: .file))")
                                    .font(.caption).foregroundStyle(Theme.SecondaryText)
                                Text(Item.Description).font(.system(size: 13)).lineLimit(12).textSelection(.enabled)
                                HStack {
                                    Button("Download item") { Download(Item) }.buttonStyle(PrimaryButtonStyle()).disabled(IsBusy)
                                    SwiftUI.Link("Open on Steam", destination: URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(Item.Id)")!)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else if !IsBusy {
                    EmptyPanel(Symbol: "shippingbox", Title: "Find a Workshop item", Message: "Paste its Steam Workshop page URL to load the item’s title, preview and download information.")
                }
                if let InstalledDirectory {
                    Panel {
                        HStack {
                            Label("Workshop item downloaded", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Button("Show files") { NSWorkspace.shared.activateFileViewerSelecting([InstalledDirectory]) }.buttonStyle(SecondaryButtonStyle())
                        }
                    }
                }
                if !Log.isEmpty {
                    DisclosureGroup("SteamCMD output") {
                        Text(Log).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                    }.padding(18).background(Theme.Card, in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(30)
        }
    }

    private var TVBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32 * Scale) {
                TVPageHeading(Title: "Workshop", Subtitle: "Discover a community creation. Make it part of your game.")
                TVPanel {
                    VStack(alignment: .leading, spacing: 20 * Scale) {
                        Text("Find a Workshop item").font(.system(size: 28 * Scale, weight: .semibold))
                        HStack(spacing: 18 * Scale) {
                            TextField("Steam Workshop URL or item ID", text: $Link)
                                .modifier(TVIntegrationFieldStyle()).onSubmit { Lookup() }
                            Button { Lookup() } label: { Label("Find item", systemImage: "magnifyingglass") }
                                .buttonStyle(TVButtonStyle(Prominent: true)).disabled(IsBusy || Link.isEmpty)
                        }
                    }
                }
                if IsBusy {
                    HStack(spacing: 20 * Scale) {
                        ProgressView().controlSize(.large)
                        Text(Log.isEmpty ? "Finding your Workshop item…" : "Downloading with SteamCMD…")
                            .font(.system(size: 24 * Scale, weight: .medium))
                    }.padding(.vertical, 24 * Scale)
                }
                if let Item { TVItem(Item) }
                else if !IsBusy {
                    TVEmptyState(Symbol: "shippingbox", Title: "Something new for your next session", Message: "Paste an item’s Steam Workshop link to see its artwork, details, and download options.")
                }
                if let InstalledDirectory {
                    TVPanel {
                        HStack(spacing: 24 * Scale) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 38 * Scale)).foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 8 * Scale) {
                                Text("Ready to use").font(.system(size: 28 * Scale, weight: .semibold))
                                Text("Your Workshop files have finished downloading.").font(.system(size: 20 * Scale)).foregroundStyle(TVStyle.Secondary)
                            }
                            Spacer()
                            Button("Show files") { NSWorkspace.shared.activateFileViewerSelecting([InstalledDirectory]) }
                                .buttonStyle(TVButtonStyle(Prominent: true))
                        }
                    }
                }
                TVPanel {
                    HStack(alignment: .top, spacing: 24 * Scale) {
                        VStack(alignment: .leading, spacing: 12 * Scale) {
                            Text("Your SteamCMD connection").font(.system(size: 26 * Scale, weight: .semibold))
                            Text("Public items with anonymous access download through SteamCMD on this Mac. Items that need a Steam account or game ownership open through Steam.")
                                .font(.system(size: 20 * Scale)).foregroundStyle(TVStyle.Secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Button("Configure SteamCMD") { Store.CurrentRoute = .Settings }.buttonStyle(TVButtonStyle())
                    }
                }
                if !Log.isEmpty {
                    TVPanel {
                        DisclosureGroup {
                            Text(Log).font(.system(size: 18 * Scale, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 20 * Scale)
                        } label: { Text("Download details").font(.system(size: 24 * Scale, weight: .medium)) }
                    }
                }
            }.padding(.horizontal, 56 * Scale).padding(.vertical, 32 * Scale)
        }
    }

    private func TVItem(_ Item: WorkshopItem) -> some View {
        TVPanel {
            HStack(alignment: .top, spacing: 34 * Scale) {
                GameArtwork(URL: Item.PreviewURL, Name: Item.Title, CornerRadius: 16 * Scale)
                    .frame(width: 360 * Scale, height: 300 * Scale)
                VStack(alignment: .leading, spacing: 20 * Scale) {
                    Text(Item.Title).font(.system(size: 36 * Scale, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                    Text("App \(Item.AppId) · \(ByteCountFormatter.string(fromByteCount: Item.Size, countStyle: .file))")
                        .font(.system(size: 21 * Scale)).foregroundStyle(TVStyle.Secondary)
                    Text(Item.Description).font(.system(size: 21 * Scale)).lineSpacing(5 * Scale).lineLimit(10).textSelection(.enabled)
                    HStack(spacing: 16 * Scale) {
                        Button { Download(Item) } label: { Label("Download", systemImage: "arrow.down.circle.fill") }
                            .buttonStyle(TVButtonStyle(Prominent: true)).disabled(IsBusy)
                        Button("Open on Steam") { Store.OpenExternal("https://steamcommunity.com/sharedfiles/filedetails/?id=\(Item.Id)") }
                            .buttonStyle(TVButtonStyle())
                    }.padding(.top, 8 * Scale)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func Lookup() {
        Task {
            IsBusy = true; Log = ""; InstalledDirectory = nil
            defer { IsBusy = false }
            do { Item = try await WorkshopService.Lookup(Link) } catch { Store.Report(error) }
        }
    }

    private func Download(_ Item: WorkshopItem) {
        Task {
            IsBusy = true; Log = "Starting SteamCMD…"; InstalledDirectory = nil
            defer { IsBusy = false }
            do {
                let Result = try await WorkshopService.Download(Item: Item, Settings: Store.Settings)
                InstalledDirectory = Result.Directory; Log = Result.Log
                Store.Notice = "\(Item.Title) downloaded."
            } catch { Log = error.localizedDescription; Store.Report(error) }
        }
    }
}
