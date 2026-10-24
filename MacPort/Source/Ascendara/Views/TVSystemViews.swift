import AppKit
import SwiftUI

struct TVDownloadsView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.TVScale) private var Scale
    @State private var Filter = "All"
    private var Filtered: [DownloadItem] {
        Store.Downloads.filter { Item in
            Filter == "All" || (Filter == "Active" && Item.IsActive) || (Filter == "Completed" && [.Completed, .Extracted].contains(Item.State)) || (Filter == "Failed" && Item.State == .Failed)
        }.sorted { $0.CreatedAt > $1.CreatedAt }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34 * Scale) {
                HStack(alignment: .top, spacing: 24 * Scale) {
                    TVPageHeading(Title: "Downloads", Subtitle: "Your next adventure is on its way.")
                    Spacer(minLength: 0)
                    Button { Store.ChooseDownloadDirectory() } label: { Label("Download folder", systemImage: "folder") }.buttonStyle(TVButtonStyle())
                }
                HStack(spacing: 20 * Scale) {
                    TVStatTile(Title: "Downloading", Value: "\(Store.Downloads.filter { $0.State == .Downloading }.count)", Symbol: "arrow.down.circle")
                    TVStatTile(Title: "Queued", Value: "\(Store.Downloads.filter { $0.State == .Queued }.count)", Symbol: "clock")
                    TVStatTile(Title: "Speed", Value: Bytes(Int64(Store.Downloads.reduce(0) { $0 + $1.BytesPerSecond })) + "/s", Symbol: "speedometer")
                }
                HStack(spacing: 14 * Scale) {
                    ForEach(["All", "Active", "Completed", "Failed"], id: \.self) { Value in
                        Button(Value) { Filter = Value }.buttonStyle(TVButtonStyle(Selected: Filter == Value))
                    }
                    Spacer(minLength: 0)
                    Text("\(Store.Downloads.count) downloads").font(.system(size: 19 * Scale)).foregroundStyle(TVStyle.Secondary)
                }
                if Filtered.isEmpty {
                    TVEmptyState(Symbol: "arrow.down.circle", Title: Filter == "All" ? "Nothing downloading yet" : "No \(Filter.lowercased()) downloads", Message: "Choose a game and a provider to add it to your queue.")
                    Button("Explore games") { Store.CurrentRoute = .Search }.buttonStyle(TVButtonStyle(Prominent: true))
                } else {
                    LazyVStack(spacing: 24 * Scale) {
                        ForEach(Filtered) { Item in TVDownloadRow(Item: Item).MotionTransition() }
                    }
                }
            }.padding(.horizontal, 56 * Scale).padding(.vertical, 32 * Scale).padding(.bottom, 48 * Scale)
        }.MotionAnimation(Filter).MotionAnimation(Filtered.map(\.Id))
    }
    private func Bytes(_ Count: Int64) -> String { ByteCountFormatter.string(fromByteCount: Count, countStyle: .file) }
}

