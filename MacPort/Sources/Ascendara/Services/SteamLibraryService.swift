import Foundation

struct SteamLibraryEntry: Identifiable {
    var Id: String
    var Name: String
    var InstallURL: URL
    var ExecutableURL: URL?
    var id: String { Id }
}

enum SteamLibraryService {
    static func Scan() throws -> [SteamLibraryEntry] {
        let Steam = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Steam")
        return try Scan(SteamDirectory: Steam)
    }

    static func Scan(SteamDirectory: URL) throws -> [SteamLibraryEntry] {
        var Libraries = Set([SteamDirectory])
        let Folders = SteamDirectory.appendingPathComponent("steamapps/libraryfolders.vdf")
        if let Text = try? String(contentsOf: Folders, encoding: .utf8) {
            let Pattern = #""path"\s*"((?:\\.|[^"\\])*)""#
            let Regex = try NSRegularExpression(pattern: Pattern, options: .caseInsensitive)
            for Match in Regex.matches(in: Text, range: NSRange(Text.startIndex..., in: Text)) {
                if let Range = Range(Match.range(at: 1), in: Text) {
                    Libraries.insert(URL(fileURLWithPath: String(Text[Range]).replacingOccurrences(of: "\\\\", with: "\\")))
                }
            }
        }
        var Entries: [SteamLibraryEntry] = []
        for Library in Libraries {
            let Apps = Library.appendingPathComponent("steamapps")
            guard FileManager.default.fileExists(atPath: Apps.path) else { continue }
            for Manifest in try FileManager.default.contentsOfDirectory(at: Apps, includingPropertiesForKeys: nil)
                where Manifest.lastPathComponent.hasPrefix("appmanifest_") && Manifest.pathExtension == "acf" {
                guard let Text = try? String(contentsOf: Manifest, encoding: .utf8), let Id = Value("appid", Text: Text),
                      let Name = Value("name", Text: Text), let Directory = Value("installdir", Text: Text) else { continue }
                let InstallURL = Apps.appendingPathComponent("common", isDirectory: true).appendingPathComponent(Directory, isDirectory: true)
                guard FileManager.default.fileExists(atPath: InstallURL.path) else { continue }
                Entries.append(SteamLibraryEntry(Id: Id, Name: Name, InstallURL: InstallURL, ExecutableURL: FindExecutable(Directory: InstallURL)))
            }
        }
        var Seen: Set<String> = []
        return Entries.filter { Seen.insert($0.Id).inserted }.sorted { $0.Name.localizedStandardCompare($1.Name) == .orderedAscending }
    }

    private static func Value(_ Key: String, Text: String) -> String? {
        let Pattern = "\"\(NSRegularExpression.escapedPattern(for: Key))\"\\s*\"((?:\\\\.|[^\"\\\\])*)\""
        guard let Regex = try? NSRegularExpression(pattern: Pattern, options: .caseInsensitive),
              let Match = Regex.firstMatch(in: Text, range: NSRange(Text.startIndex..., in: Text)),
              let Range = Range(Match.range(at: 1), in: Text) else { return nil }
        return String(Text[Range]).replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func FindExecutable(Directory: URL) -> URL? {
        guard let Files = FileManager.default.enumerator(at: Directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
        var Windows: [URL] = []
        var Native: [URL] = []
        for case let File as URL in Files {
            if File.pathExtension.lowercased() == "app" { return File }
            if Files.level > 3 { Files.skipDescendants(); continue }
            let Name = File.lastPathComponent.lowercased()
            if Name.hasSuffix(".exe"), !["unins", "setup", "crash", "redist"].contains(where: Name.contains) { Windows.append(File) }
            if File.pathExtension.isEmpty, FileManager.default.isExecutableFile(atPath: File.path),
               (try? File.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false { Native.append(File) }
        }
        return Native.sorted { $0.path.count < $1.path.count }.first ?? Windows.sorted { $0.path.count < $1.path.count }.first
    }
}
