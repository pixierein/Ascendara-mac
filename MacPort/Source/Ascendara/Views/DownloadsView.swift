import Combine
import SwiftUI

private struct SpeedSample {
    let Time: Date
    let BytesPerSecond: Double
}

struct DownloadsView: View {
    private static let SpeedTimer = Timer.publish(every: 0.5, tolerance: 0.1, on: .main, in: .common).autoconnect()
    @EnvironmentObject private var Store: AppStore
    @Environment(\.scenePhase) private var ScenePhase
    @AppStorage("DownloadNoticeDismissed") private var NoticeDismissed = false
    @State private var Filter = "All"
    @State private var SpeedSamples: [SpeedSample] = []
    @State private var PeakSpeed = 0.0
    @State private var SampledSpeed = 0.0
    @State private var LastSampleAt: Date?
    @State private var LastReceivedBytes: [UUID: Int64] = [:]
    @State private var LastProgressAt: [UUID: Date] = [:]
    @State private var LastDownloadRates: [UUID: Double] = [:]

    private var IsTransferring: Bool {
        Store.Downloads.contains { $0.State == .Downloading } ||
        Store.TorrentJobs.contains { $0.State == "Downloading" }
    }

    private var CurrentSpeed: Double {
        if LastSampleAt != nil { return SampledSpeed }
        return Store.Downloads.filter { $0.State == .Downloading }.reduce(0) { $0 + max(0, $1.BytesPerSecond) }
            + Double(Store.TorrentJobs.reduce(Int64(0)) { $0 + max(0, $1.Speed) })
    }

    private func SampleSpeed() {
        let Now = Date()
        let Active = Store.Downloads.filter { $0.State == .Downloading }
        let ActiveIds = Set(Active.map(\.Id))
        var DownloadSpeed = 0.0
        for Item in Active {
            let Reported = max(0, Item.BytesPerSecond)
            let PreviousBytes = LastReceivedBytes[Item.Id] ?? Item.ReceivedBytes
            let Rate: Double
            if Item.ReceivedBytes > PreviousBytes {
                let Elapsed = Now.timeIntervalSince(LastProgressAt[Item.Id] ?? LastSampleAt ?? Now)
                let Measured = Double(Item.ReceivedBytes - PreviousBytes) / max(0.25, Elapsed)
                Rate = max(Reported, Measured)
                LastProgressAt[Item.Id] = Now
            } else if Reported > 0 {
                Rate = Reported
            } else if let ProgressAt = LastProgressAt[Item.Id], Now.timeIntervalSince(ProgressAt) < 1.5 {
                // Worker status can briefly report zero between two progress writes.
                Rate = LastDownloadRates[Item.Id] ?? 0
            } else {
                Rate = 0
            }
            DownloadSpeed += Rate
            LastDownloadRates[Item.Id] = Rate
        }
        LastReceivedBytes = Dictionary(uniqueKeysWithValues: Active.map { ($0.Id, $0.ReceivedBytes) })
        LastProgressAt = LastProgressAt.filter { Id, _ in ActiveIds.contains(Id) }
        LastDownloadRates = LastDownloadRates.filter { Id, _ in ActiveIds.contains(Id) }
        LastSampleAt = Now
        let TorrentSpeed = Double(Store.TorrentJobs.reduce(Int64(0)) { $0 + max(0, $1.Speed) })
        let Target = DownloadSpeed + TorrentSpeed
        let Blend = Target > SampledSpeed ? 0.45 : 0.3
        SampledSpeed += (Target - SampledSpeed) * Blend
        if SampledSpeed < 50 { SampledSpeed = 0 }
        if IsTransferring || SampledSpeed > 0 || SpeedSamples.contains(where: { $0.BytesPerSecond > 0 }) {
            SpeedSamples.append(SpeedSample(Time: Now, BytesPerSecond: SampledSpeed))
        }
        SpeedSamples.removeAll { Now.timeIntervalSince($0.Time) > 61 }
        if !IsTransferring && SampledSpeed == 0 && !SpeedSamples.contains(where: { $0.BytesPerSecond > 0 }) {
            SpeedSamples.removeAll()
            LastSampleAt = nil
            PeakSpeed = 0
        }
        PeakSpeed = max(PeakSpeed, SampledSpeed)
    }

