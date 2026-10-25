import AppKit
import SwiftUI

struct LibraryEditorView: View {
    @EnvironmentObject var Store: AppStore
    @Environment(\.dismiss) private var Dismiss
    @State var Game: LibraryGame
    @State private var Arguments = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(I18n.T("Game options")).font(.system(size: 24, weight: .bold))
                Spacer()
                IconButton(Symbol: "xmark", Help: I18n.T("Close")) { Dismiss() }
            }
            HStack(spacing: 18) {
                GameArtwork(URL: Game.ArtworkURL, Name: Game.Name).frame(width: 160, height: 100)
                VStack(alignment: .leading, spacing: 8) {
                    Text(Game.Name).font(.system(size: 19, weight: .bold))
                    Text(I18n.Interpolated("\(FormatPlayTime(Game.PlayTimeSeconds)) played")).foregroundStyle(Theme.SecondaryText)
                    if let Size = Store.Library.first(where: { $0.Id == Game.Id })?.InstalledSizeBytes {
                        Text(I18n.Interpolated("\(ByteCountFormatter.string(fromByteCount: Size, countStyle: .file)) installed")).font(.caption).foregroundStyle(Theme.SecondaryText)
                    }
                    if let LastPlayed = Game.LastPlayedAt { Text(I18n.Interpolated("Last played \(LastPlayed.formatted(date: .abbreviated, time: .shortened))")).font(.system(size: 11)).foregroundStyle(Theme.SecondaryText) }
                }
            }
            Form {
                TextField(I18n.T("Name"), text: $Game.Name)
                HStack {
                    TextField(I18n.T("Executable"), text: $Game.ExecutablePath)
                    Button(I18n.T("Choose…")) { ChooseExecutable() }
                }
                Picker(I18n.T("Launch with"), selection: $Game.LaunchMode) {
                    ForEach(LaunchMode.allCases) { Mode in Text(Mode.rawValue).tag(Mode) }
                }
                LabeledContent("Launch arguments") {
                    VStack(alignment: .leading, spacing: 5) {
                        TextEditor(text: $Arguments).font(.system(size: 11, design: .monospaced)).frame(height: 45)
                        Text(I18n.T("One argument per line; spaces are preserved.")).font(.system(size: 10)).foregroundStyle(Theme.SecondaryText)
                    }.frame(width: 360)
                }
                TextField(I18n.T("Collection"), text: $Game.Collection)
                TextField(I18n.T("Save directory"), text: Binding(get: { Game.SaveDirectory ?? "" }, set: { Game.SaveDirectory = $0.isEmpty ? nil : $0 }))
                if Game.LaunchMode == .Wine {
                    TextField(I18n.T("Wine prefix"), text: Binding(get: { Game.WinePrefixPath ?? "" }, set: { Game.WinePrefixPath = $0.isEmpty ? nil : $0 }))
                }
                if Game.LaunchMode == .Highball {
                    TextField(I18n.T("Highball bottle"), text: $Game.HighballBottle)
                    Picker(I18n.T("Renderer"), selection: $Game.Renderer) {
                        ForEach(["auto", "dxmt", "d3dmetal", "dxvk", "wined3d"], id: \.self) { Renderer in Text(Renderer).tag(Renderer) }
                    }
                }
                Toggle(I18n.T("Favorite"), isOn: $Game.Favorite)
                Toggle(I18n.T("Automatically install newer versions from the index"), isOn: $Game.AutomaticallyUpdate).disabled(!Game.IsManaged)
            }.formStyle(.grouped)
            VStack(alignment: .leading, spacing: 7) {
                Text(I18n.T("Private notes")).font(.system(size: 12, weight: .medium))
                TextEditor(text: $Game.Notes).font(.system(size: 12)).frame(height: 72).padding(5).background(Theme.Card).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button(I18n.T("Show in Finder")) { Store.RevealGame(Game) }.buttonStyle(SecondaryButtonStyle())
                Menu(I18n.T("Library tools")) {
                    Button(I18n.T("Measure installed size")) { Task { do { try await Store.LibraryStore.MeasureSize(Game.Id) } catch { Store.Report(error) } } }
                    Button(I18n.T("Reinstall…")) { Dismiss(); Store.RequestReinstall(Game) }.disabled(Store.IsRunning(Game))
                    Button(I18n.T("Move installation…")) { Dismiss(); Store.MoveGame(Game) }.disabled(!Game.IsManaged || Store.IsRunning(Game))
                }
                Spacer()
                Button(I18n.T("Cancel")) { Dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Button(I18n.T("Save changes")) {
                    Game.LaunchArguments = Arguments.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    if let Current = Store.Library.first(where: { $0.Id == Game.Id }) {
                        if Game.ExecutablePath == Current.ExecutablePath {
                            Game.InstalledSizeBytes = Current.InstalledSizeBytes; Game.SizeMeasuredAt = Current.SizeMeasuredAt
                        } else { Game.InstalledSizeBytes = nil; Game.SizeMeasuredAt = nil }
                        Game.PlayTimeSeconds = Current.PlayTimeSeconds; Game.LaunchCount = Current.LaunchCount
                        Game.LastPlayedAt = Current.LastPlayedAt; Game.LastSession = Current.LastSession
                        Game.LastSessionId = Current.LastSessionId; Game.LastSessionRecordedSeconds = Current.LastSessionRecordedSeconds
                        Game.RecordedSessionSecondsById = Current.RecordedSessionSecondsById
                    }
                    Store.UpdateGame(Game)
                    Dismiss()
                }.buttonStyle(PrimaryButtonStyle()).disabled(Game.Name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 660).background(Theme.Background).foregroundStyle(Theme.Foreground)
            .onAppear { Arguments = Game.LaunchArguments.joined(separator: "\n") }
    }
    private func ChooseExecutable() {
        let Panel = NSOpenPanel()
        Panel.title = "Choose the game application or executable"
        Panel.canChooseFiles = true
        Panel.canChooseDirectories = false
        Panel.treatsFilePackagesAsDirectories = false
        if Panel.runModal() == .OK, let URL = Panel.url {
            Game.ExecutablePath = URL.path
            Game.DirectoryPath = URL.deletingLastPathComponent().path
            Game.LaunchMode = LibraryService.DefaultLaunchMode(for: URL)
            Game.InstalledSizeBytes = nil; Game.SizeMeasuredAt = nil
        }
    }
}

