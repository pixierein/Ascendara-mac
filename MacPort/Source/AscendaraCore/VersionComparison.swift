import Foundation

public enum VersionComparison {
    public static func Normalize(_ Value: String) -> String {
        var Result = Value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if Result.first == "v", Result.dropFirst().first?.isNumber == true { Result.removeFirst() }
        return Result
    }

    public static func IsNewer(_ Latest: String, than Installed: String) -> Bool {
        func Parts(_ Value: String) -> [UInt64]? {
            let Normal = Normalize(Value).replacingOccurrences(of: #"^build\s*"#, with: "", options: .regularExpression)
            guard Normal.range(of: #"^[0-9]+(?:[.\-_][0-9]+)*$"#, options: .regularExpression) != nil else { return nil }
            let Pieces = Normal.split(whereSeparator: { !$0.isNumber })
            let Result = Pieces.compactMap { UInt64($0) }
            return Result.count == Pieces.count ? Result : nil
        }
        guard let Left = Parts(Latest), let Right = Parts(Installed) else { return false }
        for Index in 0..<max(Left.count, Right.count) {
            let L = Index < Left.count ? Left[Index] : 0, R = Index < Right.count ? Right[Index] : 0
            if L != R { return L > R }
        }
        return false
    }
}
