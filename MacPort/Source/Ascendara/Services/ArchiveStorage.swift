import Foundation
import ArchiveSupport
import AscendaraCore

enum ArchiveStorage {
    private struct Recovery: Codable {
        let Staging: URL
        var Sources: [URL]?
        var Completed: URL?
    }
    static func Marker(_ Archive: URL) -> URL { URL(fileURLWithPath: Archive.path + ".consuming") }

    static func CompletedPath(_ Archive: URL) -> URL? {
        guard let Recovery = try? AppPaths.Read(Recovery.self, From: Marker(Archive)), let Output = Recovery.Completed,
              FileManager.default.fileExists(atPath: Output.path) else { return nil }
        return Output
    }

    static func MarkCompleted(_ Archive: URL, At Output: URL) throws {
        guard FileManager.default.fileExists(atPath: Marker(Archive).path) else { return }
        var Value = try AppPaths.Read(Recovery.self, From: Marker(Archive))
        Value.Completed = Output
        try AppPaths.Write(Value, To: Marker(Archive))
    }

    static func CleanInterruptedStaging(_ Archive: URL) {
        guard let Recovery = try? AppPaths.Read(Recovery.self, From: Marker(Archive)),
              Recovery.Staging.lastPathComponent.hasPrefix(".ascendara-extract-"), Recovery.Staging.pathComponents.count > 3 else { return }
        try? FileManager.default.removeItem(at: Recovery.Staging)
    }

    static func Sources(_ Archive: URL) -> [URL] {
        (try? AppPaths.Read(Recovery.self, From: Marker(Archive)))?.Sources ?? [Archive]
    }

    static func RemoveConsumedSources(_ Archive: URL) {
        for Source in Sources(Archive) { try? FileManager.default.removeItem(at: Source) }
        try? FileManager.default.removeItem(at: Marker(Archive))
    }

    static func ExpandedSize(_ Archive: URL) async throws -> Int64 {
        try await Task.detached(priority: .utility) {
            var Size: Int64 = 0
            var Error = [CChar](repeating: 0, count: 2048)
            guard AAArchiveSize(Archive.path, &Size, &Error, Error.count) == 0 else {
                throw RuntimeError.Message(String(cString: Error))
            }
            return Size
        }.value
    }

    static func ExtractReclaiming(_ Archive: URL, Parts: [URL], To Destination: URL) async throws -> Bool {
        let Sources = Parts.isEmpty ? [Archive] : Parts
        let Volume = try StorageBudget.Volume(at: Destination.deletingLastPathComponent())
        for Source in Sources {
            guard try StorageBudget.Volume(at: Source) == Volume else { return false }
        }
        guard AACanReclaim(Archive.deletingLastPathComponent().path) == 1 else { return false }
        let Native = try await Task.detached(priority: .utility) {
            guard Sources.count == 1 else { return false }
            var Plan = AAArchivePlan()
            var Error = [CChar](repeating: 0, count: 2048)
            guard AAArchiveInspect(Archive.path, &Plan, &Error, Error.count) == 0 else { return false }
            try StorageBudget.Check(at: Destination.deletingLastPathComponent(), Remaining: Plan.AdditionalBytes)
            try RuntimePaths.CreateDirectory(Destination)
            try AppPaths.Write(Recovery(Staging: Destination, Sources: Sources), To: Marker(Archive))
            guard AAArchiveExtract(Archive.path, Destination.path, 1, &Error, Error.count) == 0 else {
                throw RuntimeError.Message("Space-saving extraction stopped: \(String(cString: Error)). The archive must be downloaded again.")
            }
            return true
        }.value
        if Native { return true }
        guard let SevenZip = ArchiveExtractor.FindSevenZip(),
              let Tool = [SevenZip.deletingLastPathComponent().appendingPathComponent("7zz-reclaim"),
                          Bundle.main.resourceURL?.appendingPathComponent("Tools/7zz-reclaim")].compactMap({ $0 }).first(where: {
                  FileManager.default.isExecutableFile(atPath: $0.path)
              }) else { return false }
        let Working = Destination.deletingLastPathComponent().appendingPathComponent(".ascendara-plan-" + UUID().uuidString)
        try RuntimePaths.CreateDirectory(Working)
        defer { try? FileManager.default.removeItem(at: Working) }
        let Manifest = Working.appendingPathComponent("sources.txt")
        guard Sources.allSatisfy({ !$0.path.contains("\n") && !$0.path.contains("\r") }) else {
            throw RuntimeError.Message("Archive volume names cannot contain line breaks.")
        }
        try (Sources.map(\.path).joined(separator: "\n") + "\n").write(to: Manifest, atomically: true, encoding: .utf8)
        let Plan = Working.appendingPathComponent("plan.bin")
        var Environment = ProcessInfo.processInfo.environment
        Environment["ASCENDARA_ARCHIVE_SOURCES"] = Manifest.path
        Environment["ASCENDARA_ARCHIVE_PLAN"] = Plan.path
        Environment["ASCENDARA_ARCHIVE_MODE"] = "inspect"
        let Arguments = ["x", "-y", "-bb0", "-bsp0", "-mmt=1", "-psteamrip.com", "-o" + Destination.path, "--", Archive.path]
        do {
            _ = try await NativeProcess.Checked(Tool, Arguments, Environment: Environment)
        } catch {
            try? FileManager.default.removeItem(at: Destination)
            return false
        }
        try FileManager.default.removeItem(at: Destination)
        struct SpaceEstimate: Decodable { let ExpandedBytes: Int64; let AdditionalBytes: Int64 }
        let Estimate = try AppPaths.Read(SpaceEstimate.self, From: URL(fileURLWithPath: Plan.path + ".json"))
        guard Estimate.AdditionalBytes >= 0, Estimate.ExpandedBytes >= Estimate.AdditionalBytes else {
            throw RuntimeError.Message("The archive space estimate is invalid.")
        }
        try StorageBudget.Check(at: Destination.deletingLastPathComponent(), Remaining: Estimate.AdditionalBytes)
        try RuntimePaths.CreateDirectory(Destination)
        try AppPaths.Write(Recovery(Staging: Destination, Sources: Sources), To: Marker(Archive))
        Environment["ASCENDARA_ARCHIVE_MODE"] = "replay"
        do {
            _ = try await NativeProcess.Checked(Tool, Arguments, Environment: Environment)
        } catch {
            throw RuntimeError.Message("Space-saving extraction stopped: \(error.localizedDescription). Every archive volume must be downloaded again.")
        }
        return true
    }
}
