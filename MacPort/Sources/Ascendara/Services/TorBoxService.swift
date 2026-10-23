import Foundation

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
