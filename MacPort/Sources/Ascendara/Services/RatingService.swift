import Foundation

struct GameReview: Identifiable, Sendable {
    var Id: String
    var Username: String
    var Comments: String
    var Rating: Double
    var CreatedAt: String?
    var IsGuest: Bool
    var id: String { Id }
}

struct GameRating: Sendable {
    var Average: Double
    var Count: Int
    var Reviews: [GameReview]
}

actor RatingService {
    static let Shared = RatingService()
    private var Cached: [String: (Date, GameRating)] = [:]

    func Load(GameId: String, Force: Bool = false) async throws -> GameRating {
        if !Force, let Entry = Cached[GameId], Date().timeIntervalSince(Entry.0) < 1800 { return Entry.1 }
        let URL = URL(string: "https://api.ascendara.app/app/v2/gamerating")!.appendingPathComponent(GameId)
        let (Data, Response) = try await URLSession.shared.data(for: URLRequest(url: URL, timeoutInterval: 30))
        let Status = (Response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(Status) else { throw CatalogError.HTTP(Status) }
        let Rating = try Self.Decode(Data: Data)
        Cached[GameId] = (Date(), Rating)
        return Rating
    }

    static func Decode(Data: Data) throws -> GameRating {
        guard let Root = try JSONSerialization.jsonObject(with: Data) as? [String: Any], Root["rating"] != nil else { throw CatalogError.InvalidResponse }
        let Average = (Root["rating"] as? NSNumber)?.doubleValue ?? Double(Root["rating"] as? String ?? "") ?? 0
        let Count = (Root["ratingCount"] as? NSNumber)?.intValue ?? Int(Root["ratingCount"] as? String ?? "") ?? 0
        let Reviews = (Root["reviews"] as? [[String: Any]] ?? []).compactMap { Item -> GameReview? in
            guard let Comments = Item["comments"] as? String, !Comments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let Name = (Item["username"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let Account = Item["isAscendAccount"] as? Bool
            let IsGuest = Name.isEmpty || Account == false || (Account != true && Name.range(of: #"^Anonymous(?: \d+)?$"#, options: .regularExpression) != nil)
            let CreatedAt = Item["createdAt"] as? String
            let Id = (Item["id"] as? String) ?? CatalogText.StableId("\(Name):\(CreatedAt ?? ""):\(Comments)")
            let Value = (Item["rating"] as? NSNumber)?.doubleValue ?? Double(Item["rating"] as? String ?? "") ?? 0
            return GameReview(Id: Id, Username: IsGuest ? "Anonymous player" : Name, Comments: Comments, Rating: max(0, min(5, Value)), CreatedAt: CreatedAt, IsGuest: IsGuest)
        }.sorted { !$0.IsGuest && $1.IsGuest }
        return GameRating(Average: max(0, min(5, Average)), Count: max(0, Count), Reviews: Reviews)
    }
}
