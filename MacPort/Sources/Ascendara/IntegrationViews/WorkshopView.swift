import AppKit
import SwiftUI

struct WorkshopView: View {
    @EnvironmentObject var Store: AppStore
    @State private var Link = ""
    @State private var Item: WorkshopItem?
    @State private var IsBusy = false
    @State private var Log = ""
    @State private var InstalledDirectory: URL?

    var body: some View {
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
        }.MotionAnimation(IsBusy).MotionAnimation(InstalledDirectory)
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
