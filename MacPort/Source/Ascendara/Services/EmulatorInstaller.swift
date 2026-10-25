import AppKit
import Combine
import CryptoKit
import AscendaraCore

@MainActor
final class EmulatorInstaller: ObservableObject {
    @Published private(set) var Installing = false
    @Published private(set) var Status = ""
    private let Directory = AppPaths.Support.appendingPathComponent("Emulators", isDirectory: true)
    private static let Casks = ["dolphin": "dolphin", "pcsx2": "pcsx2", "flycast": "flycast", "xemu": "xemu", "retroarch": "retroarch-metal"]
    private static let AppNames = ["dolphin": "Dolphin.app", "pcsx2": "PCSX2.app", "flycast": "Flycast.app", "xemu": "xemu.app", "retroarch": "RetroArch.app", "ppsspp": "PPSSPPSDL.app", "duckstation": "DuckStation.app", "rpcs3": "RPCS3.app", "melonds": "melonDS.app"]
    private static let Cores = ["nes": "fceumm", "snes": "snes9x", "gb": "gambatte", "gbc": "gambatte", "gba": "mgba", "n64": "mupen64plus_next", "ps1": "swanstation", "genesis": "genesis_plus_gx", "megadrive": "genesis_plus_gx"]

    static func Supports(_ Adapter: String) -> Bool { AppNames[Adapter] != nil }

