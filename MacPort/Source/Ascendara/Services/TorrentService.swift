import Foundation
import Darwin

struct TorrentItem: Identifiable {
    var Id: String
    var Name: String
    var State: String
    var Progress: Double
    var Size: Int64
    var Speed: Int64
    var SavePath: String
    var ContentPath: String
    var ETA: Int64
    var id: String { Id }
    var IsComplete: Bool { Progress >= 0.99999 }
}

struct TorrentInstallation {
    var Directory: URL
    var ManualInstaller: URL?
    var NeedsManualInstaller: Bool { ManualInstaller != nil }
}

struct TorrentJobStatus: Codable, Identifiable, Equatable {
    var Id: UUID
    var GameName: String
    var State: String
    var Progress: Double
    var Speed: Int64
    var ETA: Int64
    var TorrentHash: String?
    var ResultDirectory: String?
    var ManualInstaller: String?
    var ErrorMessage: String?
    var PID: Int32
    var id: UUID { Id }
    var IsTerminal: Bool { ["Completed", "ManualInstallRequired", "Cancelled", "Failed"].contains(State) }
}

private struct TorrentWorkerJob: Codable {
    var Id: UUID
    var SourceURL: URL
    var GameName: String
    var DownloadDirectory: URL
    var QBitTorrentURL: URL
    var Username: String
    var Password: String
    var EstimatedSizeBytes: Int64?
    var SpeedLimitBytesPerSecond: Int64?
}

private struct TorrentJobMetadata: Codable {
    var Id: UUID
    var GameName: String
    var CreatedAt: Date
}

private struct TorrentWorkerStatus: Codable {
    var State: String
    var Progress: Double?
    var Speed: Int64?
    var ETA: Int64?
    var TorrentHash: String?
    var ResultDirectory: String?
    var ManualInstaller: String?
    var ErrorMessage: String?
    var PID: Int32?
}

/// Native qBittorrent Web UI counterpart to AscendaraTorrentHandler. The
/// external client owns the transfer while Ascendara is closed; this service
/// registers game-scoped jobs, reads progress and finalizes downloaded files.
enum TorrentService {
    private static var JobRoot: URL { RuntimePaths.Support.appendingPathComponent("TorrentJobs", isDirectory: true) }
    private static func JobDirectory(_ id: UUID) -> URL { JobRoot.appendingPathComponent(id.uuidString, isDirectory: true) }
    private static var HandlerURL: URL? {
        let configured = ProcessInfo.processInfo.environment["ASCENDARA_TORRENT_HANDLER"]
        let candidate = configured.map { URL(fileURLWithPath: $0) } ?? Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("AscendaraTorrentHandler")
        return candidate.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
    }

