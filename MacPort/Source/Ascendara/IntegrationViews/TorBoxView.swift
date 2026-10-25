import SwiftUI

struct TorBoxView: View {
    @EnvironmentObject var Store: AppStore
    @Environment(\.BigPictureActive) private var IsTV
    @Environment(\.TVScale) private var Scale
    @State private var Destination = "TorBox"
    @State private var Link = ""
    @State private var Items: [TorBoxItem] = []
    @State private var Torrents: [TorrentItem] = []
    @State private var IsBusy = false
    @State private var PendingDeletion: TorBoxItem?

    var body: some View {
        Group {
            if IsTV { TVBody } else { DesktopBody }
        }
        .MotionAnimation(Destination)
        .MotionAnimation(IsBusy)
        .task { await Refresh() }
        .onChange(of: Destination) { _, _ in Task { await Refresh() } }
        .confirmationDialog("Delete this TorBox download?", isPresented: Binding(get: { PendingDeletion != nil }, set: { if !$0 { PendingDeletion = nil } })) {
            Button(I18n.T("Delete from TorBox"), role: .destructive) {
                if let Item = PendingDeletion { Run { try await TorBoxService.Control(Item: Item, Operation: "delete", APIKey: Store.Settings.TorBoxAPIKey) } }
                PendingDeletion = nil
            }
        } message: { Text(I18n.T("This removes the selected download from your cloud account.")) }
    }

