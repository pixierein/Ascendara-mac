import Foundation
import Combine

@MainActor
final class DownloadService: NSObject, ObservableObject {
    @Published private(set) var Downloads: [DownloadItem] = []
    @Published private(set) var ErrorMessage: String?
    var MaximumConcurrentDownloads = 2 { didSet { Pump() } }
    var OnCompleted: ((DownloadItem) -> Void)?
    let StorageDirectory: URL
    private var Tasks: [UUID: URLSessionDownloadTask] = [:]
    private var Pausing: Set<UUID> = []
    private var Samples: [UUID: (Date, Int64)] = [:]
    private var LastSave = Date.distantPast
    private var LoadFailed = false
    private let Delegate = DownloadDelegate()
    private lazy var Session: URLSession = {
        let Configuration = URLSessionConfiguration.default
        Configuration.timeoutIntervalForRequest = 60
        Configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        Configuration.httpAdditionalHeaders = ["User-Agent": "Ascendara-Native/1.0"]
        return URLSession(configuration: Configuration, delegate: Delegate, delegateQueue: nil)
    }()
    private var MetadataURL: URL { StorageDirectory.appendingPathComponent("downloads.json") }

    init(StorageDirectory: URL = RuntimePaths.Support) {
        self.StorageDirectory = StorageDirectory
        super.init()
        Delegate.Owner = self
        do {
            if FileManager.default.fileExists(atPath: MetadataURL.path) {
                Downloads = try JSONDecoder().decode([DownloadItem].self, from: Data(contentsOf: MetadataURL))
                for Index in Downloads.indices where Downloads[Index].IsActive {
                    let WasExtracting = Downloads[Index].State == .Extracting
                    Downloads[Index].State = WasExtracting ? .Completed : .Paused
                    Downloads[Index].BytesPerSecond = 0
                    Downloads[Index].ErrorMessage = WasExtracting ? "Extraction was interrupted. Extract the downloaded archive again." : "Interrupted when Ascendara closed. Resume to continue; servers without resume support restart the transfer."
                }
            }
        } catch {
            LoadFailed = true
            ErrorMessage = "Could not read download history: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func Start(Name: String, URL Source: URL, DestinationDirectory: URL, CatalogId: String? = nil, FileName: String? = nil, BatchId: UUID? = nil, Version: String? = nil) throws -> UUID {
        guard ["http", "https"].contains(Source.scheme?.lowercased() ?? ""), Source.host != nil else {
            throw RuntimeError.Message("Use a direct HTTP or HTTPS download link. Magnet links require a torrent client.")
        }
        guard ErrorMessage == nil else { throw RuntimeError.Message(ErrorMessage!) }
        try RuntimePaths.CreateDirectory(DestinationDirectory)
        var NameOnDisk = RuntimePaths.SafeName(FileName ?? (Source.lastPathComponent.isEmpty ? Name + ".download" : Source.lastPathComponent))
        if FileManager.default.fileExists(atPath: DestinationDirectory.appendingPathComponent(NameOnDisk).path) || Downloads.contains(where: { $0.DestinationDirectory == DestinationDirectory && $0.FileName == NameOnDisk }) {
            NameOnDisk = String(UUID().uuidString.prefix(8)) + "-" + NameOnDisk
        }
        var Item = DownloadItem(Name: Name, SourceURL: Source, DestinationDirectory: DestinationDirectory, FileName: NameOnDisk)
        Item.CatalogId = CatalogId
        Item.BatchId = BatchId
        Item.Version = Version
        Downloads.append(Item)
        try Save()
        Pump()
        return Item.Id
    }

    func Pause(_ Id: UUID) throws {
        guard let Index = Index(Id), [.Queued, .Downloading].contains(Downloads[Index].State) else { return }
        Downloads[Index].State = .Paused
        Downloads[Index].BytesPerSecond = 0
        if let Task = Tasks[Id] {
            Pausing.insert(Id)
            Task.cancel { [weak self] Data in
                Swift.Task { @MainActor in
                    guard let self else { return }
                    if let Index = self.Index(Id), self.Downloads[Index].State == .Paused { self.Downloads[Index].ResumeData = Data }
                    self.Tasks.removeValue(forKey: Id)
                    self.Pausing.remove(Id)
                    self.SaveChanges()
                    self.Pump()
                }
            }
        }
        try Save()
        Pump()
    }

    func Resume(_ Id: UUID) throws {
        guard !Pausing.contains(Id) else { throw RuntimeError.Message("The download is still pausing. Try Resume again in a moment.") }
        guard let Index = Index(Id), [.Paused, .Failed].contains(Downloads[Index].State) else { return }
        Downloads[Index].State = .Queued
        Downloads[Index].ErrorMessage = nil
        try Save()
        Pump()
    }

    func Cancel(_ Id: UUID) throws {
        guard let Index = Index(Id), ![.Completed, .Extracted, .Extracting].contains(Downloads[Index].State) else { return }
        Downloads[Index].State = .Cancelled
        Downloads[Index].ResumeData = nil
        Downloads[Index].BytesPerSecond = 0
        Tasks.removeValue(forKey: Id)?.cancel()
        try Save()
        Pump()
    }

    func Remove(_ Id: UUID) throws {
        guard let Index = Index(Id), !Downloads[Index].IsActive, !Pausing.contains(Id) else { throw RuntimeError.Message("Stop this download before removing it from the list.") }
        Downloads.remove(at: Index)
        try Save()
    }

    func PauseAll() {
        for Id in Downloads.filter({ [.Downloading, .Queued].contains($0.State) }).map(\.Id) {
            do { try Pause(Id) } catch { ErrorMessage = error.localizedDescription }
        }
    }

    func PrepareForExit() async {
        PauseAll()
        let Deadline = Date().addingTimeInterval(5)
        while !Pausing.isEmpty, Date() < Deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        SaveChanges()
    }

    private func Pump() {
        guard !LoadFailed else { return }
        let Limit = max(1, min(8, MaximumConcurrentDownloads))
        while Downloads.filter({ $0.State == .Downloading }).count < Limit,
              let Index = Downloads.firstIndex(where: { $0.State == .Queued }) {
            let Item = Downloads[Index]
            let Task: URLSessionDownloadTask
            if let Data = Item.ResumeData {
                Task = Session.downloadTask(withResumeData: Data)
            } else {
                Task = Session.downloadTask(with: Item.SourceURL)
                Downloads[Index].ReceivedBytes = 0
            }
            Task.taskDescription = Item.Id.uuidString
            Tasks[Item.Id] = Task
            Downloads[Index].State = .Downloading
            Downloads[Index].ResumeData = nil
            Samples[Item.Id] = (Date(), Downloads[Index].ReceivedBytes)
            Task.resume()
        }
        SaveChanges()
    }

    fileprivate func Progress(_ Id: UUID, Received: Int64, Total: Int64) {
        guard let Index = Index(Id), Downloads[Index].State == .Downloading else { return }
        let Now = Date()
        if let Sample = Samples[Id], Now.timeIntervalSince(Sample.0) < 0.25,
           Total <= 0 || Received < Total { return }
        var Updated = Downloads[Index]
        Updated.ReceivedBytes = Received
        Updated.TotalBytes = max(0, Total)
        if let Sample = Samples[Id], Now.timeIntervalSince(Sample.0) > 0 {
            Updated.BytesPerSecond = max(0, Double(Received - Sample.1) / Now.timeIntervalSince(Sample.0))
        }
        Samples[Id] = (Now, Received)
        Downloads[Index] = Updated
        if Now.timeIntervalSince(LastSave) > 2 { SaveChanges() }
    }

    fileprivate func Finished(_ Id: UUID, Location: URL, Response: URLResponse?) {
        defer { try? FileManager.default.removeItem(at: Location) }
        guard let Index = Index(Id), Downloads[Index].State == .Downloading else { return }
        do {
            if let HTTP = Response as? HTTPURLResponse, !(200...299).contains(HTTP.statusCode) {
                throw RuntimeError.Message("The server returned HTTP \(HTTP.statusCode). The download link may have expired.")
            }
            let MIME = Response?.mimeType?.lowercased() ?? ""
            if MIME.contains("html") || MIME.contains("json") {
                throw RuntimeError.Message("This link returned a provider page instead of a game file. Open the link in your browser and copy its direct download URL.")
            }
            let Prefix = try FileHandle(forReadingFrom: Location)
            let Bytes = try Prefix.read(upToCount: 512) ?? Data()
            try Prefix.close()
            let Start = String(decoding: Bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if Start.hasPrefix("<!doctype html") || Start.hasPrefix("<html") {
                throw RuntimeError.Message("The provider returned a web page. Use the direct file link from your browser.")
            }
            try FileManager.default.moveItem(at: Location, to: Downloads[Index].FileURL)
            let Size = (try Downloads[Index].FileURL.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
            Downloads[Index].ReceivedBytes = Int64(Size)
            Downloads[Index].TotalBytes = Int64(Size)
            Downloads[Index].State = .Completed
            Downloads[Index].BytesPerSecond = 0
            Downloads[Index].ResumeData = nil
            Downloads[Index].ErrorMessage = nil
            Tasks.removeValue(forKey: Id)
            SaveChanges()
            OnCompleted?(Downloads[Index])
            Pump()
        } catch { Failed(Id, Error: error) }
    }

    fileprivate func Failed(_ Id: UUID, Error: Error?) {
        guard let Error else { return }
        guard let Index = Index(Id), ![.Paused, .Cancelled, .Completed, .Extracted].contains(Downloads[Index].State) else { return }
        Downloads[Index].State = .Failed
        Downloads[Index].ErrorMessage = Error.localizedDescription
        Downloads[Index].BytesPerSecond = 0
        Downloads[Index].ResumeData = (Error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Tasks.removeValue(forKey: Id)
        SaveChanges()
        Pump()
    }

    @discardableResult
    func Extract(_ Id: UUID) async throws -> URL {
        guard let Index = Index(Id), [.Completed, .Extracted].contains(Downloads[Index].State) else { throw RuntimeError.Message("Finish the download before extracting it.") }
        let Item = Downloads[Index]
        let Destination = Item.DestinationDirectory.appendingPathComponent(RuntimePaths.SafeName(Item.Name), isDirectory: true)
        guard !FileManager.default.fileExists(atPath: Destination.path) else { throw RuntimeError.Message("The destination already exists: \(Destination.path). Choose another location or move that folder first.") }
        Downloads[Index].State = .Extracting
        SaveChanges()
        do {
            try await ArchiveExtractor.Extract(Item.FileURL, To: Destination)
            if let Index = self.Index(Id) {
                Downloads[Index].State = .Extracted
                Downloads[Index].ExtractedPath = Destination.path
                Downloads[Index].ErrorMessage = nil
                SaveChanges()
                OnCompleted?(Downloads[Index])
            }
            return Destination
        } catch {
            if let Index = self.Index(Id) {
                Downloads[Index].State = .Completed
                Downloads[Index].ErrorMessage = "Extraction failed: \(error.localizedDescription)"
                SaveChanges()
            }
            throw error
        }
    }

    private func Index(_ Id: UUID) -> Int? { Downloads.firstIndex { $0.Id == Id } }

    private func Save() throws {
        guard !LoadFailed else { throw RuntimeError.Message("Download history could not be read; the original metadata has been preserved.") }
        try RuntimePaths.CreateDirectory(StorageDirectory)
        try JSONEncoder().encode(Downloads).write(to: MetadataURL, options: .atomic)
        LastSave = Date()
    }

    private func SaveChanges() {
        do { try Save() } catch { ErrorMessage = "Could not save downloads: \(error.localizedDescription)" }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var Owner: DownloadService?

    func urlSession(_ Session: URLSession, downloadTask DownloadTask: URLSessionDownloadTask, didWriteData BytesWritten: Int64, totalBytesWritten TotalBytesWritten: Int64, totalBytesExpectedToWrite TotalBytesExpectedToWrite: Int64) {
        guard let Description = DownloadTask.taskDescription, let Id = UUID(uuidString: Description) else { return }
        Task { @MainActor [weak Owner] in Owner?.Progress(Id, Received: TotalBytesWritten, Total: TotalBytesExpectedToWrite) }
    }

    func urlSession(_ Session: URLSession, downloadTask DownloadTask: URLSessionDownloadTask, didFinishDownloadingTo Location: URL) {
        guard let Description = DownloadTask.taskDescription, let Id = UUID(uuidString: Description) else { return }
        let Saved = FileManager.default.temporaryDirectory.appendingPathComponent("ascendara-" + UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: Location, to: Saved)
            let Response = DownloadTask.response
            Task { @MainActor [weak Owner] in
                guard let Owner else { try? FileManager.default.removeItem(at: Saved); return }
                Owner.Finished(Id, Location: Saved, Response: Response)
            }
        } catch {
            Task { @MainActor [weak Owner] in Owner?.Failed(Id, Error: error) }
        }
    }

    func urlSession(_ Session: URLSession, task TaskValue: URLSessionTask, didCompleteWithError Error: Error?) {
        guard let Description = TaskValue.taskDescription, let Id = UUID(uuidString: Description), let Error else { return }
        Task { @MainActor [weak Owner] in Owner?.Failed(Id, Error: Error) }
    }
}

enum ArchiveExtractor {
    static func ValidatePath(_ Path: String) throws {
        let Normal = Path.replacingOccurrences(of: "\\", with: "/")
        guard !Normal.hasPrefix("/"), !Normal.contains("\0"), !Normal.components(separatedBy: "/").contains(".."),
              !(Normal.count >= 2 && Normal[Normal.index(after: Normal.startIndex)] == ":") else {
            throw RuntimeError.Message("The archive contains an unsafe file path: \(Path)")
        }
    }

    static func Extract(_ Archive: URL, To Destination: URL) async throws {
        guard !FileManager.default.fileExists(atPath: Destination.path) else { throw RuntimeError.Message("The extraction destination already exists.") }
        let Tar = URL(fileURLWithPath: "/usr/bin/bsdtar")
        let SevenZip = FindSevenZip()
        let PrefersSevenZip = ["rar", "7z", "001"].contains(Archive.pathExtension.lowercased())
        var Extractor = Tar
        if PrefersSevenZip, let SevenZip {
            try await ValidateSevenZip(Archive, Tool: SevenZip)
            Extractor = SevenZip
        } else {
            let Listing = try await NativeProcess.Run(Tar, ["-tf", Archive.path])
            if Listing.Status == 0 {
                for Path in Listing.Output.components(separatedBy: .newlines) where !Path.isEmpty { try ValidatePath(Path) }
                let Details = try await NativeProcess.Checked(Tar, ["-tvf", Archive.path])
                for Line in Details.components(separatedBy: .newlines) where !Line.isEmpty {
                    guard Line.first == "-" || Line.first == "d" else { throw RuntimeError.Message("Archives containing links or special files are not extracted automatically.") }
                }
            } else if let SevenZip {
                try await ValidateSevenZip(Archive, Tool: SevenZip)
                Extractor = SevenZip
            } else {
                throw RuntimeError.Message("macOS could not read this archive and the 7-Zip runtime was not found. Run Scripts/SetupTools.sh to prepare archive support. \(Listing.ErrorOutput)")
            }
        }
        let Staging = Destination.deletingLastPathComponent().appendingPathComponent(".ascendara-extract-" + UUID().uuidString, isDirectory: true)
        try RuntimePaths.CreateDirectory(Staging)
        do {
            do {
                try await Unpack(Archive, Tool: Extractor, To: Staging)
            } catch {
                guard Extractor == Tar, let SevenZip else { throw error }
                try await ValidateSevenZip(Archive, Tool: SevenZip)
                try FileManager.default.removeItem(at: Staging)
                try RuntimePaths.CreateDirectory(Staging)
                try await Unpack(Archive, Tool: SevenZip, To: Staging)
            }
            try ValidateExtractedFiles(Staging)
            try FileManager.default.moveItem(at: Staging, to: Destination)
        } catch {
            try? FileManager.default.removeItem(at: Staging)
            throw error
        }
    }

    static func FindSevenZip() -> URL? {
        let Candidates: [String?] = [Bundle.main.resourceURL?.appendingPathComponent("Tools/7zz").path,
                          URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("BuildTools/7zip/7zz").path,
                          URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("MacPort/BuildTools/7zip/7zz").path,
                          "/opt/homebrew/bin/7zz", "/usr/local/bin/7zz"]
        return Candidates.compactMap { $0 }.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    private static func ValidateSevenZip(_ Archive: URL, Tool: URL) async throws {
        let Details = try await NativeProcess.Checked(Tool, ["l", "-slt", "-ba", "--", Archive.path])
        for Line in Details.components(separatedBy: .newlines) {
            if Line.hasPrefix("Path = ") { try ValidatePath(String(Line.dropFirst(7))) }
            if Line.hasPrefix("Symbolic Link = ") || Line.hasPrefix("Hard Link = ") || Line.hasPrefix("Attributes = ") && (Line.contains(" l") || Line.contains(" p") || Line.contains(" b") || Line.contains(" c")) {
                throw RuntimeError.Message("Archives containing links or special files are not extracted automatically.")
            }
        }
    }

    private static func Unpack(_ Archive: URL, Tool: URL, To Directory: URL) async throws {
        let Arguments = Tool.lastPathComponent == "bsdtar" ? ["-xf", Archive.path, "-C", Directory.path, "--no-same-owner", "--no-same-permissions"] : ["x", "-y", "-o" + Directory.path, "--", Archive.path]
        _ = try await NativeProcess.Checked(Tool, Arguments)
    }

    private static func ValidateExtractedFiles(_ Directory: URL) throws {
        if let Enumerator = FileManager.default.enumerator(at: Directory, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) {
            for case let File as URL in Enumerator {
                if (try File.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true || !RuntimePaths.IsInside(File, Directory) {
                    throw RuntimeError.Message("The archive tried to create a link outside the extraction folder.")
                }
            }
        }
    }
}
