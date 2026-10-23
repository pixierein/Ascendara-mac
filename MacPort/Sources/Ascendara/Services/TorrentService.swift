import Foundation

struct TorrentItem: Identifiable {
    var Id: String
    var Name: String
    var State: String
    var Progress: Double
    var Size: Int64
    var Speed: Int64
    var id: String { Id }
}

enum TorrentService {
    static func Add(URL: URL, Settings: AppSettings) async throws {
        guard ["magnet", "http", "https"].contains(URL.scheme?.lowercased() ?? "") else { throw AppFailure.Message("Enter a torrent URL or magnet link.") }
        let (Session, Base) = try await Connect(Settings: Settings)
        defer { Session.finishTasksAndInvalidate() }
        let Form = IntegrationHTTP.Multipart(["urls": URL.absoluteString, "savepath": Settings.DownloadDirectory])
        let Data = try await Send(Session: Session, Base: Base, Path: "torrents/add", Body: Form.Data, ContentType: Form.ContentType)
        guard String(decoding: Data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ok." else {
            throw AppFailure.Message("qBittorrent did not accept the torrent link.")
        }
    }

    static func List(Settings: AppSettings) async throws -> [TorrentItem] {
        let (Session, Base) = try await Connect(Settings: Settings)
        defer { Session.finishTasksAndInvalidate() }
        let Data = try await Send(Session: Session, Base: Base, Path: "torrents/info")
        guard let Items = try JSONSerialization.jsonObject(with: Data) as? [[String: Any]] else { throw AppFailure.Message("qBittorrent returned an invalid torrent list.") }
        return Items.compactMap { Item in
            guard let Id = Item["hash"] as? String else { return nil }
            return TorrentItem(Id: Id, Name: Item["name"] as? String ?? Id, State: Item["state"] as? String ?? "Unknown",
                               Progress: Item["progress"] as? Double ?? 0, Size: (Item["size"] as? NSNumber)?.int64Value ?? 0,
                               Speed: (Item["dlspeed"] as? NSNumber)?.int64Value ?? 0)
        }
    }

    static func Control(Id: String, Operation: String, Settings: AppSettings) async throws {
        guard ["stop", "start", "delete"].contains(Operation) else { throw AppFailure.Message("Unsupported torrent operation.") }
        let (Session, Base) = try await Connect(Settings: Settings)
        defer { Session.finishTasksAndInvalidate() }
        let Body = IntegrationHTTP.Form(["hashes": Id, "deleteFiles": "false"])
        do { _ = try await Send(Session: Session, Base: Base, Path: "torrents/\(Operation)", Body: Body) }
        catch CatalogError.HTTP(404) where Operation != "delete" {
            _ = try await Send(Session: Session, Base: Base, Path: "torrents/\(Operation == "stop" ? "pause" : "resume")", Body: Body)
        }
    }

    private static func Connect(Settings: AppSettings) async throws -> (URLSession, URL) {
        guard let Base = URL(string: Settings.QBitTorrentURL), ["http", "https"].contains(Base.scheme?.lowercased() ?? ""), Base.host != nil else {
            throw AppFailure.Message("Set a valid qBittorrent Web UI address in Preferences.")
        }
        let Session = URLSession(configuration: .ephemeral)
        do {
            let Data = try await Send(Session: Session, Base: Base, Path: "auth/login",
                Body: IntegrationHTTP.Form(["username": Settings.QBitTorrentUsername, "password": Settings.QBitTorrentPassword]))
            guard String(decoding: Data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ok." else {
                throw AppFailure.Message("qBittorrent authentication failed. Check the Web UI username and password.")
            }
            return (Session, Base)
        } catch { Session.invalidateAndCancel(); throw error }
    }

    private static func Send(Session: URLSession, Base: URL, Path: String, Body: Data? = nil,
                             ContentType: String = "application/x-www-form-urlencoded") async throws -> Data {
        var Request = URLRequest(url: Base.appendingPathComponent("api/v2/\(Path)"), timeoutInterval: 15)
        Request.setValue(Base.absoluteString, forHTTPHeaderField: "Referer")
        Request.setValue(Base.absoluteString, forHTTPHeaderField: "Origin")
        if let Body { Request.httpMethod = "POST"; Request.httpBody = Body; Request.setValue(ContentType, forHTTPHeaderField: "Content-Type") }
        let (Data, Response) = try await Session.data(for: Request)
        let Status = (Response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(Status) else { throw CatalogError.HTTP(Status) }
        return Data
    }
}
