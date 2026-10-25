import CryptoKit
import Foundation
import AppKit
import WebKit

struct ResolvedDownload: Sendable {
    var URL: URL
    var FileName: String?
    var Headers: [String: String] = [:]
    var Cookies: [DownloadCookie] = []
}

enum DownloadLinkResolver {
    private static let BrowserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func Resolve(URL: URL, Interactive: Bool = true) async throws -> [ResolvedDownload] {
        guard ["https", "http"].contains(URL.scheme?.lowercased() ?? ""), let Host = URL.host?.lowercased() else {
            throw AppFailure.Message("Choose an HTTP or HTTPS download link.")
        }
        if ["gofile.io", "www.gofile.io"].contains(Host) { return try await Gofile(Link: URL) }
        let BuzzHosts = ["buzzheavier.com", "bzzhr.co", "bzzhr.to", "fafda.to", "fuckingfast.net", "fuckingfast.co"]
        if BuzzHosts.contains(where: { Host == $0 || Host.hasSuffix("." + $0) }) {
            return [try await Buzz(Link: URL)]
        }
        if ["megadb.net", "megadb.xyz"].contains(where: { Host == $0 || Host.hasSuffix("." + $0) }) {
            return [try await MegaDB(Link: URL)]
        }
        if ["pixeldrain.com", "www.pixeldrain.com"].contains(Host),
           let Match = Capture(#"^/u/([A-Za-z0-9_-]+)/?$"#, Text: URL.path),
           let Direct = Foundation.URL(string: "https://pixeldrain.com/api/file/\(Match)?download") {
            return [ResolvedDownload(URL: Direct)]
        }
        let BrowserHosts = ["1fichier.com", "datanodes.to", "vikingfile.com", "fileditch.com", "fileditchfiles.me", "qiwi.gg"]
        if BrowserHosts.contains(where: { Host == $0 || Host.hasSuffix("." + $0) }) {
            guard Interactive else { throw AppFailure.Message("This mirror needs a provider step. Choose it manually or use another mirror.") }
            return [try await ProviderResolver.Resolve(Link: URL)]
        }
        return [ResolvedDownload(URL: URL)]
    }

    static func ContentLength(_ File: ResolvedDownload) async -> Int64? {
        var Request = URLRequest(url: File.URL, timeoutInterval: 15)
        Request.httpMethod = "HEAD"
        for (Key, Value) in File.Headers { Request.setValue(Value, forHTTPHeaderField: Key) }
        let Cookies = File.Cookies.compactMap { Cookie -> HTTPCookie? in
            HTTPCookie(properties: [.domain: Cookie.Domain, .path: Cookie.Path, .name: Cookie.Name,
                                   .value: Cookie.Value, .secure: Cookie.Secure ? "TRUE" : "FALSE"])
        }
        let Configuration = URLSessionConfiguration.ephemeral
        for Cookie in Cookies { Configuration.httpCookieStorage?.setCookie(Cookie) }
        let Session = URLSession(configuration: Configuration)
        defer { Session.finishTasksAndInvalidate() }
        guard let (_, Response) = try? await Session.data(for: Request), let HTTP = Response as? HTTPURLResponse,
              (200..<300).contains(HTTP.statusCode), HTTP.expectedContentLength > 0 else { return nil }
        return HTTP.expectedContentLength
    }

    static func ContentLengths(_ Files: [ResolvedDownload]) async -> [Int64?] {
        await withTaskGroup(of: (Int, Int64?).self) { Group in
            var Iterator = Files.enumerated().makeIterator()
            var Sizes = [Int64?](repeating: nil, count: Files.count)
            for _ in 0..<min(4, Files.count) {
                if let (Index, File) = Iterator.next() { Group.addTask { (Index, await ContentLength(File)) } }
            }
            while let (Index, Size) = await Group.next() {
                Sizes[Index] = Size
                if let (NextIndex, File) = Iterator.next() { Group.addTask { (NextIndex, await ContentLength(File)) } }
            }
            return Sizes
        }
    }

    private static func Buzz(Link: URL) async throws -> ResolvedDownload {
        let Headers = ["User-Agent": BrowserUserAgent, "Referer": Link.absoluteString]
        if Link.path.hasPrefix("/d/"), Link.query != nil {
            return ResolvedDownload(URL: Link, Headers: Headers)
        }
        return try await HeadlessBuzzResolver.Resolve(Link: Link)
    }

    private static func MegaDB(Link: URL) async throws -> ResolvedDownload {
        var Request = URLRequest(url: Link, timeoutInterval: 30)
        Request.setValue(BrowserUserAgent, forHTTPHeaderField: "User-Agent")
        Request.setValue("https://steamrip.com/", forHTTPHeaderField: "Referer")
        let (Data, RawResponse) = try await URLSession.shared.data(for: Request)
        guard let Response = RawResponse as? HTTPURLResponse, (200..<300).contains(Response.statusCode) else {
            throw AppFailure.Message("MegaDB could not load its download page.")
        }
        let HTML = String(decoding: Data, as: UTF8.self)
        guard let Address = Capture(#"var\s+finalDownloadUrl\s*=\s*['"]([^'"]+)['"]"#, Text: HTML),
              let Direct = URL(string: Address.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: Link)?.absoluteURL,
              ["https", "http"].contains(Direct.scheme?.lowercased() ?? ""), Direct.host == Link.host else {
            throw AppFailure.Message("MegaDB did not provide a signed download URL.")
        }
        let Seconds = Int(Capture(#"var\s+seconds\s*=\s*(\d+)"#, Text: HTML) ?? "10") ?? 10
        try await Task.sleep(for: .seconds(min(30, max(0, Seconds) + 2)))
        try Task.checkCancellation()
        let Name = Capture(#"<meta\s+name=["']description["']\s+content=["']Download file - ([^"']+)["']"#, Text: HTML)
            .map(CatalogText.Clean)
        return ResolvedDownload(URL: Direct, FileName: Name,
            Headers: ["User-Agent": BrowserUserAgent, "Referer": Link.absoluteString],
            Cookies: SessionCookies(for: Link, response: Response))
    }

    private static func SessionCookies(for Link: URL, response: HTTPURLResponse) -> [DownloadCookie] {
        let Headers = Dictionary(uniqueKeysWithValues: response.allHeaderFields.map { (String(describing: $0.key), String(describing: $0.value)) })
        let SetCookies = HTTPCookie.cookies(withResponseHeaderFields: Headers, for: Link)
        SetCookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
        return (HTTPCookieStorage.shared.cookies(for: Link) ?? SetCookies).compactMap(DownloadCookie.init)
    }

    private static func Gofile(Link: URL) async throws -> [ResolvedDownload] {
        guard Link.scheme == "https", Link.user == nil, Link.password == nil,
              let Id = Capture(#"^/d/([A-Za-z0-9_-]+)/?$"#, Text: Link.path) else {
            throw AppFailure.Message("Expected a GOFile sharing URL in the form https://gofile.io/d/CONTENT_ID.")
        }
        let Secret: String
        if let (Data, Response) = try? await URLSession.shared.data(from: URL(string: "https://api.ascendara.app/app/json/gofilesecret")!),
           (Response as? HTTPURLResponse)?.statusCode == 200,
           let Payload = try? JSONSerialization.jsonObject(with: Data) as? [String: Any],
           let Live = Payload["secret"] as? String, !Live.isEmpty {
            Secret = Live
        } else { Secret = "f4s58gs6" }
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
                Files.append(ResolvedDownload(URL: URL, FileName: Name,
                    Headers: ["User-Agent": "Mozilla/5.0", "Referer": "https://gofile.io/", "Origin": "https://gofile.io"]))
            }
        }
        guard !Files.isEmpty else { throw AppFailure.Message("The GOFile folder does not contain downloadable files.") }
        guard let Cookie = HTTPCookie(properties: [.domain: ".gofile.io", .path: "/", .name: "accountToken", .value: Token, .secure: "TRUE"]),
              let ScopedCookie = DownloadCookie(Cookie) else {
            throw AppFailure.Message("GOFile issued an unusable download session.")
        }
        for Index in Files.indices { Files[Index].Cookies = [ScopedCookie] }
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
        guard (200..<300).contains(Status) else { throw AppFailure.Message("GOFile returned HTTP \(Status). Ascendara will try another mirror if one is available.") }
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


@MainActor
final class HeadlessBuzzResolver: NSObject, WKNavigationDelegate {
    private static var Active: [UUID: HeadlessBuzzResolver] = [:]
    private static let DataStore = WKWebsiteDataStore(forIdentifier:
        UUID(uuidString: "254A2F6F-01DF-4D16-B63C-3F7A059D6728")!)

    static func Resolve(Link: URL) async throws -> ResolvedDownload {
        try await withCheckedThrowingContinuation { Continuation in
            let Resolver = HeadlessBuzzResolver(Link: Link, Continuation: Continuation)
            Active[Resolver.Id] = Resolver
            Resolver.Start()
        }
    }

    private let Id = UUID()
    private let Link: URL
    private let WebView: WKWebView
    private var Continuation: CheckedContinuation<ResolvedDownload, Error>?
    private var PollTimer: Timer?
    private var Checking = false
    private var StartedAt = Date()

    private init(Link: URL, Continuation: CheckedContinuation<ResolvedDownload, Error>) {
        self.Link = Link
        self.Continuation = Continuation
        let Configuration = WKWebViewConfiguration()
        Configuration.websiteDataStore = Self.DataStore
        Configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        WebView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1), configuration: Configuration)
        super.init()
        WebView.navigationDelegate = self
    }

    private func Start() {
        StartedAt = Date()
        var Request = URLRequest(url: Link)
        Request.setValue("https://steamrip.com/", forHTTPHeaderField: "Referer")
        WebView.load(Request)
        let TimerValue = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.Poll() }
        }
        PollTimer = TimerValue
        RunLoop.main.add(TimerValue, forMode: .common)
    }

    func webView(_ WebView: WKWebView, didFinish Navigation: WKNavigation!) { Poll() }

    private func Poll() {
        guard Continuation != nil else { return }
        if Date().timeIntervalSince(StartedAt) > 35 {
            Finish(.failure(AppFailure.Message("Buzzheavier did not provide a direct file link. Ascendara will try another mirror.")))
            return
        }
        guard !Checking else { return }
        Checking = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.Checking = false }
            let Script = """
            const element = Array.from(document.querySelectorAll('[hx-get]'))
                .find(node => (node.getAttribute('hx-get') || '').includes('/download?t='));
            if (!element) return {ready: false};
            const endpoint = new URL(element.getAttribute('hx-get'), location.href).href;
            const response = await fetch(endpoint, {
                method: 'HEAD', credentials: 'include',
                headers: {'hx-request': 'true', 'hx-current-url': location.href}
            });
            return {ready: true, target: response.headers.get('hx-redirect'),
                    title: document.title, agent: navigator.userAgent};
            """
            guard let Result = try? await self.WebView.callAsyncJavaScript(Script, arguments: [:], in: nil, contentWorld: .page) as? [String: Any],
                  Result["ready"] as? Bool == true,
                  let Target = Result["target"] as? String,
                  let Direct = URL(string: Target, relativeTo: self.Link)?.absoluteURL,
                  ["https", "http"].contains(Direct.scheme?.lowercased() ?? ""),
                  Direct.host != nil, Direct.user == nil, Direct.password == nil,
                  Direct != self.Link else { return }
            let Cookies = await withCheckedContinuation { (Continuation: CheckedContinuation<[HTTPCookie], Never>) in
                self.WebView.configuration.websiteDataStore.httpCookieStore.getAllCookies { Continuation.resume(returning: $0) }
            }
            let Headers = ["User-Agent": (Result["agent"] as? String) ?? "Mozilla/5.0",
                           "Referer": self.Link.absoluteString]
            self.Finish(.success(ResolvedDownload(URL: Direct, FileName: Result["title"] as? String,
                                                  Headers: Headers, Cookies: Cookies.compactMap(DownloadCookie.init))))
        }
    }

    private func Finish(_ Result: Result<ResolvedDownload, Error>) {
        guard let Continuation else { return }
        self.Continuation = nil
        PollTimer?.invalidate()
        PollTimer = nil
        WebView.stopLoading()
        WebView.navigationDelegate = nil
        Self.Active.removeValue(forKey: Id)
        Continuation.resume(with: Result)
    }
}
