import Foundation
import Combine
import Darwin
import AscendaraCore

private struct WorkerJob: Encodable {
    let Id: UUID
    let URL: URL
    let Destination: URL
    let Headers: [String: String]
    let Connections: Int
    let SpeedLimitBytesPerSecond: Int64
    let EstimatedBytes: Int64?
}

private struct WorkerStatus: Decodable {
    let State: DownloadState
    let ReceivedBytes: Int64
    let TotalBytes: Int64
    let BytesPerSecond: Double
    let ErrorMessage: String?
    let PID: Int32
}

@MainActor
final class DownloadService: NSObject, ObservableObject {
    @Published private(set) var Downloads: [DownloadItem] = []
    @Published private(set) var ErrorMessage: String?
    @Published private(set) var QueuePaused = false
    var MaximumConcurrentDownloads = 2 { didSet { Pump() } }
    private var TransferConnections = 1
    private var TransferSpeedLimit: Int64 = 0
    var OnCompleted: ((DownloadItem) -> Void)?
    let StorageDirectory: URL
    private var Tasks: [UUID: URLSessionDownloadTask] = [:]
    private var Pausing: Set<UUID> = []
    private var Samples: [UUID: (Date, Int64)] = [:]
    private var LastSave = Date.distantPast
    private var LoadFailed = false
    private var WorkerTimer: Timer?
    private var WorkerPIDs: [UUID: Int32] = [:]
    private var WorkerRoot: URL { StorageDirectory.appendingPathComponent("BackgroundDownloads", isDirectory: true) }
    private func WorkerDirectory(_ Id: UUID) -> URL { WorkerRoot.appendingPathComponent(Id.uuidString, isDirectory: true) }
    private var WorkerURL: URL? {
        let configured = ProcessInfo.processInfo.environment["ASCENDARA_DOWNLOAD_WORKER"]
        let candidate = configured.map { URL(fileURLWithPath: $0) } ?? Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("AscendaraDownloadWorker")
        return candidate.flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
    }
    private let Delegate = DownloadDelegate()
    private lazy var Session: URLSession = {
        let Configuration = URLSessionConfiguration.default
        Configuration.timeoutIntervalForRequest = 60
        Configuration.timeoutIntervalForResource = 7 * 24 * 60 * 60
        Configuration.httpAdditionalHeaders = ["User-Agent": "Ascendara-Native/" + AppVersion.Current]
        return URLSession(configuration: Configuration, delegate: Delegate, delegateQueue: nil)
    }()
    private var MetadataURL: URL { StorageDirectory.appendingPathComponent("downloads.json") }

    init(StorageDirectory: URL = RuntimePaths.Support) {
        self.StorageDirectory = StorageDirectory
        super.init()
        Delegate.Owner = self
        QueuePaused = (try? AppPaths.Read(Bool.self, From: StorageDirectory.appendingPathComponent("queue-paused.json"))) ?? false
        do {
            if FileManager.default.fileExists(atPath: MetadataURL.path) {
                Downloads = try JSONDecoder().decode([DownloadItem].self, from: Data(contentsOf: MetadataURL))
                for Index in Downloads.indices where Downloads[Index].IsActive {
                    if Downloads[Index].State != .Extracting && FileManager.default.fileExists(atPath: WorkerDirectory(Downloads[Index].Id).appendingPathComponent("job.json").path) {
                        continue
                    }
                    let WasExtracting = Downloads[Index].State == .Extracting
                    if WasExtracting, let Completed = ArchiveStorage.CompletedPath(Downloads[Index].FileURL) {
                        let Sources = ArchiveStorage.Sources(Downloads[Index].FileURL)
                        for Part in Downloads.indices where Sources.contains(Downloads[Part].FileURL) {
                            Downloads[Part].State = .Extracted
                            Downloads[Part].ExtractedPath = Completed.path
                            Downloads[Part].ErrorMessage = nil
                        }
                        ArchiveStorage.RemoveConsumedSources(Downloads[Index].FileURL)
                        continue
                    }
                    let Consumed = WasExtracting && FileManager.default.fileExists(atPath: ArchiveStorage.Marker(Downloads[Index].FileURL).path)
                    Downloads[Index].State = Consumed ? .Failed : WasExtracting ? .Completed : .Paused
                    if Consumed {
                        ArchiveStorage.CleanInterruptedStaging(Downloads[Index].FileURL)
                        let Sources = ArchiveStorage.Sources(Downloads[Index].FileURL)
                        for Part in Downloads.indices where Sources.contains(Downloads[Part].FileURL) {
                            Downloads[Part].State = .Failed
                            Downloads[Part].ReceivedBytes = 0
                            Downloads[Part].ErrorMessage = "Space-saving extraction was interrupted. Download every archive volume again."
                        }
                        ArchiveStorage.RemoveConsumedSources(Downloads[Index].FileURL)
                    }
                    Downloads[Index].BytesPerSecond = 0
                    Downloads[Index].ErrorMessage = Consumed ? "Space-saving extraction was interrupted. Resume to download the archive again." : WasExtracting ? "Extraction was interrupted. Extract the downloaded archive again." : "Interrupted when Ascendara closed. Resume to continue; servers without resume support restart the transfer."
                }
            }
        } catch {
            LoadFailed = true
            ErrorMessage = "Could not read download history: \(error.localizedDescription)"
        }
        Pump()
    }

