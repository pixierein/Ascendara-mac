import Foundation
import Darwin
import AscendaraCore

private struct Job: Decodable {
    let Id: UUID
    let URL: URL
    let Destination: URL
    let Headers: [String: String]
    let Connections: Int
    let SpeedLimitBytesPerSecond: Int64
    let EstimatedBytes: Int64?

    private enum CodingKeys: String, CodingKey { case Id, URL, Destination, Headers, Connections, SpeedLimitBytesPerSecond, EstimatedBytes }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        Id = try values.decode(UUID.self, forKey: .Id)
        URL = try values.decode(Foundation.URL.self, forKey: .URL)
        Destination = try values.decode(Foundation.URL.self, forKey: .Destination)
        Headers = try values.decodeIfPresent([String: String].self, forKey: .Headers) ?? [:]
        Connections = max(1, min(16, try values.decodeIfPresent(Int.self, forKey: .Connections) ?? 1))
        SpeedLimitBytesPerSecond = max(0, try values.decodeIfPresent(Int64.self, forKey: .SpeedLimitBytesPerSecond) ?? 0)
        EstimatedBytes = try values.decodeIfPresent(Int64.self, forKey: .EstimatedBytes)
    }
}

private struct Status: Encodable {
    let State: String
    let ReceivedBytes: Int64
    let TotalBytes: Int64
    let BytesPerSecond: Double
    let ErrorMessage: String?
    let PID: Int32
}

private struct ResumeState: Codable {
    let URL: String
    let Validator: String
    let TotalBytes: Int64
}

private struct Piece: Codable {
    let Start: Int64
    let End: Int64  // inclusive
}

private struct ParallelState: Codable {
    let URL: String
    let Validator: String
    let TotalBytes: Int64
    let Pieces: [Piece]
}

private struct ResponseHeaders {
    var StatusCode = 0
    var Values: [String: String] = [:]
    var Validator: String {
        let etag = Values["etag"] ?? ""
        return !etag.isEmpty && !etag.hasPrefix("W/") ? etag : (Values["last-modified"] ?? "")
    }
    var TotalBytes: Int64 {
        if let range = Values["content-range"], let slash = range.lastIndex(of: "/"),
           let value = Int64(range[range.index(after: slash)...].trimmingCharacters(in: .whitespacesAndNewlines)) { return value }
        return Int64(Values["content-length"] ?? "") ?? 0
    }
    var RangeStart: Int64? {
        guard let range = Values["content-range"], let space = range.firstIndex(of: " "),
              let dash = range.firstIndex(of: "-") else { return nil }
        return Int64(range[range.index(after: space)..<dash])
    }
}

private enum TransferError: LocalizedError {
    case message(String)
    case stopped
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return "The download was stopped."
    }
}

private final class Transfer {
    let directory: URL
    let job: Job
    let manager = FileManager.default
    let partial: URL
    let control: URL
    let resume: URL
    let parallel: URL
    let TransferDirectory: URL
    var lastStatus = Date.distantPast

    init(directory: URL, job: Job) {
        self.directory = directory
        self.job = job
        TransferDirectory = job.Destination.deletingLastPathComponent().appendingPathComponent(".ascendara-transfer-" + job.Id.uuidString)
        partial = TransferDirectory.appendingPathComponent("download.partial")
        control = directory.appendingPathComponent("control.txt")
        resume = directory.appendingPathComponent("resume.json")
        parallel = directory.appendingPathComponent("parallel.json")
    }