    func FindInstalled(_ Adapter: String) -> URL? {
        guard let Name = Self.AppNames[Adapter] else { return nil }
        let Candidates = [Directory.appendingPathComponent(Adapter).appendingPathComponent(Name),
                          URL(fileURLWithPath: "/Applications").appendingPathComponent(Name),
                          FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").appendingPathComponent(Name)]
        return Candidates.first { Bundle(url: $0)?.executableURL != nil }
    }

    func Install(Adapter: String, Platform: String) async throws -> (App: URL, Core: URL?) {
        guard !Installing, let Name = Self.AppNames[Adapter] else {
            throw AppFailure.Message("Choose a supported automatic installer, or select an emulator manually.")
        }
        Installing = true
        defer { Installing = false }
        var App = FindInstalled(Adapter)
        if App == nil {
            Status = "Checking the emulator release…"
            let Package = try await Package(Adapter)
            let Working = Directory.appendingPathComponent(".setup-" + UUID().uuidString, isDirectory: true)
            try RuntimePaths.CreateDirectory(Working)
            defer { try? FileManager.default.removeItem(at: Working) }
            let Archive = Working.appendingPathComponent(Package.Address.lastPathComponent)
            Status = "Downloading the emulator…"
            try await Download(Package.Address, To: Archive)
            if Package.SHA256 != "no_check" {
                let Actual = try await Task.detached(priority: .utility) { try Self.Hash(Archive) }.value
                guard Actual.caseInsensitiveCompare(Package.SHA256) == .orderedSame else { throw AppFailure.Message("The emulator download checksum did not match.") }
            }
            Status = "Installing the emulator…"
            let Unpacked = Working.appendingPathComponent("Unpacked", isDirectory: true)
            try RuntimePaths.CreateDirectory(Unpacked)
            var Mounted = false
            do {
                if Archive.pathExtension.lowercased() == "dmg" {
                    _ = try await NativeProcess.Checked(URLFrom("/usr/bin/hdiutil"), ["attach", "-readonly", "-nobrowse", "-mountpoint", Unpacked.path, Archive.path])
                    Mounted = true
                } else if Archive.pathExtension.lowercased() == "zip" {
                    _ = try await NativeProcess.Checked(URLFrom("/usr/bin/ditto"), ["-x", "-k", Archive.path, Unpacked.path])
                } else if Archive.pathExtension.lowercased() == "7z" {
                    guard let Tool = ArchiveExtractor.FindSevenZip() else { throw AppFailure.Message("The bundled 7-Zip runtime is missing. Rebuild the app to install this emulator.") }
                    let Listing = try await NativeProcess.Checked(Tool, ["l", "-slt", "-ba", "--", Archive.path])
                    for Line in Listing.components(separatedBy: .newlines) where Line.hasPrefix("Path = ") {
                        try ArchiveExtractor.ValidatePath(String(Line.dropFirst(7)))
                    }
                    _ = try await NativeProcess.Checked(Tool, ["x", "-y", "-o" + Unpacked.path, "--", Archive.path])
                } else {
                    let Listing = try await NativeProcess.Checked(URLFrom("/usr/bin/bsdtar"), ["-tf", Archive.path])
                    for Path in Listing.components(separatedBy: .newlines) where !Path.isEmpty { try ArchiveExtractor.ValidatePath(Path) }
                    _ = try await NativeProcess.Checked(URLFrom("/usr/bin/bsdtar"), ["-xf", Archive.path, "-C", Unpacked.path, "--no-same-owner", "--no-same-permissions"])
                }
                guard let Walker = FileManager.default.enumerator(at: Unpacked, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]),
                      let Source = Walker.compactMap({ $0 as? URL }).first(where: {
                          let Candidate = $0.deletingPathExtension().lastPathComponent.lowercased()
                          let Expected = String(Name.dropLast(4)).lowercased()
                          return $0.pathExtension.lowercased() == "app" && (Candidate == Expected || Candidate.hasPrefix(Expected + "-")) && Bundle(url: $0)?.executableURL != nil
                      }) else {
                    throw AppFailure.Message("The downloaded package does not contain a launchable macOS app.")
                }
                _ = try await Architecture(Source)
                let Target = Directory.appendingPathComponent(Adapter).appendingPathComponent(Name)
                try RuntimePaths.CreateDirectory(Target.deletingLastPathComponent())
                guard !FileManager.default.fileExists(atPath: Target.path) else { throw AppFailure.Message("An emulator already occupies the installation folder.") }
                let Pending = Target.deletingLastPathComponent().appendingPathComponent(".install-" + UUID().uuidString + ".app")
                do {
                    _ = try await NativeProcess.Checked(URLFrom("/usr/bin/ditto"), [Source.path, Pending.path])
                    guard Bundle(url: Pending)?.executableURL != nil else { throw AppFailure.Message("The copied emulator is incomplete.") }
                    try FileManager.default.moveItem(at: Pending, to: Target)
                } catch { try? FileManager.default.removeItem(at: Pending); throw error }
                App = Target
                if Mounted { _ = try await NativeProcess.Checked(URLFrom("/usr/bin/hdiutil"), ["detach", Unpacked.path]); Mounted = false }
            } catch {
                if Mounted { _ = try? await NativeProcess.Run(URLFrom("/usr/bin/hdiutil"), ["detach", Unpacked.path]) }
                throw error
            }
        }
        guard let App else { throw AppFailure.Message("The emulator installation could not be found.") }
        let Architecture = try await Architecture(App)
        let Core = Adapter == "retroarch" ? try await InstallCore(Platform, Architecture: Architecture) : nil
        Status = "Emulator ready."
        return (App, Core)
    }

    private func Package(_ Adapter: String) async throws -> EmulatorPackage {
        let Address: URL
        let Repository: String
        let Suffix: String
        var Prefix = ""
        switch Adapter {
        case "duckstation": Repository = "stenzek/duckstation"; Suffix = "duckstation-mac-release.zip"
        case "rpcs3":
            #if arch(arm64)
            Repository = "RPCS3/rpcs3-binaries-mac-arm64"; Suffix = "_macos_aarch64.7z"
            #else
            Repository = "RPCS3/rpcs3-binaries-mac"; Suffix = "_macos.7z"
            #endif
        case "melonds": Repository = "melonDS-emu/melonDS"; Suffix = "-macOS-universal.zip"
        case "ppsspp": Repository = "hrydgard/ppsspp"; Suffix = ".zip"; Prefix = "PPSSPPSDL-macOS-"
        default: Repository = ""; Suffix = ""
        }
        if let Cask = Self.Casks[Adapter] {
            Address = URL(string: "https://formulae.brew.sh/api/cask/\(Cask).json")!
        } else if !Repository.isEmpty {
            Address = URL(string: "https://api.github.com/repos/\(Repository)/releases/latest")!
        } else { throw AppFailure.Message("No automatic package is available for this emulator.") }
        var Request = URLRequest(url: Address, timeoutInterval: 30)
        Request.setValue("Ascendara-Mac/" + AppVersion.Current, forHTTPHeaderField: "User-Agent")
        let (Data, Response) = try await URLSession.shared.data(for: Request)
        guard (Response as? HTTPURLResponse)?.statusCode == 200 else { throw AppFailure.Message("The emulator release catalogue is unavailable. Try again later.") }
        return Repository.isEmpty ? try EmulatorPackage.Cask(Data, AllowUnchecked: Adapter == "retroarch") : try EmulatorPackage.Release(Data, Repository: Repository, Suffix: Suffix, Prefix: Prefix)
    }

