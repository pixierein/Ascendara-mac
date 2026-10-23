import Foundation

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