    private var Filtered: [DownloadItem] {
        Store.Downloads.filter { Item in
            Filter == "All" || (Filter == "Active" && Item.IsActive) ||
            (Filter == "Completed" && [.Completed, .Extracted].contains(Item.State)) ||
            (Filter == "Paused" && [.Paused, .Failed].contains(Item.State))
        }.sorted { $0.CreatedAt > $1.CreatedAt }
    }
    private var FilteredTorrents: [TorrentJobStatus] {
        Store.TorrentJobs.filter { Job in
            Filter == "All" || (Filter == "Active" && !Job.IsTerminal && Job.State != "Paused") ||
            (Filter == "Completed" && ["Completed", "ManualInstallRequired"].contains(Job.State)) ||
            (Filter == "Paused" && ["Paused", "Failed"].contains(Job.State))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !NoticeDismissed { DownloadNotice }
                SpeedPanel
                HStack {
                    PageHeading(Title: "Downloads", Subtitle: "Manage your transfers and queue.")
                    Spacer()
                    Button { Store.ChooseDownloadDirectory() } label: {
                        Label("Download folder", systemImage: "folder")
                    }.buttonStyle(SecondaryButtonStyle())
                }
                HStack {
                    Picker("Downloads", selection: $Filter) {
                        ForEach(["All", "Active", "Paused", "Completed"], id: \.self) { Value in Text(Value).tag(Value) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 380)
                    Spacer()
                    Text("\(Filtered.count + FilteredTorrents.count) of \(Store.Downloads.count + Store.TorrentJobs.count) downloads")
                        .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                }
                if Filtered.isEmpty && FilteredTorrents.isEmpty {
                    EmptyPanel(Symbol: "arrow.down.circle", Title: Filter == "All" ? "Nothing downloading yet" : "No \(Filter.lowercased()) downloads", Message: "Choose a game and a download provider to add it to the queue.", ActionTitle: "Browse games") {
                        Store.CurrentRoute = .Search
                    }
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(Filtered) { Item in DownloadRow(Item: Item) }
                        ForEach(FilteredTorrents) { Job in TorrentJobRow(Job: Job) }
                    }
                }
            }
            .padding(30).padding(.bottom, 110)
            .frame(maxWidth: 1400).frame(maxWidth: .infinity)
        }
        .background(Theme.Background)
        .onReceive(Self.SpeedTimer) { _ in
            guard ScenePhase == .active else { return }
            if !IsTransferring && SampledSpeed == 0 && SpeedSamples.isEmpty { return }
            if !IsTransferring && SampledSpeed == 0,
               let LastSampleAt, Date().timeIntervalSince(LastSampleAt) < 2 { return }
            SampleSpeed()
        }
        .MotionAnimation(Filter)
    }

    private var DownloadNotice: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "info.circle").font(.system(size: 18)).foregroundStyle(Theme.Accent)
            VStack(alignment: .leading, spacing: 5) {
                Text("Downloading on Ascendara").font(.system(size: 14, weight: .semibold))
                Text("Downloads continue in the background after you close Ascendara. You can pause or stop a transfer from its card at any time.")
                    .font(.system(size: 13)).foregroundStyle(Theme.SecondaryText)
            }
            Spacer(minLength: 12)
            Button("I understand") { NoticeDismissed = true }
                .buttonStyle(.plain).foregroundStyle(Theme.Accent)
        }
        .padding(20)
        .background(Theme.Accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Accent.opacity(0.35)))
    }

    private var SpeedPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CURRENT TOTAL SPEED").font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(Theme.SecondaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(SpeedValue(CurrentSpeed)).font(.system(size: 46, weight: .bold)).monospacedDigit()
                        Text(SpeedUnit(CurrentSpeed)).font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.SecondaryText)
                    }
                }
                Spacer()
                Metric("Peak", Value: "\(SpeedValue(PeakSpeed)) \(SpeedUnit(PeakSpeed))")
                Metric("Active", Value: "\(Store.Downloads.filter { $0.State == .Downloading }.count + Store.TorrentJobs.filter { $0.State == "Downloading" }.count)")
                Metric("Queued", Value: "\(Store.Downloads.filter { $0.State == .Queued }.count + Store.TorrentJobs.filter { ["Connecting", "Registering", "Waiting"].contains($0.State) }.count)")
            }
            SpeedChart(Samples: SpeedSamples,
                       IsLive: IsTransferring || SpeedSamples.contains(where: { $0.BytesPerSecond > 0 }))
                .frame(height: 170)
        }
        .padding(24)
        .background(Theme.Card, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.Border.opacity(0.55)))
    }

    private func Metric(_ Title: String, Value: String) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(Title).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
            Text(Value).font(.system(size: 16, weight: .semibold)).monospacedDigit()
        }.frame(minWidth: 75, alignment: .trailing)
    }

    private func SpeedValue(_ BytesPerSecond: Double) -> String {
        String(format: "%.1f", max(0, BytesPerSecond) / (BytesPerSecond >= 1_000_000 ? 1_000_000 : 1_000))
    }

    private func SpeedUnit(_ BytesPerSecond: Double) -> String {
        BytesPerSecond >= 1_000_000 ? "MB/s" : "KB/s"
    }
}

