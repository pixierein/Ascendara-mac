import SwiftUI

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
                SectionHeading(Title: "Library updates", Subtitle: "Compare installed versions before opening the latest release", Symbol: "arrow.triangle.2.circlepath")
                Button("Done") { Dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack {
                if IsChecking { ProgressView().controlSize(.small); Text("Checking \(Results.count) of \(Store.Library.count)…").font(.caption) }
                else { Text("\(Results.values.filter { $0.Status == .Available }.count) updates available").font(.system(size: 13, weight: .medium)) }
                Spacer()
                Button(IsChecking ? "Cancel" : "Check updates") {
                    if IsChecking { CheckTask?.cancel() } else { CheckAll() }
                }.buttonStyle(PrimaryButtonStyle())
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if Store.Library.isEmpty { EmptyPanel(Symbol: "books.vertical", Title: "Your library is empty", Message: "Add an installed game to compare its release with the catalogue.") }
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
                        Button("View latest") {
                            Dismiss()
                            Task { try? await Task.sleep(nanoseconds: 250_000_000); Store.OpenGame(Latest) }
                        }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                HStack(spacing: 16) {
                    Text("Installed: \(Installed.Version ?? "Unknown")").font(.caption)
                    Text("Latest: \(Result?.LatestVersion ?? "Unknown")").font(.caption).foregroundStyle(Theme.SecondaryText)
                }
                if let Message = Result?.Message { Text(Message).font(.caption).foregroundStyle(Theme.SecondaryText).fixedSize(horizontal: false, vertical: true) }
                DisclosureGroup("Set installed version") {
                    HStack(spacing: 10) {
                        TextField("Version from the installed game", text: Binding(get: { VersionInputs[Installed.Id] ?? Installed.Version ?? "" }, set: { VersionInputs[Installed.Id] = $0 }))
                            .textFieldStyle(.roundedBorder)
                        Button("Save version") { SaveVersion(Installed) }.buttonStyle(SecondaryButtonStyle()).disabled(IsChecking)
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