    private func Architecture(_ App: URL) async throws -> String {
        guard let Executable = Bundle(url: App)?.executableURL else { throw AppFailure.Message("The emulator executable is missing.") }
        let Architectures = try await NativeProcess.Checked(URLFrom("/usr/bin/lipo"), ["-archs", Executable.path])
        #if arch(arm64)
        let Architecture = Architectures.split(whereSeparator: \.isWhitespace).contains("arm64") ? "arm64" : "x86_64"
        #else
        let Architecture = "x86_64"
        #endif
        guard Architectures.split(whereSeparator: \.isWhitespace).contains(Substring(Architecture)) else {
            throw AppFailure.Message("This emulator package does not support this Mac's architecture.")
        }
        return Architecture
    }

    private func InstallCore(_ Platform: String, Architecture: String) async throws -> URL? {
        guard let Name = Self.Cores[Platform] else { return nil }
        let Cores = Directory.appendingPathComponent("Cores/" + Architecture, isDirectory: true)
        try RuntimePaths.CreateDirectory(Cores)
        let Target = Cores.appendingPathComponent(Name + "_libretro.dylib")
        if FileManager.default.fileExists(atPath: Target.path) { return Target }
        Status = "Installing the console core…"
        let Address = URL(string: "https://buildbot.libretro.com/nightly/apple/osx/\(Architecture)/latest/\(Name)_libretro.dylib.zip")!
        let Working = Cores.appendingPathComponent(".core-" + UUID().uuidString)
        try RuntimePaths.CreateDirectory(Working)
        defer { try? FileManager.default.removeItem(at: Working) }
        let Archive = Working.appendingPathComponent("core.zip")
        try await Download(Address, To: Archive)
        let Unpacked = Working.appendingPathComponent("Unpacked")
        try await ArchiveExtractor.Extract(Archive, To: Unpacked)
        let Core = Unpacked.appendingPathComponent(Target.lastPathComponent)
        guard FileManager.default.fileExists(atPath: Core.path) else { throw AppFailure.Message("The console core was missing from its package.") }
        _ = try await NativeProcess.Checked(URLFrom("/usr/bin/lipo"), ["-verify_arch", Architecture, Core.path])
        try FileManager.default.moveItem(at: Core, to: Target)
        return Target
    }

    private func Download(_ Address: URL, To Target: URL) async throws {
        var Head = URLRequest(url: Address, timeoutInterval: 20); Head.httpMethod = "HEAD"
        if let (_, Response) = try? await URLSession.shared.data(for: Head), Response.expectedContentLength > 0 {
            let Size = Response.expectedContentLength
            try StorageBudget.Check(at: Target.deletingLastPathComponent(), Remaining: Size > Int64.max / 3 ? Int64.max : Size * 3)
        }
        let (Temporary, Response) = try await URLSession.shared.download(for: URLRequest(url: Address, timeoutInterval: 300))
        defer { try? FileManager.default.removeItem(at: Temporary) }
        guard (Response as? HTTPURLResponse)?.statusCode == 200, Response.url?.scheme == "https" else { throw AppFailure.Message("The emulator download failed.") }
        try FileManager.default.moveItem(at: Temporary, to: Target)
    }

    private nonisolated static func Hash(_ File: URL) throws -> String {
        let Handle = try FileHandle(forReadingFrom: File)
        defer { try? Handle.close() }
        var Hash = SHA256()
        while let Data = try Handle.read(upToCount: 1024 * 1024), !Data.isEmpty { Hash.update(data: Data) }
        return Hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func URLFrom(_ Path: String) -> URL { URL(fileURLWithPath: Path) }
}
