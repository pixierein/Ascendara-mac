import AppKit
import ImageIO
import Metal
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @EnvironmentObject private var Store: AppStore
    @AppStorage("NativeProfileNotes") private var Notes = ""
    @AppStorage("NativeProfileAvatar") private var Avatar = "😊"
    @AppStorage("NativeProfileAvatarImagePath") private var AvatarImagePath = ""
    @AppStorage("NativeProfileCreatedAt") private var CreatedAt = 0.0
    @AppStorage("NativeProfileHighestXP") private var HighestXP = 0
    @AppStorage("NativeProfileHighestPlaytime") private var HighestPlaytime = 0.0
    @AppStorage("NativeProfileHighestGamesPlayed") private var HighestGamesPlayed = 0
    @State private var EditingName = false
    @State private var NameDraft = ""
    @State private var ShowAvatarPicker = false
    @State private var EmojiCategory = "Gaming"
    @State private var JoinDate: Date?
    @State private var Achievements: [ProfileAchievement] = []
    @State private var AvatarImageValue: NSImage?

    private let EmojiCategories: [(String, String, [String])] = [
        ("Gaming", "gamecontroller", ["🎮", "🕹️", "👾", "🎲", "🎯", "⚔️", "🛡️", "🏆", "🎨", "🎭", "🔥", "💎"]),
        ("Expressions", "face.smiling", ["😊", "😎", "🤔", "😄", "😂", "🥹", "🥰", "😇", "🤩", "🤗", "🫡", "🤭", "😌", "😏"]),
        ("Tech", "cpu", ["💻", "⌨️", "🖥️", "🖱️", "📱", "⚡", "💡", "🔧", "⚙️", "💾", "📡", "🔌", "🖨️", "📺"]),
        ("Space & Magic", "sparkles", ["⭐", "✨", "💫", "☄️", "🌙", "🌍", "🪐", "🌠", "🌌", "🔮", "🎇", "🌈", "🌟"]),
        ("Audio", "music.note", ["🎵", "🎶", "🎼", "🎹", "🥁", "🎸", "🎺", "🎻", "🎧", "🔊", "📻", "🎙️", "🎚️"])
    ]

    private var Played: [LibraryGame] {
        Store.Library.filter { $0.PlayTimeSeconds >= 60 }
            .sorted { $0.PlayTimeSeconds > $1.PlayTimeSeconds }
    }
    private var History: [DownloadItem] {
        Store.Downloads.filter { !$0.IsActive && $0.State != .Paused }
            .sorted { $0.CreatedAt > $1.CreatedAt }
    }
    private var LocalPlaytime: Double { Store.Library.reduce(0) { $0 + max(0, $1.PlayTimeSeconds) } }
    private var LocalXP: Int { ProfileLevel.CalculateXP(Store.Library) }
    private var XP: Int { max(LocalXP, HighestXP) }
    private var LevelProgress: ProfileLevel { ProfileLevel(XP: XP) }
    private var GamesPlayedCount: Int { max(Store.Library.filter { $0.PlayTimeSeconds > 0 }.count, HighestGamesPlayed) }
    private var AvatarImage: NSImage? { AvatarImageValue }
    private var DisplayName: String { Store.Settings.DisplayName.isEmpty ? "Guest" : Store.Settings.DisplayName }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Hero
                HStack(alignment: .top, spacing: 22) {
                    StatsColumn.frame(width: 360)
                    VStack(alignment: .leading, spacing: 22) {
                        GamesPlayed
                        DownloadHistory
                    }.frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24).padding(.top, 34).padding(.bottom, 130)
            .frame(maxWidth: 1500).frame(maxWidth: .infinity)
        }
        .background(Theme.Background)
        .onAppear { LoadProfile(); LoadAvatarImage() }
        .onChange(of: AvatarImagePath) { _, _ in LoadAvatarImage() }
        .onChange(of: Store.Library) { _, _ in
            PreserveStats()
            Achievements = ProfileAchievement.Load(From: Store.Library)
        }
    }

    private var Hero: some View {
        HStack(spacing: 22) {
            Button { ShowAvatarPicker = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    Circle().fill(Theme.Card).frame(width: 128, height: 128)
                        .overlay {
                            if let AvatarImage {
                                Image(nsImage: AvatarImage).resizable().scaledToFill()
                                    .frame(width: 128, height: 128).clipShape(Circle())
                            } else {
                                Text(Avatar).font(.system(size: 43))
                            }
                        }
                    Image(systemName: "face.smiling").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Background).frame(width: 31, height: 31)
                        .background(Theme.Accent, in: Circle())
                        .overlay(Circle().stroke(Theme.Background, lineWidth: 2))
                }
            }.buttonStyle(.plain).help("Change profile image or emoji")
                .popover(isPresented: $ShowAvatarPicker, arrowEdge: .trailing) { AvatarPicker }

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 9) {
                    if EditingName {
                        TextField("Display name", text: $NameDraft).textFieldStyle(.roundedBorder)
                            .frame(width: 230).onSubmit(SaveName)
                        Button("Save", action: SaveName).buttonStyle(SecondaryButtonStyle())
                        Button("Cancel") { EditingName = false }.buttonStyle(.plain)
                    } else {
                        Text(DisplayName).font(.system(size: 27, weight: .bold)).foregroundStyle(Theme.Accent)
                        Button {
                            NameDraft = Store.Settings.DisplayName
                            EditingName = true
                        } label: { Image(systemName: "pencil") }
                            .buttonStyle(.plain).help("Edit profile name")
                    }
                }
                if let JoinDate {
                    Text("You started using Ascendara on \(ProfileDateFormatter.Join.string(from: JoinDate))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Background)
                        .padding(.horizontal, 15).padding(.vertical, 6)
                        .background(Theme.Accent, in: Capsule())
                }
            }
            Spacer()
        }
        .padding(32).frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        .background(LinearGradient(colors: [Theme.Accent.opacity(0.18), Theme.Accent.opacity(0.05), Theme.Background], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.Accent.opacity(0.48), lineWidth: 1))
    }

    private var AvatarPicker: some View {
        VStack(spacing: 17) {
            HStack(spacing: 12) {
                AvatarFace(Size: 58)
                VStack(alignment: .leading, spacing: 4) {
                    Text(AvatarImage == nil ? "Currently Using Emoji" : "Currently Using Custom Image")
                        .font(.system(size: 13, weight: .semibold))
                    Text(AvatarImage == nil ? "Be stylish with a custom image!" : "Why not express yourself with emojis?")
                        .font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
                }
                Spacer()
            }.padding(13).background(Theme.Card, in: RoundedRectangle(cornerRadius: 10))

            Button { UploadAvatarImage() } label: {
                Label("Upload a profile image", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(SecondaryButtonStyle())
            Text("PNG, JPG, GIF, etc., up to 50 MB").font(.system(size: 10)).foregroundStyle(Theme.SecondaryText)
            Divider()
            HStack(spacing: 6) {
                ForEach(EmojiCategories.indices, id: \.self) { Index in
                    let Category = EmojiCategories[Index]
                    Button {
                        EmojiCategory = Category.0
                    } label: {
                        Image(systemName: Category.1).frame(width: 31, height: 31)
                            .background(EmojiCategory == Category.0 ? Theme.Accent.opacity(0.24) : Color.clear, in: Circle())
                            .contentShape(Circle())
                    }.buttonStyle(.plain).help(Category.0)
                }
            }
            if let Category = EmojiCategories.first(where: { $0.0 == EmojiCategory }) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 7) {
                    ForEach(Category.2, id: \.self) { Emoji in
                        Button {
                            Avatar = Emoji
                            AvatarImagePath = ""
                            ShowAvatarPicker = false
                        } label: {
                            Text(Emoji).font(.system(size: 22))
                                .frame(width: 39, height: 39)
                                .background(Avatar == Emoji && AvatarImage == nil ? Theme.Accent.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20).frame(width: 345)
        .background(Theme.Background)
    }

    private func AvatarFace(Size: CGFloat) -> some View {
        Circle().fill(Theme.Card).frame(width: Size, height: Size)
            .overlay {
                if let AvatarImage {
                    Image(nsImage: AvatarImage).resizable().scaledToFill()
                        .frame(width: Size, height: Size).clipShape(Circle())
                } else {
                    Text(Avatar).font(.system(size: Size * 0.42))
                }
            }
    }

    private var StatsColumn: some View {
        ProfilePanel {
            VStack(alignment: .leading, spacing: 17) {
                Label("Profile Stats", systemImage: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Foreground)
                ProfileInset {
                    VStack(spacing: 12) {
                        HStack {
                            Label("Level", systemImage: "sparkles")
                            Spacer()
                            Text("\(LevelProgress.Level)").foregroundStyle(Theme.Accent)
                        }.font(.system(size: 13, weight: .semibold))
                        HStack {
                            Text("\(Int(LevelProgress.Current.rounded())) / \(Int(LevelProgress.Needed.rounded())) XP")
                            Spacer()
                            Text("\(Int(LevelProgress.Percent.rounded()))%")
                        }.font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
                        ProgressView(value: LevelProgress.Percent, total: 100).tint(Theme.Accent)
                        Divider()
                        ProfileRow("Total Playtime", LocalPlaytime >= 60 ? FormatPlayTime(LocalPlaytime) : "0h", "clock")
                        ProfileRow("Games Played", "\(GamesPlayedCount)", "trophy")
                        ProfileRow("Most Played Game", Played.first?.Name ?? "—", nil)
                        ProfileRow("XP", "\(XP)", "cpu")
                    }
                }
                ProfileInset {
                    VStack(spacing: 11) {
                        Label("Private Notes", systemImage: "face.smiling")
                            .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        ZStack(alignment: .topLeading) {
                            if Notes.isEmpty {
                                Text("Write down something to keep in mind for later...")
                                    .font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                                    .padding(.horizontal, 15).padding(.top, 14)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $Notes)
                                .font(.system(size: 12))
                                .scrollContentBackground(.hidden)
                                .frame(height: 105).padding(6)
                                .background(Theme.Background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Border))
                        }
                        Text("Only saved locally").font(.system(size: 11))
                            .foregroundStyle(Theme.SecondaryText).frame(maxWidth: .infinity)
                        Divider()
                        Label("Device", systemImage: "desktopcomputer")
                            .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        ProfileRow("Platform", "darwin", "desktopcomputer")
                        ProfileRow("OS", ProcessInfo.processInfo.operatingSystemVersionString, "externaldrive")
                        ProfileRow("CPU", CPUName, "cpu")
                        ProfileRow("RAM", ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory), "memorychip")
                        ProfileRow("GPU", MTLCreateSystemDefaultDevice()?.name ?? "Unknown", "display")
                        ProfileRow("DirectX", "Unknown", "sparkles")
                    }
                }
                ProfileInset {
                    VStack(spacing: 13) {
                        HStack {
                            Label("Achievements", systemImage: "trophy").font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text(Achievements.isEmpty ? "None" : "Top \(Achievements.count)")
                                .font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
                        }
                        HStack(alignment: .bottom, spacing: 8) {
                            AchievementColumn(TopRank: 2, RunnerRank: 4, Emphasize: false)
                            AchievementColumn(TopRank: 1, RunnerRank: 5, Emphasize: true)
                            AchievementColumn(TopRank: 3, RunnerRank: 6, Emphasize: false)
                        }
                    }
                }
            }
        }
    }

    private func AchievementColumn(TopRank: Int, RunnerRank: Int, Emphasize: Bool) -> some View {
        VStack(spacing: 0) {
            AchievementCell(Rank: TopRank, Entry: Achievements.indices.contains(TopRank - 1) ? Achievements[TopRank - 1] : nil)
                .frame(height: Emphasize ? 95 : 78)
            Divider()
            AchievementCell(Rank: RunnerRank, Entry: Achievements.indices.contains(RunnerRank - 1) ? Achievements[RunnerRank - 1] : nil)
                .frame(height: 76)
        }
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Border.opacity(0.75), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private func AchievementCell(Rank: Int, Entry: ProfileAchievement?) -> some View {
        VStack(spacing: 4) {
            Text("#\(Rank)").font(.system(size: Rank == 1 ? 12 : 11, weight: .semibold))
            Text(Entry?.Name ?? "—").font(.system(size: Rank == 1 ? 12 : 11, weight: .semibold))
                .lineLimit(1).frame(maxWidth: .infinity)
            if let Entry {
                Text("\(Entry.Unlocked)/\(Entry.Total)").font(.system(size: 10))
            }
        }
        .foregroundStyle(Theme.SecondaryText).padding(5)
    }

    private var GamesPlayed: some View {
        ProfilePanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Games You Play", systemImage: "gamecontroller")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(Played.count) Games Played").font(.system(size: 12))
                        .foregroundStyle(Theme.SecondaryText)
                }
                ScrollView {
                    if Played.isEmpty {
                        ProfileEmpty(Symbol: "gamecontroller", Title: "No Games",
                                     Message: "Hey, play some games already! Your profile is still empty!")
                            .frame(height: 330)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                            ForEach(Played) { Game in
                                HStack(spacing: 11) {
                                    GameArtwork(URL: Game.ArtworkURL, Name: Game.Name)
                                        .frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 7))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(Game.Name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Label(ProfileGameTime(Game.PlayTimeSeconds), systemImage: "clock")
                                            .font(.system(size: 10)).foregroundStyle(Theme.SecondaryText)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(10).background(Theme.Card.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Border.opacity(0.55)))
                            }
                        }
                    }
                }.frame(height: 360)
            }
        }
    }

    private var DownloadHistory: some View {
        ProfilePanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Download History", systemImage: "arrow.down.doc")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(History.count)").font(.system(size: 12)).foregroundStyle(Theme.SecondaryText)
                }
                ScrollView {
                    if History.isEmpty {
                        ProfileEmpty(Symbol: "archivebox", Title: "No download history yet",
                                     Message: "Your game download history will appear here")
                            .frame(height: 330)
                    } else {
                        LazyVStack(spacing: 11) {
                            ForEach(History) { Item in
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.down.doc").foregroundStyle(Theme.Accent)
                                        .frame(width: 40, height: 40).background(Theme.Accent.opacity(0.12), in: Circle())
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(Item.Name).font(.system(size: 13, weight: .medium))
                                        Text(Item.CreatedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 11)).foregroundStyle(Theme.SecondaryText)
                                    }
                                    Spacer()
                                    Button { Store.RemoveDownload(Item) } label: { Image(systemName: "trash") }
                                        .buttonStyle(.plain).foregroundStyle(Theme.SecondaryText)
                                        .help("Clear \(Item.Name) from history")
                                }
                                .padding(12).background(Theme.Card.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.Border.opacity(0.55)))
                            }
                        }
                    }
                }.frame(height: 360)
            }
        }
    }

    private var CPUName: String {
        var Size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &Size, nil, 0)
        if Size > 1 {
            var Buffer = [CChar](repeating: 0, count: Size)
            if sysctlbyname("machdep.cpu.brand_string", &Buffer, &Size, nil, 0) == 0 {
                return String(cString: Buffer)
            }
        }
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel"
        #endif
    }

    private func ProfileRow(_ Name: String, _ Value: String, _ Symbol: String?) -> some View {
        HStack(spacing: 8) {
            if let Symbol {
                Label(Name, systemImage: Symbol).foregroundStyle(Theme.SecondaryText)
            } else {
                Text(Name).foregroundStyle(Theme.SecondaryText)
            }
            Spacer(minLength: 5)
            Text(Value).fontWeight(.semibold).lineLimit(1)
        }.font(.system(size: 11))
    }

    private func ProfileGameTime(_ Seconds: Double) -> String {
        if Seconds < 120 { return "1 minute" }
        if Seconds < 3600 { return "\(Int(Seconds / 60)) minutes" }
        if Seconds < 7200 { return "1 hour" }
        return "\(Int(Seconds / 3600)) hours"
    }

    private func SaveName() {
        Store.Settings.DisplayName = NameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        Store.SaveSettings()
        EditingName = false
    }

    private func UploadAvatarImage() {
        let Panel = NSOpenPanel()
        Panel.allowedContentTypes = [.image]
        Panel.allowsMultipleSelection = false
        guard Panel.runModal() == .OK, let URL = Panel.url else { return }
        do {
            let Attributes = try FileManager.default.attributesOfItem(atPath: URL.path)
            guard ((Attributes[.size] as? NSNumber)?.int64Value ?? 0) <= 50 * 1024 * 1024 else {
                Store.ErrorMessage = "Choose an image smaller than 50 MB."
                return
            }
            let Destination = AppPaths.Support.appendingPathComponent("profile-avatar.\(URL.pathExtension.isEmpty ? "png" : URL.pathExtension)")
            try FileManager.default.createDirectory(at: AppPaths.Support, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: Destination.path) {
                try FileManager.default.removeItem(at: Destination)
            }
            try FileManager.default.copyItem(at: URL, to: Destination)
            AvatarImagePath = Destination.path
            LoadAvatarImage()
            ShowAvatarPicker = false
        } catch {
            Store.ErrorMessage = error.localizedDescription
        }
    }

    private func LoadAvatarImage() {
        guard !AvatarImagePath.isEmpty,
              let Source = CGImageSourceCreateWithURL(URL(fileURLWithPath: AvatarImagePath) as CFURL, nil),
              let Thumbnail = CGImageSourceCreateThumbnailAtIndex(Source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary) else {
            AvatarImageValue = nil
            return
        }
        AvatarImageValue = NSImage(cgImage: Thumbnail,
                                   size: NSSize(width: Thumbnail.width, height: Thumbnail.height))
    }

    private func PreserveStats() {
        HighestXP = max(HighestXP, LocalXP)
        HighestPlaytime = max(HighestPlaytime, LocalPlaytime)
        HighestGamesPlayed = max(HighestGamesPlayed, Store.Library.filter { $0.PlayTimeSeconds > 0 }.count)
    }

    private func LoadProfile() {
        if CreatedAt == 0 { CreatedAt = Date().timeIntervalSince1970 }
        JoinDate = ProfileDateFormatter.LegacyJoinDate() ?? Date(timeIntervalSince1970: CreatedAt)
        PreserveStats()
        Achievements = ProfileAchievement.Load(From: Store.Library)
    }
}