    private func UpdateWorkerTimer() {
        let NeedsPolling = Downloads.contains(where: \.IsActive) || !Pausing.isEmpty
        if NeedsPolling && WorkerTimer == nil {
            let TimerValue = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Swift.Task { @MainActor [weak self] in self?.ReconcileWorkers() }
            }
            TimerValue.tolerance = 0.1
            WorkerTimer = TimerValue
            RunLoop.main.add(TimerValue, forMode: .common)
        } else if !NeedsPolling {
            WorkerTimer?.invalidate()
            WorkerTimer = nil
        }
    }

    func Configure(SingleStream: Bool, Threads: Int, SpeedLimitKBps: Int) {
        TransferConnections = SingleStream ? 1 : max(1, min(16, Threads))
        TransferSpeedLimit = Int64(max(0, SpeedLimitKBps)) * 1024
    }

    @discardableResult
    func Start(Name: String, URL Source: URL, DestinationDirectory: URL, CatalogId: String? = nil, FileName: String? = nil, BatchId: UUID? = nil, Version: String? = nil, RequestHeaders: [String: String] = [:], RequestCookies: [DownloadCookie] = [], EstimatedBytes: Int64? = nil, Installation: InstallationPlan? = nil) throws -> UUID {
        guard ["http", "https"].contains(Source.scheme?.lowercased() ?? ""), Source.host != nil else {
            throw RuntimeError.Message("Use a direct HTTP or HTTPS download link. Magnet links require a torrent client.")
        }
        guard ErrorMessage == nil else { throw RuntimeError.Message(ErrorMessage!) }
        try RuntimePaths.CreateDirectory(DestinationDirectory)
        if let EstimatedBytes, EstimatedBytes > 0 {
            try CheckCapacity(at: DestinationDirectory, Required: EstimatedBytes)
        }
        var NameOnDisk = RuntimePaths.SafeName(FileName ?? (Source.lastPathComponent.isEmpty ? Name + ".download" : Source.lastPathComponent))
        if FileManager.default.fileExists(atPath: DestinationDirectory.appendingPathComponent(NameOnDisk).path) || Downloads.contains(where: { $0.DestinationDirectory == DestinationDirectory && $0.FileName == NameOnDisk }) {
            NameOnDisk = String(UUID().uuidString.prefix(8)) + "-" + NameOnDisk
        }
        var Item = DownloadItem(Name: Name, SourceURL: Source, DestinationDirectory: DestinationDirectory, FileName: NameOnDisk)
        Item.CatalogId = CatalogId
        Item.BatchId = BatchId
        Item.Version = Version
        Item.EstimatedBytes = EstimatedBytes
        Item.TotalBytes = EstimatedBytes ?? 0
        Item.Installation = Installation
        Item.RequestHeaders = RequestHeaders.filter { ["user-agent", "referer", "origin"].contains($0.key.lowercased()) }
        if !RequestCookies.isEmpty { try WriteCookieJar(RequestCookies, For: Item.Id) }
        Downloads.append(Item)
        try Save()
        Pump()
        return Item.Id
    }

    func CheckCapacity(at Directory: URL, Required: Int64) throws {
        let Volume = try StorageBudget.Volume(at: Directory)
        let Reserved = Downloads.filter { $0.IsActive && (try? StorageBudget.Volume(at: $0.DestinationDirectory)) == Volume }
            .reduce(Int64(0)) { Current, Item in
                let Remaining = max(0, max(Item.EstimatedBytes ?? 0, Item.TotalBytes) - max(0, Item.ReceivedBytes))
                let (Total, Overflow) = Current.addingReportingOverflow(Remaining)
                return Overflow ? Int64.max : Total
            }
        try StorageBudget.Check(at: Directory, Remaining: Required, Reserved: Reserved)
    }

    func Pause(_ Id: UUID) throws {
        guard let Index = Index(Id), [.Queued, .Downloading].contains(Downloads[Index].State) else { return }
        let RunningWorker = WorkerIsRunning(Id)
        if RunningWorker {
            try "pause".write(to: WorkerDirectory(Id).appendingPathComponent("control.txt"), atomically: true, encoding: .utf8)
            Pausing.insert(Id)
        }
        Downloads[Index].State = .Paused
        Downloads[Index].BytesPerSecond = 0
        if RunningWorker {
            try Save()
            Pump()
            return
        }
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
        let RunningWorker = WorkerIsRunning(Id)
        if RunningWorker {
            try "cancel".write(to: WorkerDirectory(Id).appendingPathComponent("control.txt"), atomically: true, encoding: .utf8)
            Pausing.insert(Id)
        }
        Downloads[Index].State = .Cancelled
        Downloads[Index].ResumeData = nil
        Downloads[Index].BytesPerSecond = 0
        if !RunningWorker {
            CleanupCancelledWorker(Id)
        }
        Tasks.removeValue(forKey: Id)?.cancel()
        try Save()
        Pump()
    }

    func Remove(_ Id: UUID, DeleteFiles: Bool = false) throws {
        guard let Index = Index(Id), !Downloads[Index].IsActive, !Pausing.contains(Id) else { throw RuntimeError.Message("Stop this download before removing it from the list.") }
        let Item = Downloads[Index]
        if DeleteFiles {
            var Files = [Item.FileURL]
            if let Path = Item.ExtractedPath, !Path.isEmpty { Files.append(URL(fileURLWithPath: Path)) }
            let Existing = Files.filter { FileManager.default.fileExists(atPath: $0.path) }
            for File in Existing {
                let Extracted = Item.ExtractedPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
                let ExpectedName = RuntimePaths.SafeName(Item.Name)
                let OwnExtraction = File.standardizedFileURL == Extracted && File.pathComponents.count > 3 &&
                    (File.lastPathComponent == ExpectedName || File.lastPathComponent == ExpectedName + "-" + String(Item.Id.uuidString.prefix(8)))
                guard RuntimePaths.IsInside(File, Item.DestinationDirectory) || OwnExtraction else {
                    throw RuntimeError.Message("A download file is outside its download folder and was not moved to the Trash.")
                }
            }
            for File in Existing {
                try FileManager.default.trashItem(at: File, resultingItemURL: nil)
            }
        }
        Downloads.remove(at: Index)
        try Save()
        try? FileManager.default.removeItem(at: WorkerDirectory(Id))
    }

    private func WorkerIsRunning(_ Id: UUID) -> Bool {
        let StatusURL = WorkerDirectory(Id).appendingPathComponent("status.json")
        let Status = (try? Data(contentsOf: StatusURL)).flatMap { try? JSONDecoder().decode(WorkerStatus.self, from: $0) }
        let PID = WorkerPIDs[Id] ?? Status?.PID ?? 0
        guard PID > 0 else { return false }
        return kill(PID, 0) == 0 || errno == EPERM
    }

    private func CleanupCancelledWorker(_ Id: UUID) {
        Pausing.remove(Id)
        WorkerPIDs.removeValue(forKey: Id)
        try? FileManager.default.removeItem(at: WorkerDirectory(Id))
        if let Index = Index(Id) {
            try? FileManager.default.removeItem(at: Downloads[Index].DestinationDirectory.appendingPathComponent(".ascendara-transfer-" + Id.uuidString))
            Downloads[Index].ReceivedBytes = 0
            Downloads[Index].BytesPerSecond = 0
            try? FileManager.default.removeItem(at: Downloads[Index].FileURL)
        }
    }

    func PauseAll() {
        SetQueuePaused(true)
        for Id in Downloads.filter({ [.Downloading, .Queued].contains($0.State) }).map(\.Id) {
            do { try Pause(Id) } catch { ErrorMessage = error.localizedDescription }
        }
    }

    func SetQueuePaused(_ Paused: Bool) {
        QueuePaused = Paused
        do { try AppPaths.Write(Paused, To: StorageDirectory.appendingPathComponent("queue-paused.json")) }
        catch { ErrorMessage = error.localizedDescription }
        if !Paused { Pump() }
    }

    func ResumeAll() {
        for Index in Downloads.indices where Downloads[Index].State == .Paused && !Pausing.contains(Downloads[Index].Id) {
            Downloads[Index].State = .Queued
            Downloads[Index].ErrorMessage = nil
        }
        SetQueuePaused(false)
        SaveChanges()
    }

    func RetryFailed() {
        for Index in Downloads.indices where Downloads[Index].State == .Failed && !Pausing.contains(Downloads[Index].Id) {
            Downloads[Index].State = .Queued; Downloads[Index].ErrorMessage = nil
        }
        SaveChanges(); Pump()
    }

    func Prioritize(_ Id: UUID) throws {
        guard let Index = Index(Id), Downloads[Index].State == .Queued else { return }
        let Item = Downloads.remove(at: Index)
        Downloads.insert(Item, at: Downloads.firstIndex(where: { $0.State == .Queued }) ?? Downloads.count)
        try Save()
    }

    func ClearFinished() throws {
        for Id in Downloads.filter({ [.Completed, .Extracted, .Cancelled].contains($0.State) && $0.Installation == nil }).map(\.Id) {
            try Remove(Id)
        }
    }

    func CommitInstallation(_ Id: UUID, Path: String) throws {
        guard let Item = Downloads.first(where: { $0.Id == Id }) else { return }
        for Index in Downloads.indices where Downloads[Index].Id == Id || (Item.BatchId != nil && Downloads[Index].BatchId == Item.BatchId) {
            Downloads[Index].ExtractedPath = Path
            Downloads[Index].Installation = nil
            Downloads[Index].ImportCompleted = true
        }
        try Save()
    }

    func PrepareForExit() async {
        for Id in Downloads.filter({ $0.State == .Downloading && !FileManager.default.fileExists(atPath: WorkerDirectory($0.Id).appendingPathComponent("job.json").path) }).map(\.Id) {
            try? Pause(Id)
        }
        let Deadline = Date().addingTimeInterval(5)
        while !Pausing.isEmpty, Date() < Deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        SaveChanges()
        WorkerTimer?.invalidate()
        WorkerTimer = nil
    }

    private func Pump() {
        guard !LoadFailed else { return }
        guard !QueuePaused else { SaveChanges(); UpdateWorkerTimer(); return }
        let Limit = max(1, min(8, MaximumConcurrentDownloads))
        while Downloads.filter({ $0.State == .Downloading }).count < Limit,
              let Index = Downloads.firstIndex(where: { $0.State == .Queued }) {
            let Item = Downloads[Index]
            if let WorkerURL {
                do {
                    try StartWorker(Item, executable: WorkerURL)
                    Downloads[Index].State = .Downloading
                    Downloads[Index].BytesPerSecond = 0
                    Downloads[Index].ResumeData = nil
                    continue
                } catch {
                    Downloads[Index].State = .Failed
                    Downloads[Index].ErrorMessage = "Could not start background download: \(error.localizedDescription)"
                    continue
                }
            }
            let Task: URLSessionDownloadTask
            if let Data = Item.ResumeData {
                Task = Session.downloadTask(withResumeData: Data)
            } else {
                var Request = URLRequest(url: Item.SourceURL)
                for (Name, Value) in Item.RequestHeaders { Request.setValue(Value, forHTTPHeaderField: Name) }
                Task = Session.downloadTask(with: Request)
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
        UpdateWorkerTimer()
    }

    private func StartWorker(_ Item: DownloadItem, executable: URL) throws {
        let Directory = WorkerDirectory(Item.Id)
        try EnsurePrivateWorkerDirectory(Directory)
        let Job = WorkerJob(Id: Item.Id, URL: Item.SourceURL, Destination: Item.FileURL,
                            Headers: Item.RequestHeaders, Connections: TransferConnections,
                            SpeedLimitBytesPerSecond: TransferSpeedLimit, EstimatedBytes: Item.EstimatedBytes)
        let JobURL = Directory.appendingPathComponent("job.json")
        try JSONEncoder().encode(Job).write(to: JobURL, options: .atomic)
        _ = chmod(JobURL.path, S_IRUSR | S_IWUSR)
        try? FileManager.default.removeItem(at: Directory.appendingPathComponent("status.json"))
        try? FileManager.default.removeItem(at: Directory.appendingPathComponent("control.txt"))
        let ProcessValue = Process()
        ProcessValue.executableURL = executable
        ProcessValue.arguments = [Directory.path]
        ProcessValue.standardOutput = FileHandle.nullDevice
        ProcessValue.standardError = FileHandle.nullDevice
        try ProcessValue.run()
        WorkerPIDs[Item.Id] = ProcessValue.processIdentifier
    }

    private func EnsurePrivateWorkerDirectory(_ Directory: URL) throws {
        try FileManager.default.createDirectory(at: Directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        _ = chmod(WorkerRoot.path, S_IRUSR | S_IWUSR | S_IXUSR)
        _ = chmod(Directory.path, S_IRUSR | S_IWUSR | S_IXUSR)
    }

    private func WriteCookieJar(_ Cookies: [DownloadCookie], For Id: UUID) throws {
        let Directory = WorkerDirectory(Id)
        try EnsurePrivateWorkerDirectory(Directory)
        var Lines = ["# Netscape HTTP Cookie File"]
        for Cookie in Cookies {
            if let ExpiresAt = Cookie.ExpiresAt, ExpiresAt <= Date() { continue }
            let Domain = Cookie.Domain.lowercased()
            guard !Domain.isEmpty, Domain != ".", !Domain.contains("/"), !Domain.contains("\\"),
                  !Cookie.Name.isEmpty, !Cookie.Path.isEmpty,
                  [Domain, Cookie.Path, Cookie.Name, Cookie.Value].allSatisfy({ $0.rangeOfCharacter(from: CharacterSet(charactersIn: "\r\n\t\0")) == nil }) else { continue }
            let Prefix = Cookie.HTTPOnly ? "#HttpOnly_" : ""
            let Subdomains = Domain.hasPrefix(".") ? "TRUE" : "FALSE"
            let Expiry = Cookie.ExpiresAt.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
            Lines.append("\(Prefix)\(Domain)\t\(Subdomains)\t\(Cookie.Path)\t\(Cookie.Secure ? "TRUE" : "FALSE")\t\(Expiry)\t\(Cookie.Name)\t\(Cookie.Value)")
        }
        let Jar = Directory.appendingPathComponent("cookies.txt")
        try? FileManager.default.removeItem(at: Jar)
        let DataValue = Data((Lines.joined(separator: "\n") + "\n").utf8)
        guard FileManager.default.createFile(atPath: Jar.path, contents: DataValue,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw RuntimeError.Message("Could not save provider cookies for the background downloader.")
        }
    }

    private func ReconcileWorkers() {
        guard !LoadFailed else { return }
        guard Downloads.contains(where: { $0.IsActive }) || !Pausing.isEmpty else { return }
        var Snapshot = Downloads
        var Changed = false
        var NeedsPump = false
        var FinishedItems: [DownloadItem] = []
        for Index in Snapshot.indices {
            let Id = Snapshot[Index].Id
            let Directory = WorkerDirectory(Id)
            if Snapshot[Index].State == .Cancelled {
                guard Pausing.contains(Id) || FileManager.default.fileExists(atPath: Directory.path) else { continue }
                let StatusURL = Directory.appendingPathComponent("status.json")
                let Status = (try? Data(contentsOf: StatusURL)).flatMap { try? JSONDecoder().decode(WorkerStatus.self, from: $0) }
                if Status?.State == .Cancelled || !WorkerIsRunning(Id) {
                    CleanupCancelledWorker(Id)
                    Changed = true
                    NeedsPump = true
                }
                continue
            }
            if Snapshot[Index].State == .Paused && !Pausing.contains(Id) { continue }
            guard FileManager.default.fileExists(atPath: Directory.appendingPathComponent("job.json").path),
                  ![.Completed, .Extracted, .Extracting, .Failed].contains(Snapshot[Index].State) else { continue }
            let StatusURL = Directory.appendingPathComponent("status.json")
            guard let Status = (try? Data(contentsOf: StatusURL)).flatMap({ try? JSONDecoder().decode(WorkerStatus.self, from: $0) }) else {
                let PID = WorkerPIDs[Id] ?? 0
                if PID == 0 || kill(PID, 0) != 0 {
                    Snapshot[Index].State = .Paused
                    Snapshot[Index].ErrorMessage = "The background downloader stopped before reporting progress. Resume to retry."
                    Changed = true
                    NeedsPump = true
                }
                continue
            }
            if Status.State == .Downloading {
                if Status.PID > 0 && kill(Status.PID, 0) != 0 && errno != EPERM {
                    let Age = (try? StatusURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { Date().timeIntervalSince($0) } ?? 0
                    if Age > 5 {
                        if Snapshot[Index].State != .Cancelled {
                            Snapshot[Index].State = .Paused
                            Snapshot[Index].ErrorMessage = "The background downloader stopped. Resume to continue from the partial file."
                        }
                        Snapshot[Index].BytesPerSecond = 0
                        Pausing.remove(Id)
                        Changed = true
                        NeedsPump = true
                    }
                    continue
                }
                if Pausing.contains(Id) || Snapshot[Index].State == .Cancelled { continue }
                if Snapshot[Index].State == .Downloading &&
                    Snapshot[Index].ReceivedBytes == Status.ReceivedBytes &&
                    Snapshot[Index].TotalBytes == Status.TotalBytes &&
                    Snapshot[Index].BytesPerSecond == Status.BytesPerSecond { continue }
                Snapshot[Index].State = .Downloading
                Snapshot[Index].ReceivedBytes = Status.ReceivedBytes
                Snapshot[Index].TotalBytes = Status.TotalBytes
                Snapshot[Index].BytesPerSecond = Status.BytesPerSecond
                Changed = true
            } else {
                let Previous = Snapshot[Index].State
                if Previous == Status.State && Snapshot[Index].ReceivedBytes == Status.ReceivedBytes && Snapshot[Index].ErrorMessage == Status.ErrorMessage && !Pausing.contains(Id) { continue }
                Snapshot[Index].State = Status.State
                Snapshot[Index].ReceivedBytes = Status.ReceivedBytes
                Snapshot[Index].TotalBytes = Status.TotalBytes
                Snapshot[Index].BytesPerSecond = 0
                Snapshot[Index].ErrorMessage = Status.ErrorMessage
                Pausing.remove(Id)
                WorkerPIDs.removeValue(forKey: Id)
                if Status.State == .Completed || Status.State == .Cancelled {
                    try? FileManager.default.removeItem(at: Directory.appendingPathComponent("cookies.txt"))
                }
                Changed = true
                NeedsPump = true
                if Status.State == .Completed && Previous != .Completed { FinishedItems.append(Snapshot[Index]) }
            }
        }
        if Changed {
            Downloads = Snapshot
            if Date().timeIntervalSince(LastSave) > 2 || !FinishedItems.isEmpty { SaveChanges() }
            for Item in FinishedItems { OnCompleted?(Item) }
            if NeedsPump { Pump() }
        }
    }

    func RefreshProgress() { ReconcileWorkers() }

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
    func Extract(_ Id: UUID, SpaceSaving: Bool = false, Directory: URL? = nil) async throws -> URL {
        guard let Requested = Index(Id), [.Completed, .Extracted].contains(Downloads[Requested].State) else { throw RuntimeError.Message("Finish the download before extracting it.") }
        let ArchiveParts = PartsForArchive(Downloads[Requested])
        let Item = ArchiveParts.first(where: { Part in
            let Name = Part.FileName.lowercased()
            return Name.hasSuffix(".001") || Name.hasSuffix(".zip") ||
                (Name.hasSuffix(".rar") && (Name.range(of: #"\.part[0-9]+\.rar$"#, options: .regularExpression) == nil || Name.range(of: #"\.part0*1\.rar$"#, options: .regularExpression) != nil))
        }) ?? Downloads[Requested]
        guard ArchiveParts.allSatisfy({ [.Completed, .Extracted].contains($0.State) }) else {
            throw RuntimeError.Message("Finish downloading every archive part before extracting it.")
        }
        let Destination = (Directory ?? Item.DestinationDirectory).appendingPathComponent(RuntimePaths.SafeName(Item.Name) + (Directory == nil ? "" : "-" + String(Item.Id.uuidString.prefix(8))), isDirectory: true)
        try RuntimePaths.CreateDirectory(Destination.deletingLastPathComponent())
        guard !FileManager.default.fileExists(atPath: Destination.path) else { throw RuntimeError.Message("The destination already exists: \(Destination.path). Choose another location or move that folder first.") }
        for Part in ArchiveParts {
            if let PartIndex = self.Index(Part.Id) { Downloads[PartIndex].State = .Extracting }
        }
        do {
            try Save()
            try await ArchiveExtractor.Extract(Item.FileURL, To: Destination, SpaceSaving: SpaceSaving, Parts: ArchiveParts.map(\.FileURL))
            for Part in ArchiveParts {
                guard let PartIndex = self.Index(Part.Id) else { continue }
                Downloads[PartIndex].State = .Extracted
                Downloads[PartIndex].ExtractedPath = Destination.path
                Downloads[PartIndex].ErrorMessage = nil
            }
            try Save()
            var CleanupErrors: [String] = []
            for Part in ArchiveParts where FileManager.default.fileExists(atPath: Part.FileURL.path) {
                do { try FileManager.default.removeItem(at: Part.FileURL) }
                catch { CleanupErrors.append("\(Part.FileName): \(error.localizedDescription)") }
            }
            try? FileManager.default.removeItem(at: ArchiveStorage.Marker(Item.FileURL))
            if let Index = self.Index(Id) {
                if !CleanupErrors.isEmpty {
                    Downloads[Index].ErrorMessage = "Extracted, but could not delete the archive: " + CleanupErrors.joined(separator: "; ")
                    SaveChanges()
                }
                OnCompleted?(Downloads[Index])
            }
            return Destination
        } catch {
            if let Completed = ArchiveStorage.CompletedPath(Item.FileURL) {
                if let Index = self.Index(Item.Id) {
                    Downloads[Index].State = .Extracted
                    Downloads[Index].ExtractedPath = Completed.path
                    Downloads[Index].ErrorMessage = "Files were extracted, but download history could not be saved. Free some space and import the extracted game."
                }
                throw error
            }
            let Consumed = FileManager.default.fileExists(atPath: ArchiveStorage.Marker(Item.FileURL).path)
            if Consumed {
                for Part in ArchiveParts {
                    guard let PartIndex = self.Index(Part.Id) else { continue }
                    Downloads[PartIndex].State = .Failed
                    Downloads[PartIndex].ReceivedBytes = 0
                    Downloads[PartIndex].ErrorMessage = "Space-saving extraction failed. Download every archive volume again."
                }
                ArchiveStorage.RemoveConsumedSources(Item.FileURL)
            } else {
                for Part in ArchiveParts {
                    if let PartIndex = self.Index(Part.Id) { Downloads[PartIndex].State = .Completed }
                }
            }
            if let Index = self.Index(Id) {
                Downloads[Index].State = Consumed ? .Failed : .Completed
                if Consumed { Downloads[Index].ReceivedBytes = 0 }
                Downloads[Index].ErrorMessage = "Extraction failed: \(error.localizedDescription)"
                SaveChanges()
            }
            throw error
        }
    }

    private func PartsForArchive(_ Archive: DownloadItem) -> [DownloadItem] {
        guard let BatchId = Archive.BatchId else { return [Archive] }
        let Name = Archive.FileName.lowercased()
        let Pattern: String
        if let PartOne = Name.range(of: #"\.part[0-9]+\.rar$"#, options: .regularExpression) {
            Pattern = "^" + NSRegularExpression.escapedPattern(for: String(Name[..<PartOne.lowerBound])) + #"\.part[0-9]+\.rar$"#
        } else if Name.range(of: #"\.(?:7z|zip)\.[0-9]{3}$"#, options: .regularExpression) != nil {
            Pattern = "^" + NSRegularExpression.escapedPattern(for: String(Name.dropLast(3))) + #"[0-9]{3}$"#
        } else if let Extension = Name.range(of: #"\.(?:rar|r[0-9]{2,3})$"#, options: .regularExpression) {
            Pattern = "^" + NSRegularExpression.escapedPattern(for: String(Name[..<Extension.lowerBound])) + #"\.(?:rar|r[0-9]{2,3})$"#
        } else if let Extension = Name.range(of: #"\.(?:zip|z[0-9]{2,3})$"#, options: .regularExpression) {
            Pattern = "^" + NSRegularExpression.escapedPattern(for: String(Name[..<Extension.lowerBound])) + #"\.(?:zip|z[0-9]{2,3})$"#
        } else {
            return [Archive]
        }
        let Parts = Downloads.filter {
            $0.BatchId == BatchId && $0.DestinationDirectory == Archive.DestinationDirectory &&
            $0.FileName.lowercased().range(of: Pattern, options: .regularExpression) != nil
        }
        return Parts.contains(where: { $0.Id == Archive.Id }) ? Parts : [Archive]
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

    static func Extract(_ Archive: URL, To Destination: URL, SpaceSaving: Bool = false, Parts: [URL] = []) async throws {
        guard !FileManager.default.fileExists(atPath: Destination.path) else { throw RuntimeError.Message("The extraction destination already exists.") }
        let Tar = URL(fileURLWithPath: "/usr/bin/bsdtar")
        let SevenZip = FindSevenZip()
        let PrefersSevenZip = ["zip", "rar", "7z", "001"].contains(Archive.pathExtension.lowercased())
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
        do {
            if SpaceSaving, try await ArchiveStorage.ExtractReclaiming(Archive, Parts: Parts, To: Staging) {
                try FileManager.default.moveItem(at: Staging, to: Destination)
                try ArchiveStorage.MarkCompleted(Archive, At: Destination)
                return
            }
            let Expanded: Int64
            if let SevenZip {
                let Listing = try await NativeProcess.Checked(SevenZip, ["l", "-slt", "-ba", "-psteamrip.com", "--", Archive.path])
                Expanded = try Listing.components(separatedBy: .newlines).filter { $0.hasPrefix("Size = ") }.reduce(Int64(0)) { Total, Line in
                    guard let Size = Int64(Line.dropFirst(7).trimmingCharacters(in: .whitespaces)), Size >= 0,
                          Total <= Int64.max - Size else { throw RuntimeError.Message("The archive's expanded size is invalid.") }
                    return Total + Size
                }
            } else { Expanded = try await ArchiveStorage.ExpandedSize(Archive) }
            try StorageBudget.Check(at: Destination.deletingLastPathComponent(), Remaining: Expanded)
            try RuntimePaths.CreateDirectory(Staging)
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
        let Details = try await NativeProcess.Checked(Tool, ["l", "-slt", "-ba", "-psteamrip.com", "--", Archive.path])
        var Paths: [(Name: String, Directory: Bool)] = []
        for Entry in Details.components(separatedBy: "\n\n") {
            let Fields = Entry.components(separatedBy: .newlines)
            guard let Field = Fields.first(where: { $0.hasPrefix("Path = ") }) else { continue }
            let Name = String(Field.dropFirst(7)).replacingOccurrences(of: "\\", with: "/")
            try ValidatePath(Name)
            let Directory = Fields.contains("Folder = +") || Fields.contains(where: { $0.hasPrefix("Attributes = D") })
            Paths.append((Name: Name.components(separatedBy: "/").filter { !$0.isEmpty && $0 != "." }.joined(separator: "/").lowercased(), Directory: Directory))
        }
        var Types: [String: Bool] = [:]
        for Path in Paths {
            if let Existing = Types[Path.Name], !Existing || !Path.Directory {
                throw RuntimeError.Message("The archive contains duplicate or conflicting file names.")
            }
            Types[Path.Name] = Path.Directory
        }
        for Path in Paths {
            var Components = Path.Name.components(separatedBy: "/")
            while Components.count > 1 {
                Components.removeLast()
                if Types[Components.joined(separator: "/")] == false {
                    throw RuntimeError.Message("An archive file conflicts with an extraction folder.")
                }
            }
        }
        for Line in Details.components(separatedBy: .newlines) {
            if Line.hasPrefix("Path = ") { try ValidatePath(String(Line.dropFirst(7))) }
            let LinkFields = ["Symbolic Link = ", "Hard Link = ", "Copy Link = "]
            let HasLink = LinkFields.contains { Field in
                Line.hasPrefix(Field) && !Line.dropFirst(Field.count).trimmingCharacters(in: .whitespaces).isEmpty
            }
            let Mode = Line.hasPrefix("Attributes = ")
                ? Line.dropFirst("Attributes = ".count).split(whereSeparator: \.isWhitespace).last?.first
                : nil
            if HasLink || (Mode.map { "lpbcs".contains($0) } ?? false) {
                throw RuntimeError.Message("Archives containing links or special files are not extracted automatically.")
            }
        }
    }

    private static func Unpack(_ Archive: URL, Tool: URL, To Directory: URL) async throws {
        let Arguments = Tool.lastPathComponent == "bsdtar" ? ["-xf", Archive.path, "-C", Directory.path, "--no-same-owner", "--no-same-permissions"] : ["x", "-y", "-psteamrip.com", "-o" + Directory.path, "--", Archive.path]
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
