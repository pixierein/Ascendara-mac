import Foundation

struct SteamLibraryEntry: Identifiable {
    var Id: String
    var Name: String
    var InstallURL: URL
    var ExecutableURL: URL?
    var id: String { Id }
}

enum SteamLibraryService {
    static func Scan() throws -> [SteamLibraryEntry] {
        let Steam = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Steam")
        return try Scan(SteamDirectory: Steam)
    }

    static func Scan(SteamDirectory: URL) throws -> [SteamLibraryEntry] {
        var Libraries = Set([SteamDirectory])
        let Folders = SteamDirectory.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let Text = try? String(contentsOf: Folders, encoding: .utf8) {
            let Pattern = #""path"\s*"((?:\\.|[^"\\])*)""#
            let Regex = try NSRegularExpression(pattern: Pattern, options: .caseInsensitive)
            for Match in Regex.matches(in: Text, range: NSRange(Text.startIndex..., in: Text)) {
                if let Range = Range(Match.range(at: 1), in: Text) {
                    Libraries.insert(URL(fileURLWithPath: String(Text[Range]).replacingOccurrences(of: "\\\\", with: "\\")))
                }
            }
        }
        var Entries: [SteamLibraryEntry] = []
        for Library in Libraries {
            let Apps = Library.appendingPathComponent("steamapps")
            guard FileManager.default.fileExists(atPath: Apps.path) else { continue }
            for Manifest in try FileManager.default.contentsOfDirectory(at: Apps, includingPropertiesForKeys: nil)
                where Manifest.lastPathComponent.hasPrefix("appmanifest_") && Manifest.pathExtension == "acf" {
                guard let Text = try? String(contentsOf: Manifest, encoding: .utf8), let Id = Value("appid", Text: Text),
                      let Name = Value("name", Text: Text), let Directory = Value("installdir", Text: Text) else { continue }
                let InstallURL = Apps.appendingPathComponent("common", isDirectory: true).appendingPathComponent(Directory, isDirectory: true)
                guard FileManager.default.fileExists(atPath: InstallURL.path) else { continue }
                Entries.append(SteamLibraryEntry(Id: Id, Name: Name, InstallURL: InstallURL, ExecutableURL: FindExecutable(Directory: InstallURL)))
            }
        }
        var Seen: Set<String> = []
        return Entries.filter { Seen.insert($0.Id).inserted }.sorted { $0.Name.localizedStandardCompare($1.Name) == .orderedAscending }
    }

    private static func Value(_ Key: String, Text: String) -> String? {
        let Pattern = "\"\(NSRegularExpression.escapedPattern(for: Key))\"\\s*\"((?:\\\\.|[^\"\\\\])*)\""
        guard let Regex = try? NSRegularExpression(pattern: Pattern, options: .caseInsensitive),
              let Match = Regex.firstMatch(in: Text, range: NSRange(Text.startIndex..., in: Text)),
              let Range = Range(Match.range(at: 1), in: Text) else { return nil }
        return String(Text[Range]).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func FindExecutable(Directory: URL) -> URL? {
        guard let Files = FileManager.default.enumerator(at: Directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        var Windows: [URL] = []
        var Native: [URL] = []
        for case let File as URL in Files {
            if File.pathExtension.lowercased() == "app" { return File }
            if Files.level > 3 { Files.skipDescendants(); continue }
            let Name = File.lastPathComponent.lowercased()
            if Name.hasSuffix(".exe"), !["unins", "setup", "crash", "redist"].contains(where: Name.contains) { Windows.append(File) }
            if File.pathExtension.isEmpty, FileManager.default.isExecutableFile(atPath: File.path),
               (try? File.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false { Native.append(File) }
        }
        return Native.sorted { $0.path.count < $1.path.count }.first ?? Windows.sorted { $0.path.count < $1.path.count }.first
    }
}


struct WorkshopItem: Identifiable {
    var Id: String
    var AppId: String
    var Title: String
    var Description: String
    var PreviewURL: URL?
    var Size: Int64
    var id: String { Id }
}

enum WorkshopService {
    static func Lookup(_ Text: String) async throws -> WorkshopItem {
        let Trimmed = Text.trimmingCharacters(in: .whitespacesAndNewlines)
        let Id = Trimmed.allSatisfy(\.isNumber) ? Trimmed : URLComponents(string: Trimmed)?.queryItems?.first(where: { $0.name == "id" })?.value ?? ""
        guard !Id.isEmpty, Id.allSatisfy(\.isNumber) else { throw AppFailure.Message("Enter a Steam Workshop item URL or numeric item ID.") }
        var Request = URLRequest(url: URL(string: "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/")!, timeoutInterval: 30)
        Request.httpMethod = "POST"
        Request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        Request.httpBody = IntegrationHTTP.Form(["itemcount": "1", "publishedfileids[0]": Id])
        let (Data, Response) = try await URLSession.shared.data(for: Request)
        let Status = (Response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(Status) else { throw CatalogError.HTTP(Status) }
        let Root = try JSONSerialization.jsonObject(with: Data) as? [String: Any]
        guard let Envelope = Root?["response"] as? [String: Any],
              let Item = (Envelope["publishedfiledetails"] as? [[String: Any]])?.first, Item["result"] as? Int == 1,
              let AppId = Item["consumer_app_id"] else { throw AppFailure.Message("Steam could not find a public Workshop item with that ID.") }
        return WorkshopItem(Id: Id, AppId: String(describing: AppId), Title: Item["title"] as? String ?? Id,
                            Description: CatalogText.Clean(Item["description"] as? String ?? ""),
                            PreviewURL: (Item["preview_url"] as? String).flatMap(URL.init(string:)),
                            Size: (Item["file_size"] as? NSNumber)?.int64Value ?? Int64(Item["file_size"] as? String ?? "") ?? 0)
    }

    static func Download(Item: WorkshopItem, Settings: AppSettings) async throws -> (Directory: URL, Log: String) {
        let Candidates = [Settings.SteamCMDPath, "/opt/homebrew/bin/steamcmd", "/usr/local/bin/steamcmd",
                          FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("steamcmd/steamcmd.sh").path]
        guard let Path = Candidates.first(where: { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw AppFailure.Message("Install SteamCMD for macOS and choose its executable in Preferences → Integrations.")
        }
        let Directory = URL(fileURLWithPath: Settings.DownloadDirectory).appendingPathComponent("Workshop", isDirectory: true)
        try FileManager.default.createDirectory(at: Directory, withIntermediateDirectories: true)
        let Result = try await NativeProcess.Run(URL(fileURLWithPath: Path), ["+force_install_dir", Directory.path, "+login", "anonymous",
            "+workshop_download_item", Item.AppId, Item.Id, "+quit"])
        let Log = Result.Output + Result.ErrorOutput
        guard Result.Status == 0, !Log.contains("ERROR!"), Log.localizedCaseInsensitiveContains("Downloaded item") else {
            throw AppFailure.Message("SteamCMD could not download this item. Some games require an authenticated Steam account.\n\(String(Log.suffix(2000)))")
        }
        let Relative = "steamapps/workshop/content/\(Item.AppId)/\(Item.Id)"
        let Locations = [Directory.appendingPathComponent(Relative), URL(fileURLWithPath: Path).deletingLastPathComponent().appendingPathComponent(Relative)]
        guard let Installed = Locations.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw AppFailure.Message("SteamCMD reported a download, but its item folder was not found.\n\(String(Log.suffix(2000)))")
        }
        return (Installed, Log)
    }
}
