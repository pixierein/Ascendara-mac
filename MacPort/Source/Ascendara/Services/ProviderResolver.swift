import AppKit
import WebKit

@MainActor
final class ProviderResolver: NSObject, WKNavigationDelegate, WKDownloadDelegate, WKUIDelegate, NSWindowDelegate {
    private static var Active: [UUID: ProviderResolver] = [:]
    private static let DataStore = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "FCE27595-B1A1-4DAC-9487-FAD829575ECE")!)
    private let Id = UUID()
    private let Link: URL
    private let WebView: WKWebView
    private let Window: NSWindow
    private var Continuation: CheckedContinuation<ResolvedDownload, Error>?
    private var Timeout: Task<Void, Never>?

    private init(Link: URL, Continuation: CheckedContinuation<ResolvedDownload, Error>) {
        self.Link = Link
        self.Continuation = Continuation
        let Configuration = WKWebViewConfiguration()
        Configuration.websiteDataStore = Self.DataStore
        WebView = WKWebView(frame: .zero, configuration: Configuration)
        Window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 850, height: 650),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        Window.title = "Complete the download step · \(Link.host ?? "Provider")"
        Window.isReleasedWhenClosed = false
        Window.contentView = WebView
        Window.delegate = self
        WebView.navigationDelegate = self
        WebView.uiDelegate = self
    }

    static func Resolve(Link: URL) async throws -> ResolvedDownload {
        try await withCheckedThrowingContinuation { Continuation in
            let Resolver = ProviderResolver(Link: Link, Continuation: Continuation)
            Active[Resolver.Id] = Resolver
            Resolver.Window.center()
            Resolver.Window.makeKeyAndOrderFront(nil)
            Resolver.WebView.load(URLRequest(url: Link))
            Resolver.Timeout = Task { [weak Resolver] in
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled else { return }
                Resolver?.Finish(.failure(AppFailure.Message("The provider step timed out. Choose another mirror or retry.")))
            }
        }
    }

    func windowWillClose(_ Notification: Notification) {
        Finish(.failure(CancellationError()))
    }

    func webView(_ WebView: WKWebView, decidePolicyFor NavigationAction: WKNavigationAction,
                 decisionHandler DecisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let Address = NavigationAction.request.url,
              ["http", "https", "about"].contains(Address.scheme?.lowercased() ?? "") else { DecisionHandler(.cancel); return }
        DecisionHandler(NavigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ WebView: WKWebView, decidePolicyFor NavigationResponse: WKNavigationResponse,
                 decisionHandler DecisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let Response = NavigationResponse.response
        let MIME = Response.mimeType?.lowercased() ?? ""
        let Disposition = (Response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if NavigationResponse.isForMainFrame, Disposition.contains("attachment") || (!MIME.isEmpty && !MIME.contains("html") && !MIME.contains("json") && !MIME.hasPrefix("image/") && !MIME.hasPrefix("text/")) {
            DecisionHandler(.cancel)
            Capture(Response, FileName: Response.suggestedFilename)
        } else { DecisionHandler(.allow) }
    }

    func webView(_ WebView: WKWebView, navigationAction NavigationAction: WKNavigationAction, didBecome Download: WKDownload) { Download.delegate = self }
    func webView(_ WebView: WKWebView, navigationResponse NavigationResponse: WKNavigationResponse, didBecome Download: WKDownload) { Download.delegate = self }

    func download(_ Download: WKDownload, decideDestinationUsing Response: URLResponse, suggestedFilename SuggestedFilename: String,
                  completionHandler CompletionHandler: @escaping (URL?) -> Void) {
        CompletionHandler(nil)
        Capture(Response, FileName: SuggestedFilename)
    }

    func webView(_ WebView: WKWebView, createWebViewWith Configuration: WKWebViewConfiguration,
                 for NavigationAction: WKNavigationAction, windowFeatures WindowFeatures: WKWindowFeatures) -> WKWebView? {
        if let Address = NavigationAction.request.url, ["http", "https"].contains(Address.scheme?.lowercased() ?? "") {
            WebView.load(NavigationAction.request)
        }
        return nil
    }

    private func Capture(_ Response: URLResponse, FileName: String?) {
        guard let Address = Response.url, ["http", "https"].contains(Address.scheme?.lowercased() ?? ""),
              let HTTP = Response as? HTTPURLResponse, (200..<300).contains(HTTP.statusCode) else { return }
        Task {
            let Cookies = await withCheckedContinuation { (Continuation: CheckedContinuation<[HTTPCookie], Never>) in
                WebView.configuration.websiteDataStore.httpCookieStore.getAllCookies { Continuation.resume(returning: $0) }
            }
            let Agent = (try? await WebView.evaluateJavaScript("navigator.userAgent")) as? String ?? "Mozilla/5.0"
            Finish(.success(ResolvedDownload(URL: Address, FileName: FileName,
                Headers: ["User-Agent": Agent, "Referer": WebView.url?.absoluteString ?? Link.absoluteString],
                Cookies: Cookies.compactMap(DownloadCookie.init))))
        }
    }

    private func Finish(_ Result: Result<ResolvedDownload, Error>) {
        guard let Continuation else { return }
        self.Continuation = nil
        Timeout?.cancel()
        WebView.stopLoading()
        Window.delegate = nil
        Window.close()
        Self.Active.removeValue(forKey: Id)
        Continuation.resume(with: Result)
    }
}