private enum ProfileDateFormatter {
    static let Join: DateFormatter = {
        let Formatter = DateFormatter()
        Formatter.locale = Locale(identifier: "en_US")
        Formatter.dateFormat = "MMMM d, yyyy 'at' hh:mm a"
        return Formatter
    }()
    static func LegacyJoinDate() -> Date? {
        let URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("timestamp.ascendara.json")
        guard let Data = try? Data(contentsOf: URL),
              let Object = try? JSONSerialization.jsonObject(with: Data) as? [String: Any],
              let Timestamp = Object["timestamp"] as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: Timestamp.doubleValue / 1000)
    }
}

private struct ProfileLevel {
    let Level: Int
    let Current: Double
    let Needed: Double
    var Percent: Double { Needed > 0 ? min(100, max(0, Current / Needed * 100)) : 0 }

    init(XP: Int) {
        let Total = Double(max(0, XP))
        let RawLevel = 1 + pow(Total / 50, 1 / 1.5)
        Level = min(999, max(1, Int(floor(RawLevel))))
        if Level >= 999 {
            Current = 100
            Needed = 100
        } else {
            let CurrentThreshold = Level <= 1 ? 0 : 50 * pow(Double(Level - 1), 1.5)
            let NextThreshold = 50 * pow(Double(Level), 1.5)
            Current = max(0, Total - CurrentThreshold)
            Needed = NextThreshold - CurrentThreshold
        }
    }