private struct SpeedChart: View {
    private static let Schedule = PeriodicTimelineSchedule(from: .now, by: 1.0 / 30.0)
    @Environment(\.MotionEnabled) private var MotionEnabled
    @Environment(\.scenePhase) private var ScenePhase
    let Samples: [SpeedSample]
    let IsLive: Bool

    @ViewBuilder
    var body: some View {
        if IsLive && MotionEnabled && ScenePhase == .active {
            TimelineView(Self.Schedule) { Timeline in
                Plot(at: Timeline.date)
            }
        } else {
            Plot(at: Date())
        }
    }

    private func Plot(at Now: Date) -> some View {
        Canvas(rendersAsynchronously: true) { Context, Size in
            let Ceiling = max(1_000, (Samples.map(\.BytesPerSecond).max() ?? 0) * 1.25)
            let Plot = CGRect(x: 58, y: 8, width: max(1, Size.width - 70), height: max(1, Size.height - 22))
            let Values = Points(in: Plot, ceiling: Ceiling, at: Now)
            for Index in 0..<3 {
                let Y = Plot.minY + Plot.height * CGFloat(Index) / 2
                var Grid = Path()
                Grid.move(to: CGPoint(x: Plot.minX, y: Y))
                Grid.addLine(to: CGPoint(x: Plot.maxX, y: Y))
                Context.stroke(Grid, with: .color(Theme.Border.opacity(0.45)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
                let Label = Context.resolve(Text(AxisLabel(Ceiling * Double(2 - Index) / 2))
                    .font(.system(size: 10)).foregroundColor(Theme.SecondaryText))
                Context.draw(Label, at: CGPoint(x: 26, y: Y))
            }
            guard let First = Values.first, let Last = Values.last else { return }
            var Area = Path()
            Area.move(to: CGPoint(x: First.x, y: Plot.maxY))
            Area.addLines(Values)
            Area.addLine(to: CGPoint(x: Last.x, y: Plot.maxY))
            Area.closeSubpath()
            Context.fill(Area, with: .linearGradient(
                Gradient(colors: [Theme.Accent.opacity(0.42), Theme.Accent.opacity(0.02)]),
                startPoint: CGPoint(x: Plot.midX, y: Plot.minY),
                endPoint: CGPoint(x: Plot.midX, y: Plot.maxY)))
            var Line = Path()
            Line.move(to: First)
            for Point in Values.dropFirst() { Line.addLine(to: Point) }
            Context.stroke(Line, with: .color(Theme.Accent),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            let Marker = CGRect(x: Last.x - 5.5, y: Last.y - 5.5, width: 11, height: 11)
            Context.fill(Path(ellipseIn: Marker), with: .color(Theme.Card))
            Context.stroke(Path(ellipseIn: Marker), with: .color(Theme.Accent), lineWidth: 3)
        }.accessibilityLabel("Download speed history")
    }

    private func Points(in Plot: CGRect, ceiling: Double, at Now: Date) -> [CGPoint] {
        let WindowStart = Now.addingTimeInterval(-60)
        var Result = [CGPoint(x: Plot.minX, y: Plot.maxY)]
        for Sample in Samples where Sample.Time >= WindowStart && Sample.Time <= Now {
            let Age = Now.timeIntervalSince(Sample.Time)
            Result.append(CGPoint(x: Plot.maxX - Plot.width * CGFloat(Age / 60),
                                  y: Plot.maxY - Plot.height * CGFloat(min(1, max(0, Sample.BytesPerSecond / ceiling)))))
        }
        Result.append(CGPoint(x: Plot.maxX, y: Result.last?.y ?? Plot.maxY))
        return Result
    }

    private func AxisLabel(_ Speed: Double) -> String {
        if Speed < 10_000 { return String(format: "%.1f KB/s", Speed / 1_000) }
        if Speed < 1_000_000 { return String(format: "%.0f KB/s", Speed / 1_000) }
        return String(format: "%.1f MB/s", Speed / 1_000_000)
    }
}

struct DownloadRow: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.MotionEnabled) private var MotionEnabled
    let Item: DownloadItem

    private var Artwork: URL? {
        Store.Games.first { $0.Id == Item.CatalogId || $0.Name.localizedCaseInsensitiveCompare(Item.Name) == .orderedSame }?.ArtworkURL
    }

    private var StatusColor: Color {
        switch Item.State {
        case .Failed: .red
        case .Completed, .Extracted: .green
        case .Paused, .Queued: .orange
        default: Theme.Accent
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Theme.Card
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                GameArtwork(URL: Artwork, Name: Item.Name, CornerRadius: 0).frame(width: 440).opacity(0.42)
            }
            LinearGradient(colors: [Theme.Card, Theme.Card.opacity(0.98), Theme.Card.opacity(0.72), Theme.Card.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Item.Name).font(.system(size: 19, weight: .semibold))
                        HStack(spacing: 8) {
                            Circle().fill(StatusColor).frame(width: 7, height: 7)
                            Text(Item.State.rawValue)
                            Text("·")
                            Text(Item.TotalBytes > 0 ? Bytes(Item.TotalBytes) : Item.FileName).lineLimit(1)
                        }.font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                    }
                    Spacer()
                    Controls
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline) {
                    if Item.TotalBytes > 0 {
                        Text("\(Int(Item.Progress * 100))").font(.system(size: 28, weight: .semibold)).monospacedDigit()
                        Text("%").font(.system(size: 13)).foregroundStyle(Theme.SecondaryText)
                    } else {
                        Text(Bytes(Item.ReceivedBytes)).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    }
                    Spacer()
                    if Item.State == .Downloading {
                        Text(Bytes(Int64(Item.BytesPerSecond)) + "/s")
                        Text(ETA).padding(.leading, 12)
                    } else if Item.State == .Paused, Item.ReceivedBytes > 0 {
                        Text("\(Bytes(Item.ReceivedBytes)) downloaded")
                    }
                }.font(.system(size: 13)).foregroundStyle(Theme.SecondaryText).monospacedDigit()
                if Item.TotalBytes > 0 {
                    ProgressView(value: Item.Progress).tint(Theme.Accent)
                        .animation(MotionEnabled ? .linear(duration: 0.45) : nil, value: Item.Progress)
                } else if Item.State == .Downloading {
                    ProgressView().progressViewStyle(.linear).tint(Theme.Accent)
                }
                if let Error = Item.ErrorMessage { Text(Error).font(.system(size: 11)).foregroundStyle(.red) }
            }.padding(23)
        }
        .frame(minHeight: 155)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Border.opacity(0.55)))
        .MotionAnimation(Item.State)
    }

    @ViewBuilder private var Controls: some View {
        HStack(spacing: 8) {
            switch Item.State {
            case .Downloading:
                IconButton(Symbol: "pause", Help: "Pause download") { Store.PauseDownload(Item) }
                FolderButton
                IconButton(Symbol: "xmark", Help: "Cancel download") { Store.CancelDownload(Item) }
            case .Queued:
                FolderButton
                IconButton(Symbol: "xmark", Help: "Cancel download") { Store.CancelDownload(Item) }
            case .Paused, .Failed:
                IconButton(Symbol: "play", Help: "Resume download") { Store.ResumeDownload(Item) }
                FolderButton
                IconButton(Symbol: "xmark", Help: "Cancel download") { Store.CancelDownload(Item) }
            case .Cancelled:
                IconButton(Symbol: "trash", Help: "Remove from downloads") { Store.RemoveDownload(Item) }
            case .Completed:
                Button("Extract") { Store.ExtractDownload(Item) }.buttonStyle(SecondaryButtonStyle())
                FolderButton
                IconButton(Symbol: "trash", Help: "Remove from downloads") { Store.RemoveDownload(Item) }
            case .Extracted:
                Button("Add to library") { Store.ImportDownload(Item) }.buttonStyle(SecondaryButtonStyle())
                FolderButton
                IconButton(Symbol: "trash", Help: "Remove from downloads") { Store.RemoveDownload(Item) }
            case .Extracting:
                ProgressView().controlSize(.small)
            }
        }
    }

    private var FolderButton: some View {
        IconButton(Symbol: "folder", Help: "Show download folder") { Store.RevealDownload(Item) }
    }

    private var ETA: String {
        let Remaining = Item.TotalBytes - Item.ReceivedBytes
        guard Remaining > 0, Item.BytesPerSecond > 0 else { return "Calculating ETA" }
        let Seconds = Int(ceil(Double(Remaining) / Item.BytesPerSecond))
        if Seconds >= 3600 { return "ETA \(Seconds / 3600)h \((Seconds % 3600) / 60)m" }
        if Seconds >= 60 { return "ETA \(Seconds / 60)m \(Seconds % 60)s" }
        return "ETA \(Seconds)s"
    }

    private func Bytes(_ Count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, Count), countStyle: .file)
    }
}