struct LibraryUpdatesView: View {
    @EnvironmentObject var Store: AppStore
    @Environment(\.dismiss) private var Dismiss
    @State private var Results: [UUID: LibraryUpdateResult] = [:]
    @State private var VersionInputs: [UUID: String] = [:]
    @State private var IsChecking = false
    @State private var CheckTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                SectionHeading(Title: I18n.T("Library updates"), Subtitle: I18n.T("Compare installed versions before opening the latest release"), Symbol: "arrow.triangle.2.circlepath")
                Button(I18n.T("Done")) { Dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                if IsChecking { ProgressView().controlSize(.small); Text(I18n.Interpolated("Checking \(Results.count) of \(Store.Library.count)…")).font(.caption) }
                else { Text(I18n.Interpolated("\(Results.values.filter { $0.Status == .Available }.count) updates available")).font(.system(size: 13, weight: .medium)) }
                Spacer()
                Button(IsChecking ? "Cancel" : "Check updates") {
                    if IsChecking { CheckTask?.cancel() } else { CheckAll() }
                }.buttonStyle(PrimaryButtonStyle())
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if Store.Library.isEmpty { EmptyPanel(Symbol: "books.vertical", Title: I18n.T("Your library is empty"), Message: I18n.T("Add an installed game to compare its release with the catalogue.")) }
                    ForEach(Store.Library) { Installed in UpdateRow(Installed) }
                }
            }
        }.padding(26).frame(minWidth: 730, minHeight: 540).background(Theme.Background)
            .MotionAnimation(IsChecking)
            .task { CheckAll() }.onDisappear { CheckTask?.cancel() }
    }

    private func UpdateRow(_ Installed: LibraryGame) -> some View {
        let Result = Results[Installed.Id]
        return Panel(Padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(Installed.Name).font(.system(size: 15, weight: .semibold))
                        Text(Result?.Status.rawValue ?? "Waiting to check").font(.caption).foregroundStyle(Result?.Status == .Available ? Theme.Accent : Theme.SecondaryText)
                    }
                    Spacer()
                    if let Latest = Result?.LatestGame {
                        if Result?.Status == .Available {
                            Button(I18n.T("Install update…")) { Dismiss(); Store.RequestReinstall(Installed) }
                                .buttonStyle(PrimaryButtonStyle()).disabled(Store.IsRunning(Installed))
                        }
                        Button(I18n.T("View latest")) {
                            Dismiss()
                            Task { try? await Task.sleep(nanoseconds: 250_000_000); Store.OpenGame(Latest) }
                        }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                HStack(spacing: 16) {
                    Text(I18n.Interpolated("Installed: \(Installed.Version ?? "Unknown")")).font(.caption)
                    Text(I18n.Interpolated("Latest: \(Result?.LatestVersion ?? "Unknown")")).font(.caption).foregroundStyle(Theme.SecondaryText)
                }
                if let Message = Result?.Message { Text(I18n.T(Message)).font(.caption).foregroundStyle(Theme.SecondaryText).fixedSize(horizontal: false, vertical: true) }
                DisclosureGroup(I18n.T("Set installed version")) {
                    HStack(spacing: 10) {
                        TextField(I18n.T("Version from the installed game"), text: Binding(get: { VersionInputs[Installed.Id] ?? Installed.Version ?? "" }, set: { VersionInputs[Installed.Id] = $0 }))
                            .textFieldStyle(.roundedBorder)
                        Button(I18n.T("Save version")) { SaveVersion(Installed) }.buttonStyle(SecondaryButtonStyle()).disabled(IsChecking)
                    }.padding(.top, 8)
                }.font(.caption)
            }
        }
    }

    private func SaveVersion(_ Installed: LibraryGame) {
        var Updated = Installed
        let Value = (VersionInputs[Installed.Id] ?? Installed.Version ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        Updated.Version = Value.isEmpty ? nil : Value
        do {
            try Store.LibraryStore.Update(Updated)
            Task {
                do { Results[Installed.Id] = try await LibraryUpdateService.Check(Installed: Updated, Games: Store.Games, Catalog: Store.Catalog) }
                catch { Store.Report(error) }
            }
        } catch { Store.Report(error) }
    }

    private func CheckAll() {
        CheckTask?.cancel()
        CheckTask = Task {
            IsChecking = true; Results = [:]
            defer { IsChecking = false }
            for Installed in Store.Library {
                if Task.isCancelled { break }
                do { Results[Installed.Id] = try await LibraryUpdateService.Check(Installed: Installed, Games: Store.Games, Catalog: Store.Catalog) }
                catch { if !Task.isCancelled { Store.Report(error) }; break }
            }
        }
    }
}

