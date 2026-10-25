import Foundation

public enum TranslationCatalog {
    public static func Flatten(_ Object: [String: Any], Prefix: String = "") -> [String: String] {
        var Result: [String: String] = [:]
        for (Key, Value) in Object {
            let Path = Prefix.isEmpty ? Key : Prefix + "." + Key
            if let Text = Value as? String { Result[Path] = Text }
            else if let Nested = Value as? [String: Any] { Result.merge(Flatten(Nested, Prefix: Path)) { _, New in New } }
        }
        return Result
    }

    public static func Normalize(_ Text: String) -> String {
        Text.lowercased().replacingOccurrences(of: "…", with: "...")
            .replacingOccurrences(of: #"[^\p{L}\p{N}{}]+"#, with: "", options: .regularExpression)
    }

    public static func Render(_ Text: String, Values: [String: String]) -> String {
        var Result = Text
        for (Key, Value) in Values { Result = Result.replacingOccurrences(of: "{{" + Key + "}}", with: Value) }
        return Result
    }
}