private struct TorrentJobRow: View {
    @EnvironmentObject private var Store: AppStore
    @Environment(\.MotionEnabled) private var MotionEnabled
    let Job: TorrentJobStatus

    private var Artwork: URL? {
        Store.Games.first { $0.Name.localizedCaseInsensitiveCompare(Job.GameName) == .orderedSame }?.ArtworkURL
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Theme.Card
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                GameArtwork(URL: Artwork, Name: Job.GameName, CornerRadius: 0).frame(width: 440).opacity(0.42)
            }
            LinearGradient(colors: [Theme.Card, Theme.Card.opacity(0.98), Theme.Card.opacity(0.72), Theme.Card.opacity(0.2)], startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Job.GameName).font(.system(size: 19, weight: .semibold))
                        HStack(spacing: 8) {
                            Circle().fill(Job.State == "Failed" ? .red : Job.IsTerminal ? .green : Theme.Accent).frame(width: 7, height: 7)
                            Text(Job.State == "ManualInstallRequired" ? "Installer required" : Job.State)
                            Text("·")
                            Text("Torrent")
                        }.font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                    }
                    Spacer()
                    Controls
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(Job.Progress * 100))").font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    Text("%").font(.system(size: 13)).foregroundStyle(Theme.SecondaryText)
                    Spacer()
                    if Job.State == "Downloading" {
                        Text(ByteCountFormatter.string(fromByteCount: max(0, Job.Speed), countStyle: .file) + "/s")
                        if Job.ETA > 0 { Text("ETA \(Job.ETA / 60)m \(Job.ETA % 60)s").padding(.leading, 12) }
                    }
                }.font(.system(size: 13)).foregroundStyle(Theme.SecondaryText).monospacedDigit()
                ProgressView(value: Job.Progress).tint(Theme.Accent)
                    .animation(MotionEnabled ? .linear(duration: 0.45) : nil, value: Job.Progress)
                if let Message = Job.ErrorMessage { Text(Message).font(.system(size: 11)).foregroundStyle(.red) }
                if let Installer = Job.ManualInstaller {
                    Text("Run the installer manually: \(URL(fileURLWithPath: Installer).lastPathComponent)")
                        .font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
                }
            }.padding(23)
        }
        .frame(minHeight: 155)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.Border.opacity(0.55)))
    }

    @ViewBuilder private var Controls: some View {
        HStack(spacing: 8) {
            switch Job.State {
            case "Paused":
                IconButton(Symbol: "play", Help: "Resume torrent") { Store.ControlTorrent(Job, Operation: "resume") }
                IconButton(Symbol: "folder", Help: "Show download folder") { Store.RevealTorrent(Job) }
                IconButton(Symbol: "xmark", Help: "Cancel torrent") { Store.ControlTorrent(Job, Operation: "cancel") }
            case "Completed", "ManualInstallRequired":
                Button(Job.State == "Completed" ? "Add to library" : "Open folder") {
                    if Job.State == "Completed" { Store.ImportTorrent(Job) } else { Store.RevealTorrent(Job) }
                }.buttonStyle(SecondaryButtonStyle())
                IconButton(Symbol: "folder", Help: "Show download folder") { Store.RevealTorrent(Job) }
                IconButton(Symbol: "trash", Help: "Remove torrent from history") { Store.ControlTorrent(Job, Operation: "remove") }
            case "Failed", "Cancelled":
                IconButton(Symbol: "folder", Help: "Show download folder") { Store.RevealTorrent(Job) }
                IconButton(Symbol: "trash", Help: "Remove torrent from history") { Store.ControlTorrent(Job, Operation: "remove") }
            default:
                IconButton(Symbol: "pause", Help: "Pause torrent") { Store.ControlTorrent(Job, Operation: "pause") }
                IconButton(Symbol: "folder", Help: "Show download folder") { Store.RevealTorrent(Job) }
                IconButton(Symbol: "xmark", Help: "Cancel torrent") { Store.ControlTorrent(Job, Operation: "cancel") }
            }
        }
    }
}
