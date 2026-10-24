import Foundation
import Darwin

private struct Job: Decodable {
    let Id: UUID
    let SourceURL: URL
    let GameName: String
    let DownloadDirectory: URL
    let QBitTorrentURL: URL
    let Username: String
    let Password: String
    let EstimatedSizeBytes: Int64?
    let SpeedLimitBytesPerSecond: Int64?
}

private struct Status: Codable {
    var State: String
    var Progress: Double = 0
    var Speed: Int64 = 0
    var ETA: Int64 = 0
    var TorrentHash: String?
    var ResultDirectory: String?
    var ManualInstaller: String?
    var ErrorMessage: String?
    var PID: Int32 = getpid()
}

private enum HandlerError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

private final class Handler {
    let job: Job
    let directory: URL
    let manager = FileManager.default
    let session = URLSession(configuration: .ephemeral)
    let gameDirectory: URL
    let statusURL: URL
    let controlURL: URL
    var status = Status(State: "Connecting")

    init(job: Job, directory: URL) throws {
        self.job = job
        self.directory = directory
        statusURL = directory.appendingPathComponent("status.json")
        controlURL = directory.appendingPathComponent("control.txt")
        let name = Self.safeName(job.GameName)
        guard !name.isEmpty else { throw HandlerError.message("The game needs a valid folder name.") }
        gameDirectory = job.DownloadDirectory.appendingPathComponent(name, isDirectory: true)
    }