    static func CalculateXP(_ Games: [LibraryGame]) -> Int {
        var XP = 0
        var TotalSeconds = 0.0
        for Game in Games {
            let Seconds = max(0, Game.PlayTimeSeconds)
            let Launches = max(0, Game.LaunchCount)
            TotalSeconds += Seconds
            guard Seconds > 0 || Launches > 0 || Game.Completed else { continue }
            XP += 100
            XP += Int(floor(Seconds / 3600 * 50))
            XP += min(Launches * 10, 100)
            if Game.Completed { XP += 150 }
        }
        let Hours = TotalSeconds / 3600
        for (Threshold, Bonus) in [(25.0, 100), (50, 200), (100, 300), (200, 500), (500, 1000)] {
            if Hours >= Threshold { XP += Bonus }
        }
        return XP
    }
}

private struct ProfileAchievement {
    let Name: String
    let Unlocked: Int
    let Total: Int
    var Percentage: Double { Total > 0 ? Double(Unlocked) / Double(Total) : 0 }

    static func Load(From Games: [LibraryGame]) -> [ProfileAchievement] {
        Games.prefix(75).compactMap { Game in
            let Path = URL(fileURLWithPath: Game.DirectoryPath).appendingPathComponent("achievements.ascendara.json")
            guard let Data = try? Data(contentsOf: Path),
                  let Object = try? JSONSerialization.jsonObject(with: Data) as? [String: Any],
                  let Values = Object["achievements"] as? [[String: Any]], !Values.isEmpty else { return nil }
            let Unlocked = Values.filter {
                ($0["achieved"] as? Bool == true) || ($0["unlocked"] as? Bool == true) || ($0["isUnlocked"] as? Bool == true)
            }.count
            return ProfileAchievement(Name: Game.Name, Unlocked: Unlocked, Total: Values.count)
        }
        .sorted {
            if $0.Unlocked != $1.Unlocked { return $0.Unlocked > $1.Unlocked }
            if $0.Percentage != $1.Percentage { return $0.Percentage > $1.Percentage }
            if $0.Total != $1.Total { return $0.Total > $1.Total }
            return $0.Name.localizedStandardCompare($1.Name) == .orderedAscending
        }
        .prefix(6).map { $0 }
    }
}

private struct ProfilePanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(22).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.Background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.Border.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
    }
}

private struct ProfileInset<Content: View>: View {
    let content: Content
    init(@ViewBuilder _ content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Card.opacity(0.38), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.Border, lineWidth: 1.3))
    }
}

private struct ProfileEmpty: View {
    let Symbol: String
    let Title: String
    let Message: String
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: Symbol).font(.system(size: 32)).foregroundStyle(Theme.SecondaryText.opacity(0.7))
            Text(Title).font(.system(size: 15, weight: .semibold))
            Text(Message).font(.system(size: 12)).foregroundStyle(Theme.SecondaryText).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }
}