    private var DesktopBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(Title: I18n.T("TorBox & torrents"), Subtitle: I18n.T("Manage cloud downloads and your qBittorrent queue."))
                Picker(I18n.T("Download service"), selection: $Destination) {
                    Text(I18n.T("TorBox")).tag("TorBox")
                    Text(I18n.T("qBittorrent")).tag("qBittorrent")
                }.pickerStyle(.segmented).frame(width: 310)
                if Destination == "TorBox", Store.Settings.TorBoxAPIKey.isEmpty {
                    EmptyPanel(Symbol: "key", Title: I18n.T("Connect TorBox"), Message: I18n.T("Add your TorBox API key in Preferences to see your cloud downloads."), ActionTitle: I18n.T("Open Preferences"), Action: { Store.Route = .Settings })
                } else {
                    Panel {
                        HStack(spacing: 12) {
                            TextField(Destination == "TorBox" ? "Paste a download URL or magnet link" : "Paste a magnet or torrent URL", text: $Link)
                                .textFieldStyle(.roundedBorder).onSubmit { Add() }
                            Button(I18n.T("Add download")) { Add() }.buttonStyle(PrimaryButtonStyle()).disabled(IsBusy || Link.isEmpty)
                            IconButton(Symbol: "arrow.clockwise", Help: I18n.T("Refresh downloads"), Action: { Task { await Refresh() } }).disabled(IsBusy)
                        }
                    }
                    if IsBusy { ProgressView().frame(maxWidth: .infinity) }
                    if Destination == "TorBox" {
                        if Items.isEmpty && !IsBusy {
                            EmptyPanel(Symbol: "server.rack", Title: I18n.T("No cloud downloads"), Message: I18n.T("Add a link above to create a download on your TorBox account."))
                        }
                        ForEach(Items) { Item in TorBoxRow(Item) }
                    } else {
                        Notice(Message: I18n.T("Enable qBittorrent’s Web UI and configure its address and credentials in Preferences. Files are saved by the qBittorrent host."))
                        if Torrents.isEmpty && !IsBusy { EmptyPanel(Symbol: "network", Title: I18n.T("No torrents"), Message: I18n.T("Add a magnet link or refresh your connected qBittorrent client.")) }
                        ForEach(Torrents) { Item in TorrentRow(Item) }
                    }
                }
            }.padding(30)
        }
    }

    private var TVBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30 * Scale) {
                TVPageHeading(Title: I18n.T("Cloud downloads"), Subtitle: I18n.T("Your TorBox and qBittorrent queues, ready from the couch."))
                TVIntegrationTabs(Titles: ["TorBox", "qBittorrent"], Selection: $Destination)
                if Destination == "TorBox", Store.Settings.TorBoxAPIKey.isEmpty {
                    TVPanel {
                        VStack(alignment: .leading, spacing: 26 * Scale) {
                            TVEmptyState(Symbol: "server.rack", Title: I18n.T("Connect your TorBox account"), Message: I18n.T("Add your API key in Settings to see cloud downloads and save ready files to this Mac."))
                            Button(I18n.T("Open Settings")) { Store.CurrentRoute = .Settings }.buttonStyle(TVButtonStyle(Prominent: true))
                        }
                    }
                } else {
                    TVPanel {
                        VStack(alignment: .leading, spacing: 22 * Scale) {
                            Text(I18n.T("Add a download")).font(.system(size: 29 * Scale, weight: .semibold))
                            TextField(Destination == "TorBox" ? "Download URL or magnet link" : "Magnet link or torrent URL", text: $Link)
                                .modifier(TVIntegrationFieldStyle()).onSubmit { Add() }
                            HStack(spacing: 16 * Scale) {
                                Button { Add() } label: { Label(I18n.T("Add download"), systemImage: "plus") }
                                    .buttonStyle(TVButtonStyle(Prominent: true)).disabled(IsBusy || Link.isEmpty)
                                Button { Task { await Refresh() } } label: { Label(I18n.T("Refresh"), systemImage: "arrow.clockwise") }
                                    .buttonStyle(TVButtonStyle()).disabled(IsBusy)
                                if IsBusy { ProgressView().controlSize(.large) }
                            }
                        }
                    }
                    if Destination == "TorBox" {
                        if Items.isEmpty && !IsBusy {
                            TVEmptyState(Symbol: "icloud.and.arrow.down", Title: I18n.T("Your queue is clear"), Message: I18n.T("Add a link to start a cloud download on your TorBox account."))
                        }
                        ForEach(Items) { Item in TVTorBoxRow(Item) }
                    } else {
                        HStack(spacing: 22 * Scale) {
                            Text(I18n.T("qBittorrent saves files on its host. Configure its Web UI connection in Settings."))
                                .font(.system(size: 20 * Scale)).foregroundStyle(TVStyle.Secondary)
                            Spacer(minLength: 0)
                            Button(I18n.T("Connection settings")) { Store.CurrentRoute = .Settings }.buttonStyle(TVButtonStyle())
                        }
                        if Torrents.isEmpty && !IsBusy {
                            TVEmptyState(Symbol: "network", Title: I18n.T("No torrents in the queue"), Message: I18n.T("Add a magnet link or refresh your connected qBittorrent client."))
                        }
                        ForEach(Torrents) { Item in TVTorrentRow(Item) }
                    }
                }
            }.padding(.horizontal, 56 * Scale).padding(.vertical, 32 * Scale)
        }
    }

    private func TVTorBoxRow(_ Item: TorBoxItem) -> some View {
        TVPanel {
            VStack(alignment: .leading, spacing: 22 * Scale) {
                HStack(alignment: .top, spacing: 22 * Scale) {
                    Image(systemName: Item.Kind == "torrents" ? "network" : "icloud.and.arrow.down")
                        .font(.system(size: 36 * Scale)).foregroundStyle(TVStyle.Accent)
                    VStack(alignment: .leading, spacing: 10 * Scale) {
                        Text(Item.Name).font(.system(size: 29 * Scale, weight: .semibold)).lineLimit(2)
                        Text(I18n.Interpolated("\(Item.State.capitalized) · \(ByteCountFormatter.string(fromByteCount: Item.Size, countStyle: .file))"))
                            .font(.system(size: 21 * Scale)).foregroundStyle(TVStyle.Secondary)
                    }
                    Spacer(minLength: 0)
                    Text(I18n.Interpolated("\(Int(min(max(Item.Progress, 0), 1) * 100))%"))
                        .font(.system(size: 32 * Scale, weight: .medium, design: .rounded)).monospacedDigit()
                }
                ProgressView(value: min(max(Item.Progress, 0), 1)).tint(TVStyle.Accent)
                HStack(spacing: 16 * Scale) {
                    if Item.Ready {
                        Button(I18n.T("Download to this Mac")) {
                            Run {
                                let URL = try await TorBoxService.DirectLink(Item: Item, APIKey: Store.Settings.TorBoxAPIKey)
                                Store.StartDirectDownload(Name: Item.Name, Link: URL.absoluteString)
                            }
                        }.buttonStyle(TVButtonStyle(Prominent: true))
                    } else if Item.Kind == "torrents" {
                        Button(Item.State.lowercased().contains("paused") ? "Resume" : "Pause") {
                            Run { try await TorBoxService.Control(Item: Item, Operation: Item.State.lowercased().contains("paused") ? "resume" : "pause", APIKey: Store.Settings.TorBoxAPIKey) }
                        }.buttonStyle(TVButtonStyle(Prominent: true))
                    }
                    Button { PendingDeletion = Item } label: { Label(I18n.T("Remove from cloud"), systemImage: "trash") }
                        .buttonStyle(TVButtonStyle())
                }
            }
        }.disabled(IsBusy)
    }

    private func TVTorrentRow(_ Item: TorrentItem) -> some View {
        TVPanel {
            VStack(alignment: .leading, spacing: 22 * Scale) {
                Text(Item.Name).font(.system(size: 29 * Scale, weight: .semibold)).lineLimit(2)
                HStack {
                    Text(I18n.Interpolated("\(Item.State) · \(ByteCountFormatter.string(fromByteCount: Item.Speed, countStyle: .file))/s"))
                    Spacer()
                    Text(I18n.Interpolated("\(Int(min(max(Item.Progress, 0), 1) * 100))%")).monospacedDigit()
                }.font(.system(size: 21 * Scale)).foregroundStyle(TVStyle.Secondary)
                ProgressView(value: min(max(Item.Progress, 0), 1)).tint(TVStyle.Accent)
                HStack(spacing: 16 * Scale) {
                    Button(I18n.T("Resume")) { Run { try await TorrentService.Control(Id: Item.Id, Operation: "start", Settings: Store.Settings) } }
                        .buttonStyle(TVButtonStyle(Prominent: true))
                    Button(I18n.T("Pause")) { Run { try await TorrentService.Control(Id: Item.Id, Operation: "stop", Settings: Store.Settings) } }
                        .buttonStyle(TVButtonStyle())
                    Button(I18n.T("Remove from queue")) { Run { try await TorrentService.Control(Id: Item.Id, Operation: "delete", Settings: Store.Settings) } }
                        .buttonStyle(TVButtonStyle())
                }
            }
        }.disabled(IsBusy)
    }

    private func TorBoxRow(_ Item: TorBoxItem) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Image(systemName: Item.Kind == "torrents" ? "network" : "cloud").foregroundStyle(Theme.Accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Item.Name).font(.headline).lineLimit(2)
                        Text(I18n.Interpolated("\(Item.State.capitalized) · \(ByteCountFormatter.string(fromByteCount: Item.Size, countStyle: .file))")).font(.caption).foregroundStyle(Theme.SecondaryText)
                    }
                    Spacer()
                    if Item.Ready {
                        Button(I18n.T("Download to Mac")) {
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
                    IconButton(Symbol: "trash", Help: I18n.T("Delete cloud download"), Action: { PendingDeletion = Item })
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
                        Text(I18n.Interpolated("\(Item.State) · \(ByteCountFormatter.string(fromByteCount: Item.Speed, countStyle: .file))/s")).font(.caption).foregroundStyle(Theme.SecondaryText)
                    }
                    Spacer()
                    Button(I18n.T("Resume")) { Run { try await TorrentService.Control(Id: Item.Id, Operation: "start", Settings: Store.Settings) } }.buttonStyle(SecondaryButtonStyle())
                    Button(I18n.T("Pause")) { Run { try await TorrentService.Control(Id: Item.Id, Operation: "stop", Settings: Store.Settings) } }.buttonStyle(SecondaryButtonStyle())
                    IconButton(Symbol: "trash", Help: I18n.T("Remove torrent, keep downloaded files"), Action: {
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
