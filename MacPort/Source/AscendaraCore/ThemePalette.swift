import Foundation

public struct ThemePalette: Codable, Equatable {
    public var Name: String
    public var Dark: Bool
    public var Colors: [String]

    public init(Name: String, Dark: Bool, Colors: [String]) {
        self.Name = Name
        self.Dark = Dark
        self.Colors = Colors
    }

    public func Validate() throws {
        guard !Name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, Name.count <= 80,
              Colors.count == 8, Colors.allSatisfy({ $0.range(of: #"^#[0-9a-fA-F]{6}$"#, options: .regularExpression) != nil }) else {
            throw CocoaError(.coderInvalidValue)
        }
    }
}
