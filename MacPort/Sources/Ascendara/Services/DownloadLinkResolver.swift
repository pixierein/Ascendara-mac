import CryptoKit
import Foundation

struct ResolvedDownload: Sendable {
    var URL: URL
    var FileName: String?
}

enum DownloadLinkResolver {
    static func Resolve(URL: URL) async throws -> [ResolvedDownload] {
        guard ["https", "http"].contains(URL.scheme?.lowercased() ?? ""), let Host = URL.host?.lowercased() else {
            throw AppFailure.Message("Choose an HTTP or HTTPS download link.")
        }
        if ["gofile.io", "www.gofile.io"].contains(Host) { return try await Gofile(Link: URL) }
        let BuzzHosts = ["buzzheavier.com", "bzzhr.co", "bzzhr.to", "fafda.to", "fuckingfast.net", "fuckingfast.co"]
        if BuzzHosts.contains(where: { Host == $0 || Host.hasSuffix("." + $0) }) { return [try await Buzz(Link: URL)] }
        return [ResolvedDownload(URL: URL)]
    }

    private static func Buzz(Link: URL) async throws -> ResolvedDownload {
        if Link.path.hasPrefix("/d/"), Link.query != nil { return ResolvedDownload(URL: Link) }
        var Request = URLRequest(url: Link, timeoutInterval: 30)
        Request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        Request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (Data, Response) = try await URLSession.shared.data(for: Request)
        guard let Response = Response as? HTTPURLResponse, (200..<300).contains(Response.statusCode) else {
            throw CatalogError.HTTP((Response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        let HTML = String(decoding: Data, as: UTF8.self)
        guard let Path = Capture(#"hx-get=["']([^"']+/download\?[^"']+)["']"#, Text: HTML),
              let Endpoint = URL(string: CatalogText.Clean(Path), relativeTo: Response.url ?? Link)?.absoluteURL else {
            throw AppFailure.Message("This host did not provide a download token. The link may have expired or require a browser challenge.")
        }
        var Head = URLRequest(url: Endpoint, timeoutInterval: 30)
        Head.httpMethod = "HEAD"
        Head.setValue("true", forHTTPHeaderField: "hx-request")
        Head.setValue(Link.absoluteString, forHTTPHeaderField: "hx-current-url")
        Head.setValue(Link.absoluteString, forHTTPHeaderField: "Referer")
        let (_, HeadResponse) = try await URLSession.shared.data(for: Head)
        guard let HTTP = HeadResponse as? HTTPURLResponse,
              let Target = HTTP.value(forHTTPHeaderField: "hx-redirect"),
              let Direct = URL(string: Target, relativeTo: Link)?.absoluteURL,
              Direct != Link, ["https", "http"].contains(Direct.scheme?.lowercased() ?? "") else {
            throw AppFailure.Message("The host did not return a direct download URL. Try another mirror or TorBox.")
        }
        let Title = Capture("<title[^>]*>([\\s\\S]*?)</title>", Text: HTML).map(CatalogText.Clean)
        return ResolvedDownload(URL: Direct, FileName: Title)
    }

    private static func Gofile(Link: URL) async throws -> [ResolvedDownload] {
        guard Link.scheme == "https", Link.user == nil, Link.password == nil,
              let Id = Capture(#"^/d/([A-Za-z0-9_-]+)/?$"#, Text: Link.path) else {
            throw AppFailure.Message("Expected a GOFile sharing URL in the form https://gofile.io/d/CONTENT_ID.")
        }
        let (SecretData, SecretResponse) = try await URLSession.shared.data(from: URL(string: "https://api.ascendara.app/app/json/gofilesecret")!)
        guard (SecretResponse as? HTTPURLResponse)?.statusCode == 200,
              let Payload = try JSONSerialization.jsonObject(with: SecretData) as? [String: Any],
              let Secret = Payload["secret"] as? String, !Secret.isEmpty else {
            throw AppFailure.Message("The GOFile connection configuration could not be loaded. Try again later or use TorBox.")
        }
        let Account = try await GofileRequest(Path: "accounts", Method: "POST", Secret: Secret, Token: "")
        guard let Token = Account["token"] as? String, !Token.isEmpty else { throw AppFailure.Message("GOFile did not issue an account token.") }
        var Pending = [Id]
        var Visited: Set<String> = []
        var Names: Set<String> = []
        var Files: [ResolvedDownload] = []
        while let Current = Pending.popLast() {
            try Task.checkCancellation()
            guard Visited.insert(Current).inserted else { continue }
            let Node = try await GofileRequest(Path: "contents/\(Current)", Secret: Secret, Token: Token)
            let Children: [[String: Any]]
            if Node["type"] as? String == "folder" {
                guard let ChildMap = Node["children"] as? [String: [String: Any]],
                      (Node["childrenCount"] as? Int ?? ChildMap.count) <= ChildMap.count else {
                    throw AppFailure.Message("GOFile returned an incomplete folder listing.")
                }
                Children = ChildMap.map { Key, Value in var Value = Value; if Value["id"] == nil { Value["id"] = Key }; return Value }
            } else { Children = [Node] }
            for var Child in Children {
                if Child["type"] as? String == "folder" {
                    if let ChildId = Child["id"] as? String { Pending.append(ChildId) }
                    continue
                }
                if Child["link"] == nil, let ChildId = Child["id"] as? String {
                    Child = try await GofileRequest(Path: "contents/\(ChildId)", Secret: Secret, Token: Token)
                }
                guard let Name = Child["name"] as? String, !Name.isEmpty, ![".", ".."].contains(Name),
                      !Name.contains("/"), !Name.contains("\\"), let Address = Child["link"] as? String,
                      let URL = URL(string: Address), URL.scheme == "https", URL.host != nil, URL.user == nil, URL.password == nil else {
                    throw AppFailure.Message("GOFile returned a file without a safe filename or download URL.")
                }
                guard Names.insert(Name.lowercased()).inserted else { throw AppFailure.Message("GOFile folders contain duplicate filenames: \(Name).") }
                Files.append(ResolvedDownload(URL: URL, FileName: Name))
            }
        }
        guard !Files.isEmpty else { throw AppFailure.Message("The GOFile folder does not contain downloadable files.") }
        if let Cookie = HTTPCookie(properties: [.domain: ".gofile.io", .path: "/", .name: "accountToken", .value: Token, .secure: "TRUE"]) {
            HTTPCookieStorage.shared.setCookie(Cookie)
        }
        return Files.sorted { ($0.FileName ?? "") < ($1.FileName ?? "") }
    }

    private static func GofileRequest(Path: String, Method: String = "GET", Secret: String, Token: String) async throws -> [String: Any] {
        let UserAgent = "Mozilla/5.0"
        let Slot = Int(Date().timeIntervalSince1970) / 14400
        let Text = "\(UserAgent)::en-US::\(Token)::\(Slot)::\(Secret)"
        let WebsiteToken = SHA256.hash(data: Data(Text.utf8)).map { String(format: "%02x", $0) }.joined()
        var Components = URLComponents(url: URL(string: "https://api.gofile.io")!.appendingPathComponent(Path), resolvingAgainstBaseURL: false)!
        if Method == "GET" { Components.queryItems = [URLQueryItem(name: "cache", value: "true"), URLQueryItem(name: "sortField", value: "createTime"), URLQueryItem(name: "sortDirection", value: "1")] }
        var Request = URLRequest(url: Components.url!, timeoutInterval: 30)
        Request.httpMethod = Method
        Request.setValue(UserAgent, forHTTPHeaderField: "User-Agent")
        Request.setValue("https://gofile.io", forHTTPHeaderField: "Origin")
        Request.setValue("https://gofile.io/", forHTTPHeaderField: "Referer")
        Request.setValue(WebsiteToken, forHTTPHeaderField: "X-Website-Token")
        Request.setValue("en-US", forHTTPHeaderField: "X-BL")
        if !Token.isEmpty { Request.setValue("Bearer \(Token)", forHTTPHeaderField: "Authorization") }
        let (Data, Response) = try await URLSession.shared.data(for: Request)
        let Status = (Response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(Status) else { throw CatalogError.HTTP(Status) }
        guard let Payload = try JSONSerialization.jsonObject(with: Data) as? [String: Any],
              Payload["status"] as? String == "ok", let Result = Payload["data"] as? [String: Any] else {
            let Payload = (try? JSONSerialization.jsonObject(with: Data)) as? [String: Any]
            throw AppFailure.Message("GOFile could not provide this content (\(Payload?["status"] as? String ?? "invalid response")). Password-protected or private folders must be opened in your browser.")
        }
        return Result
    }

    private static func Capture(_ Pattern: String, Text: String) -> String? {
        guard let Regex = try? NSRegularExpression(pattern: Pattern, options: .caseInsensitive),
              let Match = Regex.firstMatch(in: Text, range: NSRange(Text.startIndex..., in: Text)),
              let Range = Range(Match.range(at: 1), in: Text) else { return nil }
        return String(Text[Range])
    }
}