    func run() throws {
        guard ["https", "http"].contains(job.URL.scheme?.lowercased() ?? ""), job.URL.host != nil,
              job.URL.user == nil, job.URL.password == nil else {
            throw TransferError.message("The download URL must be an HTTP or HTTPS file URL.")
        }
        try manager.createDirectory(at: job.Destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.createDirectory(at: TransferDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let LegacyPartial = directory.appendingPathComponent("download.partial")
        if manager.fileExists(atPath: LegacyPartial.path), !manager.fileExists(atPath: partial.path) {
            try manager.moveItem(at: LegacyPartial, to: partial)
        }
        if job.Connections > 1 || manager.fileExists(atPath: parallel.path) {
            if try parallelTransfer() { return }
        }
        try singleTransfer()
    }

    private func singleTransfer() throws {
        var offset = size(partial)
        let Head = try HeadIfAvailable()
        let Expected = (Head?.TotalBytes ?? 0) > 0 ? Head!.TotalBytes : job.EstimatedBytes ?? 0
        if Expected > 0 { try StorageBudget.Check(at: TransferDirectory, Remaining: max(0, Expected - offset)) }
        let saved = try? JSONDecoder().decode(ResumeState.self, from: Data(contentsOf: resume))
        if offset > 0 {
            if let saved, saved.URL == job.URL.absoluteString, !saved.Validator.isEmpty,
               let current = try probeIfAvailable(), current.StatusCode == 206,
               current.Validator == saved.Validator, current.TotalBytes == saved.TotalBytes,
               offset <= saved.TotalBytes {
                if offset == saved.TotalBytes { try finish(total: offset); return }
            } else {
                try? manager.removeItem(at: partial)
                try? manager.removeItem(at: resume)
                offset = 0
            }
        }
        if let command = command(), command == "cancel" || command == "pause" {
            stop(command: command, received: offset, total: saved?.TotalBytes ?? 0)
            return
        }
        let headers = directory.appendingPathComponent("headers.txt")
        let errors = directory.appendingPathComponent("curl-error.txt")
        try? manager.removeItem(at: headers)
        var args = commonArguments() + ["--continue-at", "-", "--output", partial.path, "--dump-header", headers.path]
        if offset > 0, let saved { args += ["--header", "If-Range: \(saved.Validator)"] }
        args.append(job.URL.absoluteString)
        var restarted = false
        while true {
            if Expected > 0 { try StorageBudget.Check(at: TransferDirectory, Remaining: max(0, Expected - offset)) }
            let process = try startCurl(args, errorFile: errors)
            let result = try monitor([process], received: { self.size(self.partial) }, total: { self.readHeaders(headers).TotalBytes })
            if let result {
                stop(command: result, received: size(partial), total: readHeaders(headers).TotalBytes)
                return
            }
            let response = readHeaders(headers)
            let actual = size(partial)
            if process.terminationStatus == 0 {
                if offset > 0 && (response.StatusCode != 206 || response.RangeStart != offset || response.Validator != saved?.Validator) {
                    if !restarted {
                        restarted = true
                        offset = 0
                        try? manager.removeItem(at: partial)
                        try? manager.removeItem(at: resume)
                        args = commonArguments() + ["--output", partial.path, "--dump-header", headers.path, job.URL.absoluteString]
                        continue
                    }
                    throw TransferError.message("The server changed the file during resume; the partial file was retained.")
                }
                if ["text/html", "application/json"].contains(where: { response.Values["content-type"]?.lowercased().contains($0) == true }) {
                    throw TransferError.message("The provider returned a page or JSON response instead of a game file.")
                }
                let total = response.TotalBytes
                if total > 0, actual != total {
                    throw TransferError.message("Incomplete download: \(actual) of \(total) bytes; partial data was retained.")
                }
                try finish(total: actual)
                return
            }
            if offset > 0 && !restarted && (process.terminationStatus == 33 || response.StatusCode == 416 || response.StatusCode == 200) {
                restarted = true
                offset = 0
                try? manager.removeItem(at: partial)
                try? manager.removeItem(at: resume)
                args = commonArguments() + ["--output", partial.path, "--dump-header", headers.path, job.URL.absoluteString]
                continue
            }
            throw TransferError.message(failureMessage(errors, status: response.StatusCode))
        }
    }

    private func parallelTransfer() throws -> Bool {
        let state: ParallelState
        if let old = try? JSONDecoder().decode(ParallelState.self, from: Data(contentsOf: parallel)),
           old.URL == job.URL.absoluteString, !old.Validator.isEmpty {
            let current = try probe()
            if current.StatusCode == 206, current.TotalBytes == old.TotalBytes,
               current.Validator == old.Validator { state = old }
            else { discardPieces(); return false }
        } else {
            discardPieces()
            guard !manager.fileExists(atPath: partial.path),
                  let response = try probeIfAvailable(), response.StatusCode == 206,
                  response.TotalBytes >= 8 * 1024 * 1024, !response.Validator.isEmpty else { return false }
            let target = max(Int64(4 * 1024 * 1024), min(Int64(64 * 1024 * 1024),
                         (response.TotalBytes + Int64(job.Connections * 2) - 1) / Int64(job.Connections * 2)))
            var pieces: [Piece] = []
            var start: Int64 = 0
            while start < response.TotalBytes {
                let end = min(response.TotalBytes - 1, start + target - 1)
                pieces.append(Piece(Start: start, End: end))
                start = end + 1
            }
            state = ParallelState(URL: job.URL.absoluteString, Validator: response.Validator,
                                  TotalBytes: response.TotalBytes, Pieces: pieces)
            try JSONEncoder().encode(state).write(to: parallel, options: .atomic)
        }
        try? manager.removeItem(at: partial)
        try StorageBudget.Check(at: TransferDirectory, Remaining: state.TotalBytes - pieceBytes(state), Reserved: state.Pieces.map(length).max() ?? 0)
        var failures = Array(repeating: 0, count: state.Pieces.count)
        var active: [Int: (Process, URL, URL, Int64)] = [:]
        defer {
            for (_, Entry) in active where Entry.0.isRunning { Entry.0.terminate() }
            for (_, Entry) in active { Entry.0.waitUntilExit() }
        }
        var lastSample = (Date(), pieceBytes(state))
        while true {
            let InProgress = active.values.reduce(Int64(0)) { $0 + size($1.1) }
            try StorageBudget.Check(at: TransferDirectory, Remaining: max(0, state.TotalBytes - pieceBytes(state) - InProgress), Reserved: state.Pieces.map(length).max() ?? 0)
            if let action = command() {
                for (_, entry) in active { entry.0.terminate() }
                for (_, entry) in active { entry.0.waitUntilExit() }
                for (index, entry) in active { _ = try mergePart(index: index, responseFile: entry.1, headerFile: entry.2, start: entry.3, state: state) }
                if action == "cancel" { discardPieces() }
                stop(command: action, received: pieceBytes(state), total: state.TotalBytes)
                return true
            }
            for (index, entry) in active where !entry.0.isRunning {
                entry.0.waitUntilExit()
                active.removeValue(forKey: index)
                let valid = try mergePart(index: index, responseFile: entry.1, headerFile: entry.2, start: entry.3, state: state)
                if !valid {
                    for (_, remaining) in active { remaining.0.terminate() }
                    for (_, remaining) in active { remaining.0.waitUntilExit() }
                    discardPieces()
                    return false
                }
                if entry.0.terminationStatus != 0 {
                    failures[index] += 1
                    if failures[index] >= 6 {
                        throw TransferError.message("A download segment failed repeatedly; completed segments were retained. \(failureMessage(errorFile(index), status: 0))")
                    }
                } else if pieceSize(index) < length(state.Pieces[index]) {
                    failures[index] += 1
                } else { failures[index] = 0 }
            }
            let completed = state.Pieces.indices.allSatisfy { pieceSize($0) == length(state.Pieces[$0]) }
            if completed && active.isEmpty { break }
            for index in state.Pieces.indices where active.count < job.Connections {
                let part = state.Pieces[index]
                let next = part.Start + pieceSize(index)
                guard next <= part.End, active[index] == nil else { continue }
                if failures[index] >= 6 { throw TransferError.message("A download segment failed repeatedly; completed segments were retained.") }
                let output = TransferDirectory.appendingPathComponent("piece-\(index).next")
                let headers = directory.appendingPathComponent("piece-\(index).headers")
                try? manager.removeItem(at: output)
                try? manager.removeItem(at: headers)
                let args = commonArguments(rateDivisor: job.Connections) + ["--range", "\(next)-\(part.End)",
                            "--header", "If-Range: \(state.Validator)", "--output", output.path,
                            "--dump-header", headers.path, job.URL.absoluteString]
                let process = try startCurl(args, errorFile: errorFile(index))
                active[index] = (process, output, headers, next)
            }
            let now = Date()
            if now.timeIntervalSince(lastStatus) >= 0.5 {
                let bytes = pieceBytes(state) + active.values.reduce(Int64(0)) { $0 + size($1.1) }
                let elapsed = max(0.01, now.timeIntervalSince(lastSample.0))
                report("Downloading", bytes, state.TotalBytes, max(0, Double(bytes - lastSample.1) / elapsed))
                lastSample = (now, bytes)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        try StorageBudget.Check(at: TransferDirectory, Remaining: state.Pieces.map(length).max() ?? 0)
        manager.createFile(atPath: partial.path, contents: nil)
        let output = try FileHandle(forWritingTo: partial)
        defer { try? output.close() }
        for index in state.Pieces.indices {
            try append(file: pieceURL(index), to: output)
            try output.synchronize()
            try manager.removeItem(at: pieceURL(index))
        }
        guard size(partial) == state.TotalBytes else { throw TransferError.message("Parallel download did not assemble to the expected size.") }
        try finish(total: state.TotalBytes)
        discardPieces()
        return true
    }

    private func mergePart(index: Int, responseFile: URL, headerFile: URL, start: Int64, state: ParallelState) throws -> Bool {
        defer { try? manager.removeItem(at: responseFile); try? manager.removeItem(at: headerFile) }
        guard size(responseFile) > 0 else { return true }
        let headers = readHeaders(headerFile)
        guard headers.StatusCode == 206, headers.RangeStart == start,
              headers.TotalBytes == state.TotalBytes, headers.Validator == state.Validator,
              size(responseFile) <= state.Pieces[index].End - start + 1 else { return false }
        let piece = pieceURL(index)
        if !manager.fileExists(atPath: piece.path) { manager.createFile(atPath: piece.path, contents: nil) }
        let destination = try FileHandle(forWritingTo: piece)
        try destination.seekToEnd()
        try append(file: responseFile, to: destination)
        try destination.close()
        return true
    }

    private func probe() throws -> ResponseHeaders {
        let headers = directory.appendingPathComponent("probe.headers")
        let output = directory.appendingPathComponent("probe.byte")
        let errors = directory.appendingPathComponent("probe-error.txt")
        defer { try? manager.removeItem(at: output); try? manager.removeItem(at: headers) }
        try? manager.removeItem(at: headers)
        let process = try startCurl(commonArguments() + ["--max-filesize", "1048576", "--max-time", "20", "--range", "0-0", "--output", output.path,
                                                    "--dump-header", headers.path, job.URL.absoluteString], errorFile: errors)
        let Deadline = Date().addingTimeInterval(20)
        while process.isRunning {
            try stopProbeIfRequested(process)
            if size(output) > 1024 * 1024 || Date() > Deadline {
                process.terminate(); process.waitUntilExit()
                throw TransferError.message("The server did not honor the bounded range probe.")
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        process.waitUntilExit()
        try stopProbeIfRequested(process)
        guard process.terminationStatus == 0 else { throw TransferError.message(failureMessage(errors, status: readHeaders(headers).StatusCode)) }
        return readHeaders(headers)
    }

    private func probeIfAvailable() throws -> ResponseHeaders? {
        do { return try probe() }
        catch TransferError.stopped { throw TransferError.stopped }
        catch { return nil }
    }

    private func HeadIfAvailable() throws -> ResponseHeaders? {
        let Headers = directory.appendingPathComponent("head.headers")
        let Errors = directory.appendingPathComponent("head.error")
        defer { try? manager.removeItem(at: Headers); try? manager.removeItem(at: Errors) }
        let ProcessValue = try startCurl(commonArguments() + ["--head", "--max-time", "20", "--dump-header", Headers.path,
                                                          "--output", "/dev/null", job.URL.absoluteString], errorFile: Errors)
        while ProcessValue.isRunning {
            try stopProbeIfRequested(ProcessValue)
            Thread.sleep(forTimeInterval: 0.1)
        }
        ProcessValue.waitUntilExit()
        let Response = readHeaders(Headers)
        return ProcessValue.terminationStatus == 0 && (200..<300).contains(Response.StatusCode) ? Response : nil
    }

    private func stopProbeIfRequested(_ process: Process) throws {
        guard let action = command() else { return }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        let state = try? JSONDecoder().decode(ParallelState.self, from: Data(contentsOf: parallel))
        let saved = try? JSONDecoder().decode(ResumeState.self, from: Data(contentsOf: resume))
        let received = state.map(pieceBytes) ?? size(partial)
        if action == "cancel" { discardPieces() }
        stop(command: action, received: received, total: state?.TotalBytes ?? saved?.TotalBytes ?? 0)
        throw TransferError.stopped
    }

    private func commonArguments(rateDivisor: Int = 1) -> [String] {
        var args = ["--location", "--max-redirs", "10", "--fail", "--show-error", "--silent",
                    "--connect-timeout", "30", "--proto", "=http,https", "--proto-redir", "=http,https",
                    "--retry", "5", "--retry-delay", "2", "--header", "Accept-Encoding: identity"]
        let cookieJar = directory.appendingPathComponent("cookies.txt")
        if manager.fileExists(atPath: cookieJar.path) { args += ["--cookie", cookieJar.path] }
        if job.SpeedLimitBytesPerSecond > 0 {
            args += ["--limit-rate", String(max(1, job.SpeedLimitBytesPerSecond / Int64(max(1, rateDivisor))))]
        }
        for (name, value) in job.Headers.sorted(by: { $0.key < $1.key })
            where ["user-agent", "referer", "origin"].contains(name.lowercased()) {
            args += ["--header", "\(name): \(value)"]
        }
        return args
    }

    private func startCurl(_ arguments: [String], errorFile: URL) throws -> Process {
        try? manager.removeItem(at: errorFile)
        manager.createFile(atPath: errorFile.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = try FileHandle(forWritingTo: errorFile)
        try process.run()
        return process
    }

    private func monitor(_ processes: [Process], received: () -> Int64, total: () -> Int64) throws -> String? {
        var last = (Date(), received())
        while processes.contains(where: { $0.isRunning }) {
            if let action = command() {
                for process in processes where process.isRunning { process.terminate() }
                for process in processes { process.waitUntilExit() }
                return action
            }
            let now = Date(), bytes = received()
            do { try StorageBudget.Check(at: TransferDirectory, Remaining: max(0, total() - bytes)) }
            catch {
                for process in processes where process.isRunning { process.terminate() }
                for process in processes { process.waitUntilExit() }
                throw error
            }
            let elapsed = max(0.01, now.timeIntervalSince(last.0))
            report("Downloading", bytes, total(), max(0, Double(bytes - last.1) / elapsed))
            last = (now, bytes)
            Thread.sleep(forTimeInterval: 0.5)
        }
        for process in processes { process.waitUntilExit() }
        return nil
    }

    private func finish(total: Int64) throws {
        guard total > 0 else { throw TransferError.message("The provider returned an empty file.") }
        let handle = try FileHandle(forReadingFrom: partial)
        let prefix = try handle.read(upToCount: 512) ?? Data()
        try handle.close()
        let text = String(decoding: prefix, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("<!doctype html") || text.hasPrefix("<html") || text.hasPrefix("{\"error\"") {
            throw TransferError.message("The provider returned a page or error response instead of a game file.")
        }
        guard !manager.fileExists(atPath: job.Destination.path) else {
            throw TransferError.message("The destination file already exists; the partial file was retained.")
        }
        try manager.moveItem(at: partial, to: job.Destination)
        try? manager.removeItem(at: TransferDirectory)
        try? manager.removeItem(at: resume)
        report("Completed", total, total, 0)
    }

    private func stop(command: String, received: Int64, total: Int64) {
        if command == "cancel" {
            try? manager.removeItem(at: TransferDirectory)
            try? manager.removeItem(at: resume)
        }
        report(command == "pause" ? "Paused" : "Cancelled", received, total, 0)
    }

    private func command() -> String? {
        let value = (try? String(contentsOf: control, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value == "pause" || value == "cancel" ? value : nil
    }

    private func readHeaders(_ url: URL) -> ResponseHeaders {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return ResponseHeaders() }
        var current = ResponseHeaders()
        for line in text.components(separatedBy: .newlines) {
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.uppercased().hasPrefix("HTTP/") {
                current = ResponseHeaders()
                current.StatusCode = Int(clean.split(separator: " ").dropFirst().first ?? "") ?? 0
            } else if let colon = clean.firstIndex(of: ":") {
                let key = clean[..<colon].lowercased()
                let value = clean[clean.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
                current.Values[key] = value
            }
        }
        return current
    }

    private func report(_ state: String, _ received: Int64, _ total: Int64, _ speed: Double, error: String? = nil) {
        let now = Date()
        guard state != "Downloading" || now.timeIntervalSince(lastStatus) >= 0.45 else { return }
        lastStatus = now
        let status = Status(State: state, ReceivedBytes: received, TotalBytes: total,
                            BytesPerSecond: speed, ErrorMessage: error, PID: getpid())
        if let data = try? JSONEncoder().encode(status) {
            let target = directory.appendingPathComponent("status.json")
            try? data.write(to: target, options: .atomic)
            _ = chmod(target.path, S_IRUSR | S_IWUSR)
        }
        if state == "Downloading", received > 0 {
            let headers = readHeaders(directory.appendingPathComponent("headers.txt"))
            if !headers.Validator.isEmpty, headers.TotalBytes > 0 {
                let metadata = ResumeState(URL: job.URL.absoluteString, Validator: headers.Validator, TotalBytes: headers.TotalBytes)
                if let data = try? JSONEncoder().encode(metadata) { try? data.write(to: resume, options: .atomic) }
            }
        }
    }

    private func size(_ url: URL) -> Int64 {
        var information = stat()
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path, lstat(path, &information) == 0 else { return 0 }
            return Int64(information.st_size)
        }
    }
    private func length(_ piece: Piece) -> Int64 { piece.End - piece.Start + 1 }
    private func pieceURL(_ index: Int) -> URL { TransferDirectory.appendingPathComponent("piece-\(index).data") }
    private func errorFile(_ index: Int) -> URL { directory.appendingPathComponent("piece-\(index).error") }
    private func pieceSize(_ index: Int) -> Int64 { size(pieceURL(index)) }
    private func pieceBytes(_ state: ParallelState) -> Int64 {
        state.Pieces.indices.reduce(Int64(0)) { $0 + min(length(state.Pieces[$1]), pieceSize($1)) }
    }
    private func discardPieces() {
        try? manager.removeItem(at: parallel)
        for Root in [directory, TransferDirectory] {
            if let Files = try? manager.contentsOfDirectory(at: Root, includingPropertiesForKeys: nil) {
                for File in Files where File.lastPathComponent.hasPrefix("piece-") { try? manager.removeItem(at: File) }
            }
        }
    }
    private func append(file: URL, to output: FileHandle) throws {
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty { try output.write(contentsOf: data) }
    }
    private func failureMessage(_ url: URL, status: Int) -> String {
        let message = (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if [403, 404, 410].contains(status) { return "Download server returned HTTP \(status). Refresh the source or choose another link." }
        return message.isEmpty ? "The download server rejected the transfer\(status > 0 ? " (HTTP \(status))" : "")." : String(message.suffix(500))
    }
}

@main
private enum DownloadWorker {
    static func main() {
        _ = umask(0o077)
        guard CommandLine.arguments.count == 2 else { exit(2) }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        do {
            let job = try JSONDecoder().decode(Job.self, from: Data(contentsOf: directory.appendingPathComponent("job.json")))
            try Transfer(directory: directory, job: job).run()
        } catch TransferError.stopped {
            return
        } catch {
            let partial = directory.appendingPathComponent("download.partial")
            let status = Status(State: "Failed", ReceivedBytes: Int64((try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0),
                                TotalBytes: 0, BytesPerSecond: 0, ErrorMessage: error.localizedDescription, PID: getpid())
            if let data = try? JSONEncoder().encode(status) {
                let target = directory.appendingPathComponent("status.json")
                try? data.write(to: target, options: .atomic)
                _ = chmod(target.path, S_IRUSR | S_IWUSR)
            }
            exit(1)
        }
    }
}
