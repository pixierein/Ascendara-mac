import Foundation

enum LibraryUpdateStatus: String {
    case Current = "Up to date"
    case Available = "Update available"
    case Different = "Catalogue version differs"
    case Unknown = "Installed version unknown"
    case Unavailable = "Latest version unavailable"
    case NoMatch = "No catalogue match"
    case Failed = "Check failed"
}

struct LibraryUpdateResult {
    var Status: LibraryUpdateStatus
    var LatestGame: Game?
    var LatestVersion: String?
    var Message: String?
}

enum LibraryUpdateService {
    static func Check(Installed: LibraryGame, Games: [Game], Catalog: CatalogService) async throws -> LibraryUpdateResult {
        let Match = Games.first { Game in
            if let Id = Installed.CatalogId { return Game.Id == Id }
            return Game.Name.caseInsensitiveCompare(Installed.Name) == .orderedSame
        }
        guard let Match else { return LibraryUpdateResult(Status: .NoMatch, Message: "Choose a catalogue containing this game to compare releases.") }
        guard let Version = Installed.Version?.trimmingCharacters(in: .whitespacesAndNewlines), !Version.isEmpty else {
            return LibraryUpdateResult(Status: .Unknown, LatestGame: Match, LatestVersion: Match.Version,
                                       Message: "Enter the version shown by your installed game to compare it with the catalogue.")
        }
        if Match.CustomSource != nil {
            guard let LatestVersion = Match.Version?.trimmingCharacters(in: .whitespacesAndNewlines), !LatestVersion.isEmpty else {
                return LibraryUpdateResult(Status: .Unavailable, LatestGame: Match,
                                           Message: "This catalogue does not include a version for this game.")
            }
            let Same = Normalize(Version) == Normalize(LatestVersion)
            return LibraryUpdateResult(Status: Same ? .Current : .Different, LatestGame: Match, LatestVersion: Match.Version,
                                       Message: "Compared with your custom catalogue. Check the source before installing another version.")
        }
        do {
            guard let Update = try await Catalog.CheckUpdate(GameId: Match.Id, Version: Version) else {
                return LibraryUpdateResult(Status: .NoMatch, LatestGame: Match, LatestVersion: Match.Version,
                                           Message: "The community update service does not list this game.")
            }
            guard Update.Id == Match.Id else { throw AppFailure.Message("The update server returned a different game's information.") }
            var Latest = Match
            Latest.Version = Update.LatestVersion
            if !Update.DownloadLinks.isEmpty { Latest.DownloadLinks = Update.DownloadLinks }
            return LibraryUpdateResult(Status: Update.UpdateAvailable ? .Available : .Current, LatestGame: Latest, LatestVersion: Update.LatestVersion)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
            return LibraryUpdateResult(Status: .Failed, LatestGame: Match, LatestVersion: Match.Version, Message: error.localizedDescription)
        }
    }

    static func Normalize(_ Version: String) -> String {
        var Value = Version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if Value.hasPrefix("v"), Value.dropFirst().first?.isNumber == true { Value.removeFirst() }
        return Value
    }
}
