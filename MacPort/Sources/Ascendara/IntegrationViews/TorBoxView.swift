import SwiftUI

struct TorBoxView: View {
    @EnvironmentObject var Store: AppStore
    @State private var Destination = "TorBox"
    @State private var Link = ""
    @State private var Items: [TorBoxItem] = []
    @State private var Torrents: [TorrentItem] = []
    @State private var IsBusy = false
    @State private var PendingDeletion: TorBoxItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(Title: "TorBox & torrents", Subtitle: "Manage cloud downloads and your qBittorrent queue.")
                Picker("Download service", selection: $Destination) {
                    Text("TorBox").tag("TorBox")
                    Text("qBittorrent").tag("qBittorrent")
                }.pickerStyle(.segmented).frame(width: 310)
                if Destination == "TorBox", Store.Settings.TorBoxAPIKey.isEmpty {
                    EmptyPanel(Symbol: "key", Title: "Connect TorBox", Message: "Add your TorBox API key in Preferences to see your cloud downloads.", ActionTitle: "Open Preferences", Action: { Store.Route = .Settings })
                } else {
                    Panel {
                        HStack(spacing: 12) {
                            TextField(Destination == "TorBox" ? "Paste a download URL or magnet link" : "Paste a magnet or torrent URL", text: $Link)
                                .textFieldStyle(.roundedBorder).onSubmit { Add() }
                            Button("Add download") { Add() }.buttonStyle(PrimaryButtonStyle()).disabled(IsBusy || Link.isEmpty)
                            IconButton(Symbol: "arrow.clockwise", Help: "Refresh downloads", Action: { Task { await Refresh() } }).disabled(IsBusy)
                        }
                    }
                    if IsBusy { ProgressView().frame(maxWidth: .infinity) }
                    if Destination == "TorBox" {
                        if Items.isEmpty && !IsBusy {
                            EmptyPanel(Symbol: "server.rack", Title: "No cloud downloads", Message: "Add a link above to create a download on your TorBox account.")
                        }
                        ForEach(Items) { Item in TorBoxRow(Item) }
                    } else {
                        Notice(Message: "Enable qBittorrent’s Web UI and configure its address and credentials in Preferences. Files are saved by the qBittorrent host.")
                        if Torrents.isEmpty && !IsBusy { EmptyPanel(Symbol: "network", Title: "No torrents", Message: "Add a magnet link or refresh your connected qBittorrent client.") }
                        ForEach(Torrents) { Item in TorrentRow(Item) }
                    }
                }
            }.padding(30)
        }
        .MotionAnimation(Destination)
        .MotionAnimation(IsBusy)
        .task { await Refresh() }
        .onChange(of: Destination) { _, _ in Task { await Refresh() } }
        .confirmationDialog("Delete this TorBox download?", isPresented: Binding(get: { PendingDeletion != nil }, set: { if !$0 { PendingDeletion = nil } })) {
            Button("Delete from TorBox", role: .destructive) {
                if let Item = PendingDeletion { Run { try await TorBoxService.Control(Item: Item, Operation: "delete", APIKey: Store.Settings.TorBoxAPIKey) } }
                PendingDeletion = nil
            }
        } message: { Text("This removes the selected download from your cloud account.") }
    }

    private func TorBoxRow(_ Item: TorBoxItem) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: Item.Kind == "torrents" ? "network" : "cloud").foregroundStyle(Theme.Accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Item.Name).font(.headline).lineLimit(2)
                        Text("\(Item.State.capitalized) · \(ByteCountFormatter.string(fromByteCount: Item.Size, countStyle: .file))").font(.caption).foregroundStyle(Theme.SecondaryText)
                    }
                    Spacer()
                    if Item.Ready {
                        Button("Download to Mac") {
                            Run {
                                let URL = try await TorBoxService.DirectLink(Item: Item, APIKey: Store.Settings.TorBoxAPIKey)
                                Store.StartDirectDownload(Name: Item.Name, Link: URL.absoluteString)
                            }
                        }.buttonStyle(PrimaryButtonStyle())
                    } else if Item.Kind == "torrents" {
                        Button(Item.State.lowercased().contains("paused") ? "Resume" : "Pause") {
                            Run { try await TorBoxService.Control(Item: Item, Operation: Item.State.lowercased().contains("paused") ? "resume" : "pause", APIKey: Store.Settings.TorBoxAPIKey) }
                        }.buttonStyle(SecondaryButtonStyle())
                    }
                    IconButton(Symbol: "trash", Help: "Delete cloud download", Action: { PendingDeletion = Item })
                }
                ProgressView(value: Item.Progress).tint(Theme.Accent)
            }
        }.disabled(IsBusy)
    }

    private func TorrentRow(_ Item: TorrentItem) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Item.Name).font(.headline).lineLimit(2)
                        Text("\(Item.State) · \(ByteCountFormatter.string(fromByteCount: Item.Speed, countStyle: .file))/s").font(.caption).foregroundStyle(Theme.SecondaryText)
                    }
                    Spacer()
                    Button("Resume") { Run { try await TorrentService.Control(Id: Item.Id, Operation: "start", Settings: Store.Settings) } }.buttonStyle(SecondaryButtonStyle())
                    Button("Pause") { Run { try await TorrentService.Control(Id: Item.Id, Operation: "stop", Settings: Store.Settings) } }.buttonStyle(SecondaryButtonStyle())
                    IconButton(Symbol: "trash", Help: "Remove torrent, keep downloaded files", Action: {
                        Run { try await TorrentService.Control(Id: Item.Id, Operation: "delete", Settings: Store.Settings) }
                    })
                }
                ProgressView(value: min(max(Item.Progress, 0), 1)).tint(Theme.Accent)
            }
        }.disabled(IsBusy)
    }

    private func Add() {
        guard let URL = URL(string: Link.trimmingCharacters(in: .whitespacesAndNewlines)) else { Store.Report(AppFailure.Message("Enter a valid download link.")); return }
        Run {
            if Destination == "TorBox" { try await TorBoxService.Create(Link: URL, APIKey: Store.Settings.TorBoxAPIKey) }
            else { try await TorrentService.Add(URL: URL, Settings: Store.Settings) }
            Link = ""
            Store.Notice = "Download added to \(Destination)."
        }
    }

    private func Run(_ Operation: @escaping () async throws -> Void) {
        Task {
            IsBusy = true
            do { try await Operation(); await Refresh() } catch { Store.Report(error) }
            IsBusy = false
        }
    }

    private func Refresh() async {
        if Destination == "TorBox" && Store.Settings.TorBoxAPIKey.isEmpty { return }
        IsBusy = true
        defer { IsBusy = false }
        do {
            if Destination == "TorBox" { Items = try await TorBoxService.List(APIKey: Store.Settings.TorBoxAPIKey) }
            else { Torrents = try await TorrentService.List(Settings: Store.Settings) }
        } catch { Store.Report(error) }
    }
}
