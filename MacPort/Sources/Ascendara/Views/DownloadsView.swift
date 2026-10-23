import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject var Store: AppStore
    @State private var Filter = "All"
    private var Filtered: [DownloadItem] {
        Store.Downloads.filter { Item in
            Filter == "All" || (Filter == "Active" && Item.IsActive) || (Filter == "Completed" && [.Completed, .Extracted].contains(Item.State)) || (Filter == "Failed" && Item.State == .Failed)
        }.sorted { $0.CreatedAt > $1.CreatedAt }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    PageHeading(Title: "Downloads", Subtitle: "Everything on its way to your library.")
                    Button { Store.ChooseDownloadDirectory() } label: { Label("Download folder", systemImage: "folder") }.buttonStyle(SecondaryButtonStyle())
                }
                HStack(spacing: 16) {
                    StatCard(Title: "Downloading", Value: "\(Store.Downloads.filter { $0.State == .Downloading }.count)", Symbol: "arrow.down.circle")
                    StatCard(Title: "Queued", Value: "\(Store.Downloads.filter { $0.State == .Queued }.count)", Symbol: "clock")
                    StatCard(Title: "Download speed", Value: ByteCountFormatter.string(fromByteCount: Int64(Store.Downloads.reduce(0) { $0 + $1.BytesPerSecond }), countStyle: .file) + "/s", Symbol: "speedometer")
                }
                HStack {
                    Picker("Downloads", selection: $Filter) {
                        ForEach(["All", "Active", "Completed", "Failed"], id: \.self) { Value in Text(Value).tag(Value) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 380)
                    Spacer()
                    Text("\(Store.Downloads.count) downloads").font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                }
                if Filtered.isEmpty {
                    EmptyPanel(Symbol: "arrow.down.circle", Title: Filter == "All" ? "Nothing downloading yet" : "No \(Filter.lowercased()) downloads", Message: "Choose a game and a download provider to add it to the queue.", ActionTitle: "Browse games") { Store.CurrentRoute = .Search }
                } else {
                    LazyVStack(spacing: 14) { ForEach(Filtered) { Item in DownloadRow(Item: Item).MotionTransition() } }
                }
            }.padding(30).padding(.bottom, 100).frame(maxWidth: 1350).frame(maxWidth: .infinity)
        }.MotionAnimation(Filter)
            .MotionAnimation(Filtered.map(\.Id))
    }
}

struct DownloadRow: View {
    @EnvironmentObject var Store: AppStore
    let Item: DownloadItem
    private var StatusColor: Color {
        switch Item.State {
        case .Failed: return .red
        case .Completed, .Extracted: return .green
        case .Paused, .Queued: return .orange
        default: return Theme.Accent
        }
    }
    var body: some View {
        Panel(Padding: 21) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: Item.State == .Extracting ? "shippingbox" : "arrow.down.doc").font(.system(size: 24, weight: .light))
                        .foregroundStyle(StatusColor).frame(width: 52, height: 52).background(StatusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Item.Name).font(.system(size: 16, weight: .semibold))
                        Text(Item.FileName).font(.system(size: 11)).foregroundStyle(Theme.SecondaryText).lineLimit(1)
                        Text(Item.State.rawValue).font(.system(size: 11, weight: .medium)).foregroundStyle(StatusColor)
                            .contentTransition(.opacity)
                    }
                    Spacer()
                    Controls
                }
                if Item.State == .Downloading || Item.State == .Paused || Item.State == .Queued {
                    ProgressView(value: Item.Progress).tint(Theme.Accent)
                        .MotionAnimation(Item.Progress)
                    HStack {
                        Text("\(Bytes(Item.ReceivedBytes)) / \(Item.TotalBytes > 0 ? Bytes(Item.TotalBytes) : "Unknown size")")
                        Spacer()
                        if Item.State == .Downloading { Text(Bytes(Int64(Item.BytesPerSecond)) + "/s") }
                        Text("\(Int(Item.Progress * 100))%")
                            .contentTransition(.numericText()).MotionAnimation(Int(Item.Progress * 100))
                    }.font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.SecondaryText)
                }
                if Item.State == .Extracting { ProgressView("Extracting files…").font(.system(size: 11)) }
                if let Error = Item.ErrorMessage { Notice(Message: Error, Symbol: "exclamationmark.triangle") }
            }
        }.MotionAnimation(Item.State)
    }
    @ViewBuilder private var Controls: some View {
        HStack(spacing: 8) {
            switch Item.State {
            case .Downloading:
                IconButton(Symbol: "pause", Help: "Pause download") { Store.PauseDownload(Item) }
                IconButton(Symbol: "xmark", Help: "Cancel download") { Store.CancelDownload(Item) }
            case .Queued:
                IconButton(Symbol: "xmark", Help: "Cancel download") { Store.CancelDownload(Item) }
            case .Paused, .Failed:
                IconButton(Symbol: "play", Help: "Resume download") { Store.ResumeDownload(Item) }
                if Item.State == .Paused { IconButton(Symbol: "xmark", Help: "Cancel download") { Store.CancelDownload(Item) } }
            case .Cancelled: EmptyView()
            case .Completed:
                Button("Extract") { Store.ExtractDownload(Item) }.buttonStyle(SecondaryButtonStyle())
                IconButton(Symbol: "folder", Help: "Show download in Finder") { Store.RevealDownload(Item) }
            case .Extracted:
                IconButton(Symbol: "folder", Help: "Show extracted files") { Store.RevealDownload(Item) }
                Button("Add to library") { Store.ImportDownload(Item) }.buttonStyle(SecondaryButtonStyle())
            case .Extracting: EmptyView()
            }
        }
    }
    private func Bytes(_ Count: Int64) -> String { ByteCountFormatter.string(fromByteCount: Count, countStyle: .file) }
}
