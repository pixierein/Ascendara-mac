import Foundation
import Observation
import AscendaraCore

struct AppLanguage: Decodable, Identifiable {
    let Id: String
    let Name: String
    let NativeName: String
    let Bundled: Bool
    var id: String { Id }
    enum CodingKeys: String, CodingKey { case Id = "id", Name = "name", NativeName = "nativeName", Bundled = "bundled" }
}

@Observable
private final class I18nState {
    var Language = ""
    var Strings: [String: String] = [:]
    var English: [String: String] = [:]
    var EnglishKeys: [String: String] = [:]
    var Templates: [String: (Key: String, Names: [String])] = [:]
}

enum I18n {
    private static let State = I18nState()
    static let Languages: [AppLanguage] = {
        struct Index: Decodable {
            let Languages: [AppLanguage]
            enum CodingKeys: String, CodingKey { case Languages = "languages" }
        }
        guard let File = Resource("Languages"), let Data = try? Data(contentsOf: File),
              let Index = try? JSONDecoder().decode(Index.self, from: Data) else { return [] }
        return Index.Languages.sorted { $0.NativeName.localizedStandardCompare($1.NativeName) == .orderedAscending }
    }()

    static var IsRTL: Bool { ["ar", "fa", "he", "iw", "ur", "ps", "sd", "yi"].contains(State.Language) }

    static func IsInstalled(_ Code: String) -> Bool {
        Resource(Code) != nil || FileManager.default.fileExists(atPath: Imported(Code).path)
    }

    static func Use(_ Code: String, Force: Bool = false) {
        guard Force || State.Language != Code else { return }
        if State.English.isEmpty {
            State.English = Load("en")
            for Key in State.English.keys.sorted(by: { Left, Right in
                if Left.hasPrefix("common.") != Right.hasPrefix("common.") { return Left.hasPrefix("common.") }
                return Left < Right
            }) {
                let Normal = TranslationCatalog.Normalize(State.English[Key] ?? "")
                if State.EnglishKeys[Normal] == nil { State.EnglishKeys[Normal] = Key }
                if let Expression = try? NSRegularExpression(pattern: #"\{\{([^}]+)\}\}"#) {
                    let English = State.English[Key] ?? ""
                    let Matches = Expression.matches(in: English, range: NSRange(English.startIndex..., in: English))
                    var Pattern = English
                    var Names: [String] = []
                    for Match in Matches {
                        guard let Range = Range(Match.range(at: 1), in: English) else { continue }
                        Names.append(String(English[Range]))
                    }
                    for (Index, Match) in Matches.enumerated().reversed() {
                        if let Range = Range(Match.range, in: Pattern) { Pattern.replaceSubrange(Range, with: "{{\(Index)}}") }
                    }
                    if !Names.isEmpty { State.Templates[TranslationCatalog.Normalize(Pattern)] = (Key, Names) }
                }
            }
        }
        State.Language = Code
        State.Strings = Load(Code)
    }

    static func T(_ Text: String, Values: [String: String] = [:]) -> String {
        if ["Ascendara", "Ascend", "TorBox", "Highball", "Steam", "SteamCMD", "RetroArch"].contains(Text) { return Text }
        let Key = State.English[Text] != nil ? Text : State.EnglishKeys[TranslationCatalog.Normalize(Text)] ?? Text
        return TranslationCatalog.Render(State.Strings[Key] ?? State.English[Key] ?? Text, Values: Values)
    }

    static func Interpolated(_ Message: I18nMessage) -> String {
        let Template = State.Templates[TranslationCatalog.Normalize(Message.Pattern)]
        var Values: [String: String] = [:]
        for (Index, Value) in Message.Values.enumerated() {
            Values[String(Index)] = Value
            if let Template, Index < Template.Names.count { Values[Template.Names[Index]] = Value }
        }
        return T(Template?.Key ?? Message.Pattern, Values: Values)
    }

    static func Import(_ File: URL, Code: String) throws {
        guard Languages.contains(where: { $0.Id == Code }), File.isFileURL else { throw AppFailure.Message("Choose a supported language and its i18next JSON file.") }
        let Data = try Data(contentsOf: File)
        guard Data.count < 10_000_000, let Object = try JSONSerialization.jsonObject(with: Data) as? [String: Any],
              !TranslationCatalog.Flatten(Object).isEmpty else { throw AppFailure.Message("The translation file must contain an i18next JSON object.") }
        try RuntimePaths.CreateDirectory(Imported(Code).deletingLastPathComponent())
        try Data.write(to: Imported(Code), options: .atomic)
        if State.Language == Code { Use(Code, Force: true) }
    }

    static func Export(_ Code: String, To File: URL) throws {
        let Object = Load(Code)
        try JSONSerialization.data(withJSONObject: Object, options: [.prettyPrinted, .sortedKeys]).write(to: File, options: .atomic)
    }

    private static func Resource(_ Name: String) -> URL? {
        AppResources.Bundle.url(forResource: Name, withExtension: "json", subdirectory: "Translations")
            ?? AppResources.Bundle.url(forResource: Name, withExtension: "json")
    }

    private static func Imported(_ Code: String) -> URL {
        AppPaths.Support.appendingPathComponent("Translations").appendingPathComponent(Code + ".json")
    }

    private static func Load(_ Code: String) -> [String: String] {
        var Result: [String: String] = [:]
        for File in [Resource(Code), Imported(Code)] .compactMap({ $0 }) {
            if let Data = try? Data(contentsOf: File), let Object = (try? JSONSerialization.jsonObject(with: Data)) as? [String: Any] {
                Result.merge(TranslationCatalog.Flatten(Object)) { _, New in New }
            }
        }
        return Result
    }
}

struct I18nMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let Pattern: String
    let Values: [String]
    init(stringLiteral Value: String) { Pattern = Value; Values = [] }
    init(stringInterpolation Value: StringInterpolation) { Pattern = Value.Pattern; Values = Value.Values }

    struct StringInterpolation: StringInterpolationProtocol {
        var Pattern = ""
        var Values: [String] = []
        init(literalCapacity LiteralCapacity: Int, interpolationCount InterpolationCount: Int) {
            Pattern.reserveCapacity(LiteralCapacity); Values.reserveCapacity(InterpolationCount)
        }
        mutating func appendLiteral(_ Literal: String) { Pattern += Literal }
        mutating func appendInterpolation<Value>(_ Value: Value) {
            Pattern += "{{\(Values.count)}}"; Values.append(String(describing: Value))
        }
        mutating func appendInterpolation<Value: CVarArg>(_ Value: Value, specifier: String) {
            Pattern += "{{\(Values.count)}}"; Values.append(String(format: specifier, Value))
        }
    }
}
