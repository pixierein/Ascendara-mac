import Foundation

public enum StorageBudget {
    public static let Headroom: Int64 = 32 * 1024 * 1024

    public static func ExistingAncestor(_ URL: URL) -> URL {
        var Directory = URL.standardizedFileURL
        while !FileManager.default.fileExists(atPath: Directory.path), Directory.path != "/" {
            Directory.deleteLastPathComponent()
        }
        return Directory
    }

    public static func Available(at URL: URL) throws -> Int64 {
        let Directory = ExistingAncestor(URL)
        let Values = try FileManager.default.attributesOfFileSystem(forPath: Directory.path)
        return (Values[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    public static func Volume(at URL: URL) throws -> String {
        let Directory = ExistingAncestor(URL)
        if let Identifier = try Directory.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString { return Identifier }
        let Values = try FileManager.default.attributesOfFileSystem(forPath: Directory.path)
        guard let Identifier = Values[.systemNumber] as? NSNumber else { throw CocoaError(.fileReadUnknown) }
        return Identifier.stringValue
    }

    public static func Required(Remaining: Int64, Reserved: Int64 = 0) -> Int64 {
        let (Sum, Overflow) = max(0, Remaining).addingReportingOverflow(max(0, Reserved))
        let (Total, Overflow2) = Sum.addingReportingOverflow(Headroom)
        return Overflow || Overflow2 ? Int64.max : Total
    }

    public static func Check(at URL: URL, Remaining: Int64, Reserved: Int64 = 0) throws {
        let Free = try Available(at: URL)
        let Needed = Required(Remaining: Remaining, Reserved: Reserved)
        guard Free >= Needed else {
            throw StorageError.Insufficient(Required: Needed, Available: Free, Path: URL.path)
        }
    }

    public static func Measure(_ Root: URL) throws -> Int64 {
        let Keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .fileResourceIdentifierKey]
        let Values = try Root.resourceValues(forKeys: Keys)
        if Values.isSymbolicLink == true { return 0 }
        if Values.isRegularFile == true { return Int64(Values.fileSize ?? 0) }
        var Failure: Error?
        guard let Walker = FileManager.default.enumerator(at: Root, includingPropertiesForKeys: Array(Keys), options: [], errorHandler: { _, Error in
            Failure = Error
            return false
        }) else { throw CocoaError(.fileReadUnknown) }
        var Seen: Set<String> = []
        var Total: Int64 = 0
        for case let File as URL in Walker {
            try Task.checkCancellation()
            let Entry = try File.resourceValues(forKeys: Keys)
            if Entry.isSymbolicLink == true { Walker.skipDescendants(); continue }
            guard Entry.isRegularFile == true else { continue }
            let Identity = Entry.fileResourceIdentifier.map { String(describing: $0) } ?? File.path
            guard Seen.insert(Identity).inserted else { continue }
            let (Next, Overflow) = Total.addingReportingOverflow(Int64(Entry.fileSize ?? 0))
            guard !Overflow else { throw CocoaError(.fileReadTooLarge) }
            Total = Next
        }
        if let Failure { throw Failure }
        return Total
    }
}

public enum StorageError: LocalizedError {
    case Insufficient(Required: Int64, Available: Int64, Path: String)
    public var errorDescription: String? {
        switch self {
        case let .Insufficient(Required, Available, Path):
            return "Not enough space at \(Path). This operation needs \(ByteCountFormatter.string(fromByteCount: Required, countStyle: .file)); \(ByteCountFormatter.string(fromByteCount: Available, countStyle: .file)) is available. Choose another drive or free some space."
        }
    }
}