struct LibraryValueView: View {
    let Games: [LibraryGame]
    @Environment(\.dismiss) private var Dismiss
    @State private var Total = 0.0
    @State private var Matched = 0
    @State private var Unmatched: [String] = []
    @State private var PriceEntries: [LibraryValueEntry] = []
    @State private var Checked = 0
    @State private var CurrentGame = ""
    @State private var IsCalculating = false
    @State private var Failure: String?
    @State private var Calculation: Task<Void, Never>?

    private var Currency: String {
        Total.formatted(.currency(code: "USD"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(I18n.T("Library Value")).font(.system(size: 30, weight: .bold))
            HStack(spacing: 4) {
                Text(I18n.T("Estimated retail value of your game library based on"))
                Button(I18n.T("CheapShark API ↗")) { NSWorkspace.shared.open(URL(string: "https://apidocs.cheapshark.com/")!) }
                    .buttonStyle(.plain).foregroundStyle(Theme.Accent)
            }
            .font(.system(size: 14)).foregroundStyle(Theme.SecondaryText)
            if IsCalculating {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large)
                    Text(I18n.T("Calculating…")).font(.system(size: 13, weight: .semibold))
                    Text(I18n.Interpolated("\(Checked) / \(Games.count)")).font(.system(size: 12))
                    Text(CurrentGame).font(.system(size: 11)).lineLimit(1)
                    ProgressView(value: Double(Checked), total: Double(max(Games.count, 1)))
                        .tint(Theme.Accent).frame(maxWidth: 250)
                }
                .foregroundStyle(Theme.SecondaryText)
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
            VStack(spacing: 8) {
                Text((Unmatched.isEmpty && Failure == nil) ? "Total Library Value" : "Matched Library Value")
                    .font(.system(size: 16)).foregroundStyle(Theme.SecondaryText)
                Text(Currency).font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.Accent).monospacedDigit()
                Text(I18n.Interpolated("\(Matched) games found") + (Unmatched.isEmpty ? "" : " · \(Unmatched.count) not matched"))
                    .font(.system(size: 13)).foregroundStyle(Theme.SecondaryText)
            }
            .frame(maxWidth: .infinity).padding(24)
            .background(Theme.Accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
            if !PriceEntries.isEmpty {
                Text(I18n.T("Price Breakdown")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.Accent)
                VStack(spacing: 2) {
                    ForEach(PriceEntries.sorted { $0.Price > $1.Price }) { Entry in
                        HStack {
                            Text(Entry.Title).lineLimit(1)
                            Spacer()
                            Text(String(format: "$%.2f", Entry.Price)).fontWeight(.medium)
                        }
                        .font(.system(size: 12)).foregroundStyle(Theme.Accent)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                    }
                }
                .padding(8).overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.Border))
            }
            if !Unmatched.isEmpty {
                Text(I18n.Interpolated("\(Unmatched.count) games not found"))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.SecondaryText)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(Unmatched.enumerated()), id: \.offset) { _, Name in
                        Text(Name).font(.system(size: 11)).foregroundStyle(Theme.SecondaryText).lineLimit(1)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.Border.opacity(0.7)))
            }
            if let Failure {
                Label(Failure, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(.orange)
            }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            }
            Spacer(minLength: 0)
            HStack {
                if !IsCalculating {
                    Button(I18n.T("Recalculate")) { Start(Force: true) }.buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                Button(I18n.T("Close")) { Dismiss() }.buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(28)
        .frame(width: 590, height: 550)
        .background(Theme.Background)
        .task { Start() }
        .onDisappear { Calculation?.cancel() }
    }

    private func Start(Force: Bool = false) {
        Calculation?.cancel()
        if !Force,
           let Data = UserDefaults.standard.data(forKey: "NativeLibraryValueCache"),
           let Cached = try? JSONDecoder().decode(LibraryValueSnapshot.self, from: Data),
           Cached.Titles == Games.map(\.Name) {
            PriceEntries = Cached.Entries
            Unmatched = Cached.NotFound
            Total = Cached.Entries.reduce(0) { $0 + $1.Price }
            Matched = Cached.Entries.count
            Checked = Games.count
            IsCalculating = false
            Failure = nil
            return
        }
        Total = 0
        Matched = 0
        Checked = 0
        CurrentGame = ""
        Unmatched = []
        PriceEntries = []
        Failure = nil
        IsCalculating = !Games.isEmpty
        guard !Games.isEmpty else { return }
        Calculation = Task {
            var FailedRequests = 0
            for (Index, Game) in Games.enumerated() {
                if Task.isCancelled { return }
                CurrentGame = Game.Name
                do {
                    if let Price = try await CheapSharkRetailPrice.Lookup(Name: Game.Name), Price.Value > 0 {
                        if Task.isCancelled { return }
                        Total += Price.Value
                        Matched += 1
                        PriceEntries.append(LibraryValueEntry(Title: Price.Title, Price: Price.Value))
                    } else {
                        if Task.isCancelled { return }
                        Unmatched.append(Game.Name)
                    }
                } catch {
                    if Task.isCancelled { return }
                    if let LookupError = error as? CheapSharkRetailPrice.LookupError {
                        Failure = LookupError.localizedDescription
                        break
                    }
                    FailedRequests += 1
                    Unmatched.append(Game.Name)
                }
                Checked = Index + 1
                if Checked < Games.count { try? await Task.sleep(for: .milliseconds(1200)) }
            }
            if Task.isCancelled { return }
            IsCalculating = false
            if FailedRequests > 0 && Failure == nil {
                Failure = "\(FailedRequests) games could not be checked. Recalculate to try again."
            }
            if Failure == nil,
               let Data = try? JSONEncoder().encode(LibraryValueSnapshot(
                Titles: Games.map(\.Name), Entries: PriceEntries, NotFound: Unmatched)) {
                UserDefaults.standard.set(Data, forKey: "NativeLibraryValueCache")
            }
        }
    }
}