    static func Add(URL: URL, Settings: AppSettings, GameName: String? = nil,
                    EstimatedSizeBytes: Int64? = nil) async throws {
        guard ["magnet", "http", "https"].contains(URL.scheme?.lowercased() ?? "") else {
            throw AppFailure.Message("Enter a torrent URL or magnet link.")
        }
        if let GameName, let handler = HandlerURL,
           let base = Foundation.URL(string: Settings.QBitTorrentURL), IsLocalQBitTorrent(base) {
            let id = UUID()
            let directory = JobDirectory(id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            _ = chmod(JobRoot.path, S_IRUSR | S_IWUSR | S_IXUSR)
            _ = chmod(directory.path, S_IRUSR | S_IWUSR | S_IXUSR)
            let job = TorrentWorkerJob(Id: id, SourceURL: URL, GameName: GameName,
                                       DownloadDirectory: Foundation.URL(fileURLWithPath: Settings.DownloadDirectory, isDirectory: true),
                                       QBitTorrentURL: base, Username: Settings.QBitTorrentUsername,
                                       Password: Settings.QBitTorrentPassword,
                                       EstimatedSizeBytes: EstimatedSizeBytes,
                                       SpeedLimitBytesPerSecond: Int64(max(0, Settings.DownloadSpeedLimitKBps)) * 1024)
            let jobURL = directory.appendingPathComponent("job.json")
            try JSONEncoder().encode(job).write(to: jobURL, options: .atomic)
            _ = chmod(jobURL.path, S_IRUSR | S_IWUSR)
            let metadataURL = directory.appendingPathComponent("metadata.json")
            try JSONEncoder().encode(TorrentJobMetadata(Id: id, GameName: GameName, CreatedAt: Date()))
                .write(to: metadataURL, options: .atomic)
            _ = chmod(metadataURL.path, S_IRUSR | S_IWUSR)
            let process = Process()
            process.executableURL = handler
            process.arguments = [directory.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() }
            catch { try? FileManager.default.removeItem(at: directory); throw error }
            return
        }
        try await AddDirect(URL: URL, Settings: Settings, GameName: GameName,
                            EstimatedSizeBytes: EstimatedSizeBytes)
    }

    static func ListJobs() -> [TorrentJobStatus] {
        guard let directories = try? FileManager.default.contentsOfDirectory(at: JobRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return directories.compactMap { directory in
            guard let id = UUID(uuidString: directory.lastPathComponent),
                  let metadata = (try? Data(contentsOf: directory.appendingPathComponent("metadata.json"))).flatMap({ try? JSONDecoder().decode(TorrentJobMetadata.self, from: $0) }),
                  let state = (try? Data(contentsOf: directory.appendingPathComponent("status.json"))).flatMap({ try? JSONDecoder().decode(TorrentWorkerStatus.self, from: $0) }) else { return nil }
            return TorrentJobStatus(Id: id, GameName: metadata.GameName, State: state.State,
                                    Progress: state.Progress ?? 0, Speed: state.Speed ?? 0,
                                    ETA: state.ETA ?? 0, TorrentHash: state.TorrentHash,
                                    ResultDirectory: state.ResultDirectory, ManualInstaller: state.ManualInstaller,
                                    ErrorMessage: state.ErrorMessage, PID: state.PID ?? 0)
        }.sorted { $0.GameName.localizedCaseInsensitiveCompare($1.GameName) == .orderedAscending }
    }

    static func ControlJob(_ id: UUID, Operation: String) throws {
        guard ["pause", "resume", "cancel", "remove"].contains(Operation) else {
            throw AppFailure.Message("Unsupported torrent operation.")
        }
        let directory = JobDirectory(id)
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("metadata.json").path) else {
            throw AppFailure.Message("The torrent job no longer exists.")
        }
        let status = (try? Data(contentsOf: directory.appendingPathComponent("status.json"))).flatMap { try? JSONDecoder().decode(TorrentWorkerStatus.self, from: $0) }
        if Operation == "remove" {
            guard ["Completed", "ManualInstallRequired", "Cancelled", "Failed", "Paused"].contains(status?.State ?? "") else {
                throw AppFailure.Message("Pause the torrent before removing its job history.")
            }
            try FileManager.default.removeItem(at: directory)
            return
        }
        let control = directory.appendingPathComponent("control.txt")
        if Operation == "resume" {
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("job.json").path) else {
                throw AppFailure.Message("This finished torrent cannot be resumed.")
            }
            guard let handler = HandlerURL else { throw AppFailure.Message("The signed torrent handler is missing from this app build.") }
            if let pid = status?.PID, pid > 0, kill(pid, 0) == 0 {
                throw AppFailure.Message("The torrent handler is still running.")
            }
            try? FileManager.default.removeItem(at: control)
            let process = Process()
            process.executableURL = handler
            process.arguments = [directory.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            return
        }
        try Operation.write(to: control, atomically: true, encoding: .utf8)
        _ = chmod(control.path, S_IRUSR | S_IWUSR)
        if Operation == "cancel", status?.State == "Paused", let handler = HandlerURL {
            let process = Process()
            process.executableURL = handler
            process.arguments = [directory.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
        }
    }

    private static func AddDirect(URL: URL, Settings: AppSettings, GameName: String?,
                                  EstimatedSizeBytes: Int64?) async throws {
        let (session, base) = try await Connect(Settings: Settings)
        defer { session.finishTasksAndInvalidate() }
        var fields = ["urls": URL.absoluteString, "sequentialDownload": "true"]
        if let GameName, IsLocalQBitTorrent(base) {
            let gameDirectory = Foundation.URL(fileURLWithPath: Settings.DownloadDirectory, isDirectory: true)
                .appendingPathComponent(RuntimePaths.SafeName(GameName), isDirectory: true)
            try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
            if let EstimatedSizeBytes, EstimatedSizeBytes > 0 { try CheckDiskSpace(gameDirectory, Required: EstimatedSizeBytes) }
            fields["savepath"] = gameDirectory.path
        }
        let form = IntegrationHTTP.Multipart(fields)
        let data = try await Send(Session: session, Base: base, Path: "torrents/add", Body: form.Data, ContentType: form.ContentType)
        guard String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ok." else {
            throw AppFailure.Message("qBittorrent did not accept the torrent link.")
        }
        if Settings.DownloadSpeedLimitKBps > 0, let hash = MagnetHash(URL) {
            // qBittorrent registers new magnets asynchronously. Like upstream,
            // wait briefly before applying a per-torrent speed limit.
            for _ in 0..<30 {
                let data = try await Send(Session: session, Base: base, Path: "torrents/info")
                if let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   list.contains(where: { ($0["hash"] as? String)?.lowercased() == hash }) {
                    _ = try await Send(Session: session, Base: base, Path: "torrents/setDownloadLimit",
                                       Body: IntegrationHTTP.Form(["hashes": hash, "limit": String(Settings.DownloadSpeedLimitKBps * 1024)]))
                    break
                }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    static func List(Settings: AppSettings) async throws -> [TorrentItem] {
        let (session, base) = try await Connect(Settings: Settings)
        defer { session.finishTasksAndInvalidate() }
        let data = try await Send(Session: session, Base: base, Path: "torrents/info")
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw AppFailure.Message("qBittorrent returned an invalid torrent list.")
        }
        return items.compactMap { item in
            guard let id = item["hash"] as? String else { return nil }
            return TorrentItem(Id: id, Name: item["name"] as? String ?? id,
                               State: item["state"] as? String ?? "Unknown",
                               Progress: (item["progress"] as? NSNumber)?.doubleValue ?? 0,
                               Size: (item["size"] as? NSNumber)?.int64Value ?? 0,
                               Speed: (item["dlspeed"] as? NSNumber)?.int64Value ?? 0,
                               SavePath: item["save_path"] as? String ?? "",
                               ContentPath: item["content_path"] as? String ?? "",
                               ETA: (item["eta"] as? NSNumber)?.int64Value ?? 0)
        }
    }

    static func Control(Id: String, Operation: String, Settings: AppSettings,
                        DeleteFiles: Bool = false) async throws {
        guard ["stop", "start", "delete"].contains(Operation) else {
            throw AppFailure.Message("Unsupported torrent operation.")
        }
        let (session, base) = try await Connect(Settings: Settings)
        defer { session.finishTasksAndInvalidate() }
        let body = IntegrationHTTP.Form(["hashes": Id, "deleteFiles": DeleteFiles ? "true" : "false"])
        do { _ = try await Send(Session: session, Base: base, Path: "torrents/\(Operation)", Body: body) }
        catch CatalogError.HTTP(404) where Operation != "delete" {
            _ = try await Send(Session: session, Base: base,
                               Path: "torrents/\(Operation == "stop" ? "pause" : "resume")", Body: body)
        }
    }

    /// Extract a completed local torrent using the same safe archive validator
    /// as direct downloads. Repack installers remain a manual handoff, matching
    /// the original helper's behavior (it does not silently grant elevation).
    static func Finalize(_ item: TorrentItem, GameName: String,
                         Settings: AppSettings) async throws -> TorrentInstallation {
        guard item.IsComplete else { throw AppFailure.Message("The torrent is still downloading.") }
        guard let base = Foundation.URL(string: Settings.QBitTorrentURL), IsLocalQBitTorrent(base) else {
            throw AppFailure.Message("Torrent files live on the qBittorrent host. Finalize them on that computer.")
        }
        let root = Foundation.URL(fileURLWithPath: Settings.DownloadDirectory, isDirectory: true).standardizedFileURL
        let content = Foundation.URL(fileURLWithPath: item.ContentPath.isEmpty ? item.SavePath : item.ContentPath)
            .resolvingSymlinksInPath().standardizedFileURL
        guard RuntimePaths.IsInside(content, root), FileManager.default.fileExists(atPath: content.path) else {
            throw AppFailure.Message("qBittorrent's completed files are outside the configured download folder or are missing.")
        }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: content.path, isDirectory: &isDirectory)
        let source = isDirectory.boolValue ? content : content.deletingLastPathComponent()
        let archives = try FindArchives(source)
        if archives.isEmpty {
            let installer = try FindInstaller(source, GameName: GameName)
            return TorrentInstallation(Directory: source, ManualInstaller: installer)
        }
        let installDirectory = source.appendingPathComponent(RuntimePaths.SafeName(GameName) + "-Installed", isDirectory: true)
        guard !FileManager.default.fileExists(atPath: installDirectory.path) else {
            throw AppFailure.Message("An installed torrent folder already exists: \(installDirectory.path)")
        }
        let staging = source.appendingPathComponent(".ascendara-torrent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            for (index, archive) in archives.enumerated() {
                let extracted = source.appendingPathComponent(".ascendara-part-\(UUID().uuidString)-\(index)", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: extracted) }
                try await ArchiveExtractor.Extract(archive, To: extracted)
                try Merge(extracted, Into: staging)
            }
            try WriteFileMap(staging)
            try FileManager.default.moveItem(at: staging, to: installDirectory)
            return TorrentInstallation(Directory: installDirectory, ManualInstaller: nil)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private static func FindArchives(_ directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var archives: [URL] = []
        for case let file as URL in enumerator {
            guard ["zip", "rar", "7z"].contains(file.pathExtension.lowercased()),
                  (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let lower = file.lastPathComponent.lowercased()
            if let range = lower.range(of: #"\.part([0-9]+)\.rar$"#, options: .regularExpression),
               let number = Int(lower[range].dropFirst(5).dropLast(4)), number != 1 { continue }
            archives.append(file)
        }
        return archives.sorted { ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    private static func FindInstaller(_ directory: URL, GameName: String) throws -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        let name = RuntimePaths.SafeName(GameName).lowercased()
        var files: [URL] = []
        for case let file as URL in enumerator where file.pathExtension.lowercased() == "exe" {
            let lower = file.lastPathComponent.lowercased()
            if lower.hasPrefix("setup") || lower.hasPrefix(name) { files.append(file) }
        }
        return files.sorted { $0.pathComponents.count < $1.pathComponents.count }.first
    }

    private static func Merge(_ source: URL, Into destination: URL) throws {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return }
        for case let file as URL in enumerator {
            let relative = file.path.replacingOccurrences(of: source.path + "/", with: "")
            try ArchiveExtractor.ValidatePath(relative)
            let target = destination.appendingPathComponent(relative)
            let isDirectory = (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                try manager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                guard !manager.fileExists(atPath: target.path) else {
                    throw AppFailure.Message("Two torrent archives contain the same file: \(relative)")
                }
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.moveItem(at: file, to: target)
            }
        }
    }

    private static func WriteFileMap(_ directory: URL) throws {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: []) else { return }
        var map: [String: [String: Int64]] = [:]
        for case let file as URL in enumerator where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let relative = file.path.replacingOccurrences(of: directory.path + "/", with: "")
            if relative.lowercased().hasSuffix(".url") || relative.lowercased().contains("_commonredist/") { continue }
            map[relative] = ["size": Int64((try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)]
        }
        try JSONEncoder().encode(map).write(to: directory.appendingPathComponent("filemap.ascendara.json"), options: .atomic)
    }

    private static func CheckDiskSpace(_ directory: URL, Required: Int64) throws {
        var info = statvfs()
        guard statvfs(directory.path, &info) == 0 else { return }
        let available = Int64(info.f_bavail) * Int64(info.f_frsize)
        if Required > available { throw AppFailure.Message("Insufficient disk space for the torrent download.") }
    }

    private static func MagnetHash(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "magnet",
              let xt = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name.lowercased() == "xt" })?.value,
              xt.lowercased().hasPrefix("urn:btih:") else { return nil }
        let value = String(xt.dropFirst("urn:btih:".count)).lowercased()
        if value.count == 40, value.allSatisfy({ $0.isHexDigit }) { return value }
        if value.count == 32 {
            let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
            var bytes: [UInt8] = []
            var pending = 0
            var bits = 0
            for character in value {
                guard let digit = alphabet.firstIndex(of: character) else { return nil }
                pending = (pending << 5) | digit
                bits += 5
                if bits >= 8 {
                    bits -= 8
                    bytes.append(UInt8((pending >> bits) & 0xff))
                    pending &= (1 << bits) - 1
                }
            }
            if bytes.count == 20 { return bytes.map { String(format: "%02x", $0) }.joined() }
        }
        return nil
    }

    private static func IsLocalQBitTorrent(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    private static func Connect(Settings: AppSettings) async throws -> (URLSession, URL) {
        guard let base = URL(string: Settings.QBitTorrentURL), ["http", "https"].contains(base.scheme?.lowercased() ?? ""), base.host != nil else {
            throw AppFailure.Message("Set a valid qBittorrent Web UI address in Preferences.")
        }
        let session = URLSession(configuration: .ephemeral)
        do {
            let data = try await Send(Session: session, Base: base, Path: "auth/login",
                                      Body: IntegrationHTTP.Form(["username": Settings.QBitTorrentUsername,
                                                                  "password": Settings.QBitTorrentPassword]))
            guard String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ok." else {
                throw AppFailure.Message("qBittorrent authentication failed. Check the Web UI username and password.")
            }
            return (session, base)
        } catch { session.invalidateAndCancel(); throw error }
    }

    private static func Send(Session: URLSession, Base: URL, Path: String, Body: Data? = nil,
                             ContentType: String = "application/x-www-form-urlencoded") async throws -> Data {
        var request = URLRequest(url: Base.appendingPathComponent("api/v2/\(Path)"), timeoutInterval: 15)
        request.setValue(Base.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(Base.absoluteString, forHTTPHeaderField: "Origin")
        if let Body {
            request.httpMethod = "POST"
            request.httpBody = Body
            request.setValue(ContentType, forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await Session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw CatalogError.HTTP(status) }
        return data
    }
}


struct TorBoxItem: Identifiable, Hashable {
    var Id: String
    var Name: String
    var Kind: String
    var State: String
    var Progress: Double
    var Size: Int64
    var Ready: Bool
    var id: String { "\(Kind):\(Id)" }
}

enum TorBoxService {
    static let BaseURL = URL(string: "https://api.torbox.app/v1/api")!

    static func List(APIKey: String) async throws -> [TorBoxItem] {
        async let Web = ListKind("webdl", APIKey: APIKey)
        async let Torrents = ListKind("torrents", APIKey: APIKey)
        return try await Web + Torrents
    }

    static func Create(Link: URL, APIKey: String) async throws {
        let IsTorrent = Link.scheme?.lowercased() == "magnet"
        guard IsTorrent || ["https", "http"].contains(Link.scheme?.lowercased() ?? "") else {
            throw AppFailure.Message("Enter an HTTP link or a magnet link.")
        }
        let Fields = IsTorrent ? ["magnet": Link.absoluteString, "allow_zip": "true"] : ["link": Link.absoluteString]
        let Form = IntegrationHTTP.Multipart(Fields)
        _ = try await Request(Path: IsTorrent ? "torrents/createtorrent" : "webdl/createwebdownload", APIKey: APIKey,
                              Method: "POST", Body: Form.Data, ContentType: Form.ContentType)
    }

    static func Control(Item: TorBoxItem, Operation: String, APIKey: String) async throws {
        guard ["pause", "resume", "delete", "reannounce"].contains(Operation) else { throw AppFailure.Message("Unsupported TorBox operation.") }
        let Key = Item.Kind == "torrents" ? "torrent_id" : "webdl_id"
        guard let Id = Int(Item.Id) else { throw AppFailure.Message("TorBox returned an invalid download ID.") }
        let Body = try JSONSerialization.data(withJSONObject: [Key: Id, "operation": Operation, "all": false])
        _ = try await Request(Path: "\(Item.Kind)/\(Item.Kind == "torrents" ? "controltorrent" : "controlwebdownload")",
                              APIKey: APIKey, Method: "POST", Body: Body, ContentType: "application/json")
    }

    static func DirectLink(Item: TorBoxItem, APIKey: String) async throws -> URL {
        let Response = try await Request(Path: "\(Item.Kind)/requestdl", APIKey: APIKey,
            Query: [URLQueryItem(name: "token", value: APIKey), URLQueryItem(name: Item.Kind == "torrents" ? "torrent_id" : "web_id", value: Item.Id), URLQueryItem(name: "zip_link", value: "true")])
        let Text = Response["data"] as? String ?? Response["download_url"] as? String
            ?? (Response["data"] as? [String: Any])?["download_url"] as? String
        guard let Text, let Link = URL(string: Text), ["http", "https"].contains(Link.scheme?.lowercased() ?? "") else {
            throw AppFailure.Message("TorBox has not provided a download link. Wait until the download is cached.")
        }
        return Link
    }

    private static func ListKind(_ Kind: String, APIKey: String) async throws -> [TorBoxItem] {
        let Response = try await Request(Path: "\(Kind)/mylist", APIKey: APIKey)
        let Items = Response["data"] as? [[String: Any]] ?? (Response["data"] as? [String: Any]).map { [$0] } ?? []
        return Items.compactMap { Item in
            guard let Id = Item["id"] else { return nil }
            let State = Item["download_state"] as? String ?? "Unknown"
            return TorBoxItem(Id: String(describing: Id), Name: Item["name"] as? String ?? "Download \(Id)", Kind: Kind,
                State: State, Progress: (Item["progress"] as? Double ?? 0).Clamped(To: 0...1),
                Size: (Item["size"] as? NSNumber)?.int64Value ?? 0,
                Ready: Item["download_present"] as? Bool == true || ["cached", "completed"].contains(State.lowercased()))
        }
    }

    private static func Request(Path: String, APIKey: String, Method: String = "GET", Body: Data? = nil,
                                ContentType: String? = nil, Query: [URLQueryItem] = []) async throws -> [String: Any] {
        guard !APIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppFailure.Message("Add your TorBox API key in Preferences.") }
        var Components = URLComponents(url: BaseURL.appendingPathComponent(Path), resolvingAgainstBaseURL: false)!
        Components.queryItems = Query.isEmpty ? nil : Query
        var Request = URLRequest(url: Components.url!, timeoutInterval: 45)
        Request.httpMethod = Method; Request.httpBody = Body
        Request.setValue("Bearer \(APIKey)", forHTTPHeaderField: "Authorization")
        if let ContentType { Request.setValue(ContentType, forHTTPHeaderField: "Content-Type") }
        let (Data, Response) = try await URLSession.shared.data(for: Request)
        let Object = (try? JSONSerialization.jsonObject(with: Data)) as? [String: Any] ?? [:]
        let Status = (Response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(Status), Object["success"] as? Bool == true else {
            throw AppFailure.Message(Object["detail"] as? String ?? "TorBox request failed (HTTP \(Status)).")
        }
        return Object
    }
}

enum IntegrationHTTP {
    static func Form(_ Fields: [String: String]) -> Data {
        var Parts = URLComponents()
        Parts.queryItems = Fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Data((Parts.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
    }
    static func Multipart(_ Fields: [String: String]) -> (Data: Data, ContentType: String) {
        let Boundary = "Ascendara-\(UUID().uuidString)"
        var Body = ""
        for (Key, Value) in Fields.sorted(by: { $0.key < $1.key }) {
            Body += "--\(Boundary)\r\nContent-Disposition: form-data; name=\"\(Key)\"\r\n\r\n\(Value)\r\n"
        }
        Body += "--\(Boundary)--\r\n"
        return (Data(Body.utf8), "multipart/form-data; boundary=\(Boundary)")
    }
}

private extension Double {
    func Clamped(To Range: ClosedRange<Double>) -> Double { min(max(self, Range.lowerBound), Range.upperBound) }
}