    func run() async throws {
        guard ["magnet", "http", "https"].contains(job.SourceURL.scheme?.lowercased() ?? ""),
              ["http", "https"].contains(job.QBitTorrentURL.scheme?.lowercased() ?? ""),
              job.QBitTorrentURL.host != nil else {
            throw HandlerError.message("A torrent or qBittorrent URL is invalid.")
        }
        try manager.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        if let required = job.EstimatedSizeBytes, required > 0 { try checkSpace(gameDirectory, required: required) }
        try await login()
        let prior = (try? Data(contentsOf: statusURL)).flatMap { try? JSONDecoder().decode(Status.self, from: $0) }
        var hash = prior?.TorrentHash
        if hash == nil {
            let before = Set(try await torrentList().compactMap { $0["hash"] as? String })
            status.State = "Registering"
            writeStatus()
            let body = multipart(["urls": job.SourceURL.absoluteString, "savepath": gameDirectory.path,
                                  "sequentialDownload": "true"])
            let result = try await request("torrents/add", body: body.data, contentType: body.contentType)
            guard String(decoding: result, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ok." else {
                throw HandlerError.message("qBittorrent did not accept the torrent.")
            }
            let expected = Self.magnetHash(job.SourceURL)
            for _ in 0..<30 {
                let list = try await torrentList()
                hash = list.first(where: { item in
                    guard let candidate = item["hash"] as? String else { return false }
                    if let expected { return candidate.lowercased() == expected }
                    return !before.contains(candidate) && (item["save_path"] as? String) == gameDirectory.path
                })?["hash"] as? String
                if hash != nil { break }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            guard let hash else { throw HandlerError.message("The torrent did not register in qBittorrent.") }
            status.TorrentHash = hash
            writeStatus()
            if let limit = job.SpeedLimitBytesPerSecond, limit > 0 {
                _ = try await request("torrents/setDownloadLimit", body: form(["hashes": hash, "limit": String(limit)]))
            }
        }
        guard let hash else { throw HandlerError.message("The torrent has no hash.") }
        status.TorrentHash = hash
        if prior?.State == "Paused", command() == nil { try await controlTorrent(hash, operation: "start") }
        while true {
            if let command = command() {
                if command == "pause" {
                    try await controlTorrent(hash, operation: "stop")
                    status.State = "Paused"
                } else {
                    _ = try await request("torrents/delete", body: form(["hashes": hash, "deleteFiles": "true"]))
                    status.State = "Cancelled"
                }
                status.Speed = 0
                writeStatus()
                return
            }
            guard let item = try await torrentList().first(where: { ($0["hash"] as? String)?.lowercased() == hash.lowercased() }) else {
                throw HandlerError.message("qBittorrent removed the torrent before it completed.")
            }
            let progress = (item["progress"] as? NSNumber)?.doubleValue ?? 0
            status.Progress = min(1, max(0, progress))
            status.Speed = (item["dlspeed"] as? NSNumber)?.int64Value ?? 0
            status.ETA = (item["eta"] as? NSNumber)?.int64Value ?? 0
            status.State = progress >= 0.99999 ? "Finalizing" : (status.Speed > 0 ? "Downloading" : "Waiting")
            writeStatus()
            if progress >= 0.99999 {
                try await waitForRelease(hash)
                try install(item)
                status.Progress = 1
                status.Speed = 0
                status.ETA = 0
                status.State = status.ManualInstaller == nil ? "Completed" : "ManualInstallRequired"
                writeStatus()
                return
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    func fail(_ error: Error) {
        status.State = "Failed"
        status.Speed = 0
        status.ErrorMessage = error.localizedDescription
        writeStatus()
    }

    private func login() async throws {
        let result = try await request("auth/login", body: form(["username": job.Username, "password": job.Password]))
        guard String(decoding: result, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "ok." else {
            throw HandlerError.message("qBittorrent authentication failed.")
        }
    }

    private func torrentList() async throws -> [[String: Any]] {
        let result = try await request("torrents/info")
        guard let list = try JSONSerialization.jsonObject(with: result) as? [[String: Any]] else {
            throw HandlerError.message("qBittorrent returned an invalid torrent list.")
        }
        return list
    }

    private func request(_ path: String, body: Data? = nil,
                         contentType: String = "application/x-www-form-urlencoded") async throws -> Data {
        var request = URLRequest(url: job.QBitTorrentURL.appendingPathComponent("api/v2/\(path)"), timeoutInterval: 30)
        request.setValue(job.QBitTorrentURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(job.QBitTorrentURL.absoluteString, forHTTPHeaderField: "Origin")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw HandlerError.message("qBittorrent returned HTTP \(code).") }
        return data
    }

    private func controlTorrent(_ hash: String, operation: String) async throws {
        do { _ = try await request("torrents/\(operation)", body: form(["hashes": hash])) }
        catch {
            // qBittorrent v4 calls these pause/resume, v5 stop/start.
            _ = try await request("torrents/\(operation == "stop" ? "pause" : "resume")", body: form(["hashes": hash]))
        }
    }

    private func waitForRelease(_ hash: String) async throws {
        let unstable: Set<String> = ["checkingup", "checkingdl", "movingfiles", "checkingresumedata", "allocating"]
        for _ in 0..<30 {
            guard let item = try await torrentList().first(where: { ($0["hash"] as? String) == hash }) else { return }
            if !unstable.contains((item["state"] as? String ?? "").lowercased()) { return }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func install(_ item: [String: Any]) throws {
        let path = (item["content_path"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (item["save_path"] as? String) ?? gameDirectory.path
        let content = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard Self.inside(content, gameDirectory), manager.fileExists(atPath: content.path) else {
            throw HandlerError.message("The torrent files are missing or outside the game download folder.")
        }
        var isDirectory: ObjCBool = false
        manager.fileExists(atPath: content.path, isDirectory: &isDirectory)
        let source = isDirectory.boolValue ? content : content.deletingLastPathComponent()
        let archives = findArchives(source)
        if archives.isEmpty {
            status.ResultDirectory = source.path
            status.ManualInstaller = findSetup(source)?.path
            return
        }
        status.State = "Extracting"
        writeStatus()
        let destination = gameDirectory.appendingPathComponent(Self.safeName(job.GameName) + "-Installed", isDirectory: true)
        guard !manager.fileExists(atPath: destination.path) else {
            throw HandlerError.message("An installed game folder already exists: \(destination.path)")
        }
        let staging = gameDirectory.appendingPathComponent(".ascendara-torrent-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            for (index, archive) in archives.enumerated() {
                if command() != nil { throw HandlerError.message("Installation was stopped; downloaded files were retained.") }
                let part = gameDirectory.appendingPathComponent(".ascendara-part-\(UUID().uuidString)-\(index)", isDirectory: true)
                defer { try? manager.removeItem(at: part) }
                try extract(archive, into: part)
                try merge(part, into: staging)
            }
            try writeFileMap(staging)
            try manager.moveItem(at: staging, to: destination)
            status.ResultDirectory = destination.path
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    private func findArchives(_ source: URL) -> [URL] {
        guard let files = manager.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        var archives: [URL] = []
        for case let file as URL in files where ["zip", "rar", "7z"].contains(file.pathExtension.lowercased()) {
            let name = file.lastPathComponent.lowercased()
            if let range = name.range(of: #"\.part([0-9]+)\.rar$"#, options: .regularExpression),
               let number = Int(name[range].dropFirst(5).dropLast(4)), number != 1 { continue }
            archives.append(file)
        }
        return archives.sorted { size($0) > size($1) }
    }

    private func findSetup(_ source: URL) -> URL? {
        guard let files = manager.enumerator(at: source, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        var installers: [URL] = []
        for case let file as URL in files where file.pathExtension.lowercased() == "exe" {
            if file.lastPathComponent.lowercased().hasPrefix("setup") { installers.append(file) }
        }
        return installers.sorted { $0.pathComponents.count < $1.pathComponents.count }.first
    }

    private func extract(_ archive: URL, into destination: URL) throws {
        let isSevenZip = ["rar", "7z"].contains(archive.pathExtension.lowercased())
        let resourceTool = Bundle.main.executableURL?.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Tools/7zz")
        let tool: URL
        if isSevenZip {
            guard let resourceTool, manager.isExecutableFile(atPath: resourceTool.path) else {
                throw HandlerError.message("The bundled 7-Zip tool is needed to extract this archive.")
            }
            tool = resourceTool
        } else { tool = URL(fileURLWithPath: "/usr/bin/bsdtar") }
        let listing = try run(tool, isSevenZip ? ["l", "-slt", "-ba", "--", archive.path] : ["-tf", archive.path])
        if isSevenZip {
            for line in listing.components(separatedBy: .newlines) where line.hasPrefix("Path = ") {
                try Self.validateArchivePath(String(line.dropFirst(7)))
            }
            if listing.contains("Symbolic Link = ") || listing.contains("Hard Link = ") {
                throw HandlerError.message("The archive contains a link and cannot be extracted automatically.")
            }
        } else {
            for line in listing.components(separatedBy: .newlines) where !line.isEmpty { try Self.validateArchivePath(line) }
        }
        try manager.createDirectory(at: destination, withIntermediateDirectories: false)
        _ = try run(tool, isSevenZip ? ["x", "-y", "-psteamrip.com", "-o" + destination.path, "--", archive.path]
                                     : ["-xf", archive.path, "-C", destination.path, "--no-same-owner", "--no-same-permissions"])
        guard let files = manager.enumerator(at: destination, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) else { return }
        for case let file as URL in files where (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw HandlerError.message("The archive created a link and cannot be installed automatically.")
        }
    }

    private func merge(_ source: URL, into destination: URL) throws {
        guard let files = manager.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return }
        for case let file as URL in files {
            let parent = source.standardizedFileURL.pathComponents
            let components = file.standardizedFileURL.pathComponents
            guard components.starts(with: parent), components.count > parent.count else {
                throw HandlerError.message("An extracted path escaped its staging directory.")
            }
            let relative = components.dropFirst(parent.count).joined(separator: "/")
            try Self.validateArchivePath(relative)
            let target = destination.appendingPathComponent(relative)
            if (try? file.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                try manager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                guard !manager.fileExists(atPath: target.path) else {
                    throw HandlerError.message("Two archives contain the same file: \(relative)")
                }
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try manager.moveItem(at: file, to: target)
            }
        }
    }

    private func writeFileMap(_ root: URL) throws {
        guard let files = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: []) else { return }
        var map: [String: [String: Int64]] = [:]
        for case let file as URL in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let parent = root.standardizedFileURL.pathComponents
            let components = file.standardizedFileURL.pathComponents
            guard components.starts(with: parent), components.count > parent.count else {
                throw HandlerError.message("An installed file escaped its staging directory.")
            }
            let relative = components.dropFirst(parent.count).joined(separator: "/")
            if relative.lowercased().hasSuffix(".url") || relative.lowercased().contains("_commonredist/") { continue }
            map[relative] = ["size": size(file)]
        }
        try JSONEncoder().encode(map).write(to: root.appendingPathComponent("filemap.ascendara.json"), options: .atomic)
    }

    private func run(_ executable: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw HandlerError.message("Archive tool failed: \(String(text.suffix(500)))")
        }
        return text
    }

    private func command() -> String? {
        let value = (try? String(contentsOf: controlURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == "pause" || value == "cancel" ? value : nil
    }

    private func writeStatus() {
        if let data = try? JSONEncoder().encode(status) {
            try? data.write(to: statusURL, options: .atomic)
            _ = chmod(statusURL.path, S_IRUSR | S_IWUSR)
        }
    }

    private func size(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func checkSpace(_ url: URL, required: Int64) throws {
        var info = statvfs()
        guard statvfs(url.path, &info) == 0 else { return }
        if required > Int64(info.f_bavail) * Int64(info.f_frsize) {
            throw HandlerError.message("Insufficient disk space for the torrent download.")
        }
    }

    private func form(_ fields: [String: String]) -> Data {
        fields.map { key, value in
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(key)=\(encoded)"
        }.joined(separator: "&").data(using: .utf8) ?? Data()
    }

    private func multipart(_ fields: [String: String]) -> (data: Data, contentType: String) {
        let boundary = "Ascendara-\(UUID().uuidString)"
        var result = Data()
        for (key, value) in fields {
            result.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n".utf8))
        }
        result.append(Data("--\(boundary)--\r\n".utf8))
        return (result, "multipart/form-data; boundary=\(boundary)")
    }

    private static func safeName(_ value: String) -> String {
        let excluded = CharacterSet(charactersIn: "/\\:\0\r\n")
        let cleaned = value.components(separatedBy: excluded).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(120))
    }

    private static func inside(_ candidate: URL, _ root: URL) -> Bool {
        let path = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        return path == base || path.hasPrefix(base + "/")
    }

    private static func validateArchivePath(_ path: String) throws {
        let normal = path.replacingOccurrences(of: "\\", with: "/")
        if normal.hasPrefix("/") || normal.contains("\0") || normal.components(separatedBy: "/").contains("..") ||
           (normal.count >= 2 && normal[normal.index(after: normal.startIndex)] == ":") {
            throw HandlerError.message("The archive contains an unsafe path: \(path)")
        }
    }

    private static func magnetHash(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "magnet",
              let xt = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "xt" })?.value,
              xt.lowercased().hasPrefix("urn:btih:") else { return nil }
        let value = String(xt.dropFirst("urn:btih:".count)).lowercased()
        if value.count == 40 && value.allSatisfy(\.isHexDigit) { return value }
        if value.count == 32 {
            let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
            var bytes: [UInt8] = []
            var pending = 0
            var bits = 0
            for character in value {
                guard let digit = alphabet.firstIndex(of: character) else { return nil }
                pending = (pending << 5) | digit
                bits += 5
                if bits >= 8 {
                    bits -= 8
                    bytes.append(UInt8((pending >> bits) & 0xff))
                    pending &= (1 << bits) - 1
                }
            }
            if bytes.count == 20 { return bytes.map { String(format: "%02x", $0) }.joined() }
        }
        return nil
    }
}

@main
private enum AscendaraTorrentHandler {
    static func main() async {
        _ = umask(0o077)
        guard CommandLine.arguments.count == 2 else { exit(2) }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        do {
            let job = try JSONDecoder().decode(Job.self, from: Data(contentsOf: directory.appendingPathComponent("job.json")))
            let handler = try Handler(job: job, directory: directory)
            do {
                try await handler.run()
                if handler.status.State != "Paused" {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent("job.json"))
                }
            } catch {
                handler.fail(error)
                try? FileManager.default.removeItem(at: directory.appendingPathComponent("job.json"))
                exit(1)
            }
        } catch {
            let status = Status(State: "Failed", ErrorMessage: error.localizedDescription)
            if let data = try? JSONEncoder().encode(status) {
                let target = directory.appendingPathComponent("status.json")
                try? data.write(to: target, options: .atomic)
                _ = chmod(target.path, S_IRUSR | S_IWUSR)
            }
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("job.json"))
            exit(1)
        }
    }
}
