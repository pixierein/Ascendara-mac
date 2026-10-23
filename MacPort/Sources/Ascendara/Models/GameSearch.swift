import Foundation

enum CatalogSort: String, CaseIterable, Identifiable, Sendable {
    case Popular = "Most popular"
    case Name = "Name A–Z"
    case Recent = "Recently updated"
    case Smallest = "Smallest size"
    var id: String { rawValue }
}

enum GameSearch {
    static func Filter(Games: [Game], Query: String = "", Categories: Set<String> = [], Sort: CatalogSort = .Popular,
                       OnlineOnly: Bool = false, DlcOnly: Bool = false, MaximumSizeGB: Double? = nil,
                       Provider: String? = nil, VerifiedIds: Set<String>? = nil) -> [Game] {
        let Search = Query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Games.filter { Game in
            (Search.isEmpty || Matches(Text: Game.Name, Query: Search)) &&
            (Categories.isEmpty || Categories.isSubset(of: Set(Game.Categories))) &&
            (!OnlineOnly || Game.Online) && (!DlcOnly || Game.Dlc) &&
            (MaximumSizeGB == nil || Game.SizeGB <= MaximumSizeGB!) &&
            (Provider == nil || Game.DownloadLinks[Provider!] != nil) &&
            (VerifiedIds == nil || VerifiedIds!.contains(Game.Id))
        }.sorted { Left, Right in
            switch Sort {
            case .Popular:
                if Left.Weight != Right.Weight { return (Left.Weight ?? 0) > (Right.Weight ?? 0) }
            case .Recent:
                if Left.LatestUpdate != Right.LatestUpdate { return (Left.LatestUpdate ?? "") > (Right.LatestUpdate ?? "") }
            case .Smallest:
                if Left.SizeGB != Right.SizeGB { return Left.SizeGB < Right.SizeGB }
            case .Name: break
            }
            return Left.Name.localizedStandardCompare(Right.Name) == .orderedAscending
        }
    }

    static func Matches(Text: String, Query: String) -> Bool {
        let Text = Text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let Query = Query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if Text.contains(Query) { return true }
        let Words = Text.split(whereSeparator: { $0.isWhitespace })
        return Query.split(whereSeparator: { $0.isWhitespace }).allSatisfy { QueryWord in
            if QueryWord.contains(where: { $0.isNumber }) { return Text.contains(QueryWord) }
            return Words.contains { Word in
                if Word.contains(QueryWord) { return true }
                if Word.contains(where: { $0.isNumber }) { return false }
                var Position = Word.startIndex
                var Count = 0
                for Character in QueryWord {
                    if Position < Word.endIndex, let Found = Word[Position...].firstIndex(of: Character) {
                        Count += 1; Position = Word.index(after: Found)
                    }
                }
                return Double(Count) >= Double(QueryWord.count) * 0.8
            }
        }
    }
}