private struct TVDownloadRow: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.TVScale) private var Scale
    let Item: DownloadItem
    private var Artwork: URL? { Store.Games.first { $0.Id == Item.CatalogId }?.ArtworkURL }
    private var StatusColor: Color {
        switch Item.State {
        case .Failed: return .red
        case .Completed, .Extracted: return .green
        case .Paused, .Queued: return .orange
        default: return TVStyle.Accent
        }
    }
    var body: some View {
        TVPanel {
            VStack(alignment: .leading, spacing: 24 * Scale) {
                HStack(alignment: .center, spacing: 24 * Scale) {
                    if let Artwork {
                        GameArtwork(URL: Artwork, Name: Item.Name, CornerRadius: 12 * Scale).frame(width: 164 * Scale, height: 92 * Scale)
                    } else {
                        Image(systemName: Item.State == .Extracting ? "shippingbox" : "arrow.down.doc")
                            .font(.system(size: 42 * Scale, weight: .light)).foregroundStyle(StatusColor)
                            .frame(width: 92 * Scale, height: 92 * Scale)
                            .background(StatusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 20 * Scale))
                    }
                    VStack(alignment: .leading, spacing: 10 * Scale) {
                        Text(Item.Name).font(.system(size: 28 * Scale, weight: .semibold)).foregroundStyle(TVStyle.Text).lineLimit(2)
                        Text(Item.FileName).font(.system(size: 18 * Scale)).foregroundStyle(TVStyle.Secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(Item.State.rawValue).font(.system(size: 20 * Scale, weight: .semibold)).foregroundStyle(StatusColor)
                        .padding(.horizontal, 18 * Scale).padding(.vertical, 10 * Scale)
                        .background(StatusColor.opacity(0.12), in: Capsule())
                }
                if [.Downloading, .Paused, .Queued].contains(Item.State) {
                    VStack(spacing: 14 * Scale) {
                        GeometryReader { Geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(TVStyle.Text.opacity(0.12))
                                Capsule().fill(TVStyle.Accent).frame(width: Geometry.size.width * CGFloat(Item.Progress))
                            }
                        }.frame(height: 7 * Scale).MotionAnimation(Item.Progress)
                        HStack {
                            Text("\(Bytes(Item.ReceivedBytes)) of \(Item.TotalBytes > 0 ? Bytes(Item.TotalBytes) : "unknown size")")
                            Spacer()
                            if Item.State == .Downloading { Text(Bytes(Int64(Item.BytesPerSecond)) + "/s") }
                            Text("\(Int(Item.Progress * 100))%").frame(minWidth: 70 * Scale, alignment: .trailing)
                        }.font(.system(size: 18 * Scale)).monospacedDigit().foregroundStyle(TVStyle.Secondary)
                    }
                }
                if Item.State == .Extracting {
                    HStack(spacing: 16 * Scale) {
                        ProgressView().controlSize(.large)
                        Text("Extracting game files…").font(.system(size: 20 * Scale)).foregroundStyle(TVStyle.Secondary)
                    }
                }
                if let Error = Item.ErrorMessage {
                    Label(Error, systemImage: "exclamationmark.triangle").font(.system(size: 18 * Scale)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Controls
            }
        }.MotionAnimation(Item.State)
    }
    @ViewBuilder private var Controls: some View {
        HStack(spacing: 16 * Scale) {
            switch Item.State {
            case .Downloading:
                Button { Store.PauseDownload(Item) } label: { Label("Pause", systemImage: "pause.fill") }.buttonStyle(TVButtonStyle())
                Button("Cancel download") { Store.CancelDownload(Item) }.buttonStyle(TVButtonStyle())
            case .Queued:
                Button("Cancel download") { Store.CancelDownload(Item) }.buttonStyle(TVButtonStyle())
            case .Paused, .Failed:
                Button { Store.ResumeDownload(Item) } label: { Label(Item.State == .Failed ? "Retry" : "Resume", systemImage: "play.fill") }.buttonStyle(TVButtonStyle(Prominent: true))
                if Item.State == .Paused { Button("Cancel download") { Store.CancelDownload(Item) }.buttonStyle(TVButtonStyle()) }
            case .Completed:
                Button("Extract game files") { Store.ExtractDownload(Item) }.buttonStyle(TVButtonStyle(Prominent: true))
                Button { Store.RevealDownload(Item) } label: { Label("Show files", systemImage: "folder") }.buttonStyle(TVButtonStyle())
            case .Extracted:
                Button("Add to library") { Store.ImportDownload(Item) }.buttonStyle(TVButtonStyle(Prominent: true))
                Button { Store.RevealDownload(Item) } label: { Label("Show files", systemImage: "folder") }.buttonStyle(TVButtonStyle())
            case .Cancelled, .Extracting:
                EmptyView()
            }
        }
    }
    private func Bytes(_ Count: Int64) -> String { ByteCountFormatter.string(fromByteCount: Count, countStyle: .file) }
}

struct TVProfileView: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.TVScale) private var Scale
    @AppStorage("NativeProfileNotes") private var Notes = ""
    @State private var EditingName = false
    private var Played: [LibraryGame] { Store.Library.filter { $0.LastPlayedAt != nil }.sorted { $0.PlayTimeSeconds > $1.PlayTimeSeconds } }
    private var TotalTime: Double { Store.Library.reduce(0) { $0 + $1.PlayTimeSeconds } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40 * Scale) {
                HStack(spacing: 30 * Scale) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 108 * Scale, weight: .ultraLight)).foregroundStyle(TVStyle.Accent)
                    VStack(alignment: .leading, spacing: 12 * Scale) {
                        Text("YOUR PROFILE").font(.system(size: 17 * Scale, weight: .bold)).tracking(2 * Scale).foregroundStyle(TVStyle.Secondary)
                        if EditingName {
                            TextField("Display name", text: $Store.Settings.DisplayName).textFieldStyle(.plain)
                                .font(.system(size: 42 * Scale, weight: .bold)).foregroundStyle(TVStyle.Text)
                                .padding(12 * Scale).background(TVStyle.Panel, in: RoundedRectangle(cornerRadius: 12 * Scale))
                                .onSubmit { SaveName() }
                        } else {
                            Text(Store.Settings.DisplayName).font(.system(size: 48 * Scale, weight: .bold)).foregroundStyle(TVStyle.Text).lineLimit(2)
                        }
                        Text("Your space. Your games.").font(.system(size: 22 * Scale)).foregroundStyle(TVStyle.Secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button(EditingName ? "Save name" : "Edit profile") {
                        if EditingName { SaveName() } else { EditingName = true }
                    }.buttonStyle(TVButtonStyle())
                }.padding(.vertical, 16 * Scale)
                HStack(spacing: 18 * Scale) {
                    TVStatTile(Title: "In your library", Value: "\(Store.Library.count)", Symbol: "books.vertical")
                    TVStatTile(Title: "Games played", Value: "\(Played.count)", Symbol: "gamecontroller")
                    TVStatTile(Title: "Time played", Value: FormatPlayTime(TotalTime), Symbol: "clock")
                    TVStatTile(Title: "Favorites", Value: "\(Store.Library.filter(\.Favorite).count)", Symbol: "star")
                }
                VStack(alignment: .leading, spacing: 22 * Scale) {
                    Text("Most played").font(.system(size: 30 * Scale, weight: .semibold)).foregroundStyle(TVStyle.Text)
                    if Played.isEmpty {
                        TVEmptyState(Symbol: "gamecontroller", Title: "Your story starts here", Message: "Play a game from your library to start tracking time.")
                        Button("Open library") { Store.CurrentRoute = .Library }.buttonStyle(TVButtonStyle(Prominent: true))
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 24 * Scale) {
                                ForEach(Array(Played.prefix(8))) { Game in PlayedCard(Game) }
                            }.padding(.vertical, 8 * Scale)
                        }
                    }
                }
                TVPanel {
                    VStack(alignment: .leading, spacing: 18 * Scale) {
                        Text("Private notes").font(.system(size: 28 * Scale, weight: .semibold)).foregroundStyle(TVStyle.Text)
                        Text("Keep track of your next adventure.").font(.system(size: 20 * Scale)).foregroundStyle(TVStyle.Secondary)
                        TextEditor(text: $Notes).font(.system(size: 21 * Scale)).scrollContentBackground(.hidden)
                            .foregroundStyle(TVStyle.Text).frame(height: 160 * Scale).padding(16 * Scale)
                            .background(TVStyle.Background, in: RoundedRectangle(cornerRadius: 12 * Scale))
                    }
                }
                HStack(spacing: 30 * Scale) {
                    Label(Host.current().localizedName ?? "Mac", systemImage: "desktopcomputer")
                    Text(ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory) + " memory")
                    Text("\(ProcessInfo.processInfo.processorCount) processor cores")
                }.font(.system(size: 18 * Scale)).foregroundStyle(TVStyle.Secondary)
            }.padding(.horizontal, 56 * Scale).padding(.vertical, 32 * Scale).padding(.bottom, 48 * Scale)
        }.onDisappear { if EditingName { Store.SaveSettings() } }
    }
    private func PlayedCard(_ Game: LibraryGame) -> some View {
        let Running = Store.IsRunning(Game)
        return Button {
            if Running { Store.StopGame(Game) } else { Store.LaunchGame(Game) }
        } label: {
            VStack(alignment: .leading, spacing: 12 * Scale) {
                GameArtwork(URL: Game.ArtworkURL, Name: Game.Name, CornerRadius: 14 * Scale)
                    .frame(width: 300 * Scale, height: 169 * Scale)
                    .overlay(alignment: .bottomLeading) {
                        Label(Running ? "Stop" : "Play", systemImage: Running ? "stop.fill" : "play.fill")
                            .font(.system(size: 18 * Scale, weight: .semibold)).foregroundStyle(.white)
                            .padding(10 * Scale).background(.black.opacity(0.7), in: Capsule()).padding(14 * Scale)
                    }
                Text(Game.Name).font(.system(size: 21 * Scale, weight: .semibold)).foregroundStyle(TVStyle.Text).lineLimit(2)
                Text(!Running && !Game.IsInstalled ? "Game file missing" : FormatPlayTime(Game.PlayTimeSeconds) + " played")
                    .font(.system(size: 18 * Scale)).foregroundStyle(TVStyle.Secondary)
            }.frame(width: 300 * Scale, alignment: .leading)
        }.buttonStyle(MotionButtonStyle()).disabled(Store.BusyGameIds.contains(Game.Id) || (!Running && !Game.IsInstalled))
            .accessibilityLabel("\(Running ? "Stop" : "Play") \(Game.Name)")
    }
    private func SaveName() {
        Store.SaveSettings()
        EditingName = false
    }
}

struct TVStatTile: View {
    @Environment(\.TVScale) private var Scale
    let Title: String
    let Value: String
    let Symbol: String
    var body: some View {
        TVPanel {
            VStack(alignment: .leading, spacing: 20 * Scale) {
                HStack(spacing: 12 * Scale) {
                    Text(Title).font(.system(size: 18 * Scale)).foregroundStyle(TVStyle.Secondary)
                    Spacer(minLength: 0)
                    Image(systemName: Symbol).font(.system(size: 24 * Scale)).foregroundStyle(TVStyle.Accent)
                }
                Text(Value).font(.system(size: 36 * Scale, weight: .semibold)).foregroundStyle(TVStyle.Text).lineLimit(1).minimumScaleFactor(0.65)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