private struct LibraryValueEntry: Codable, Identifiable {
    var id = UUID()
    let Title: String
    let Price: Double
}

private struct LibraryValueSnapshot: Codable {
    let Titles: [String]
    let Entries: [LibraryValueEntry]
    let NotFound: [String]
}

private enum CheapSharkRetailPrice {
    enum LookupError: LocalizedError {
        case rateLimited
        var errorDescription: String? { "CheapShark is rate limiting requests. Try again later." }
    }
    struct Price {
        let Title: String
        let Value: Double
    }
    private struct SearchResult: Decodable {
        let gameID: String
        let external: String
        let cheapest: String
    }
    private struct GameDetail: Decodable {
        struct Info: Decodable { let title: String }
        struct Deal: Decodable { let retailPrice: String?; let normalPrice: String? }
        let info: Info
        let deals: [Deal]
    }

    static func Lookup(Name: String) async throws -> Price? {
        var Search = URLComponents(string: "https://www.cheapshark.com/api/1.0/games")!
        Search.queryItems = [URLQueryItem(name: "title", value: Name), URLQueryItem(name: "limit", value: "5")]
        let Results = try JSONDecoder().decode([SearchResult].self, from: await Fetch(Search.url!))
        guard let Match = Results.first(where: {
            $0.external.trimmingCharacters(in: .whitespacesAndNewlines)
                .compare(Name.trimmingCharacters(in: .whitespacesAndNewlines), options: .caseInsensitive) == .orderedSame
        }) ?? Results.first else { return nil }
        var Details = URLComponents(string: "https://www.cheapshark.com/api/1.0/games")!
        Details.queryItems = [URLQueryItem(name: "id", value: Match.gameID)]
        let Detail = try JSONDecoder().decode(GameDetail.self, from: await Fetch(Details.url!))
        let Retail = Detail.deals.compactMap { Double($0.retailPrice ?? $0.normalPrice ?? "") }
            .filter { $0.isFinite && $0 >= 0 }.max()
        return Price(Title: Detail.info.title, Value: Retail ?? Double(Match.cheapest) ?? 0)
    }

    private static func Fetch(_ URL: URL) async throws -> Data {
        var Request = URLRequest(url: URL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        Request.setValue("AscendaraMac/\(AppVersion.Current) (library value lookup)", forHTTPHeaderField: "User-Agent")
        Request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (Data, Response) = try await URLSession.shared.data(for: Request)
        guard let HTTP = Response as? HTTPURLResponse else { throw AppFailure.Message("CheapShark did not return a valid response.") }
        guard HTTP.statusCode == 200 else {
            if HTTP.statusCode == 429 { throw LookupError.rateLimited }
            throw AppFailure.Message("CheapShark returned HTTP \(HTTP.statusCode).")
        }
        return Data
    }
}
