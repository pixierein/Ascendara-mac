import Foundation

enum DeepLink: Equatable {
    case Game(String), Search(String), Library, Downloads, Ascend, ShowWindow

    static func Parse(_ URL: URL) -> DeepLink? {
        guard ["ascendara", "ascendara-native"].contains(URL.scheme?.lowercased() ?? "") else { return nil }
        let Parts = URLComponents(url: URL, resolvingAgainstBaseURL: false)
        switch URL.host?.lowercased() {
        case "game":
            let Id = Parts?.queryItems?.first { ["id", "game", "gameID"].contains($0.name) }?.value
                ?? (URL.path.isEmpty || URL.path == "/" ? Parts?.queryItems?.first?.name : URL.lastPathComponent)
            guard let Id, Id.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { return nil }
            return .Game(Id)
        case "search": return .Search(Parts?.queryItems?.first { $0.name == "q" }?.value ?? "")
        case "library": return .Library
        case "downloads": return .Downloads
        case "checkout-success", "checkout-canceled": return .Ascend
        case "show-window": return .ShowWindow
        default: return nil
        }
    }
}
