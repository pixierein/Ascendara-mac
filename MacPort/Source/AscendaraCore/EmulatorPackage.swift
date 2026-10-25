import Foundation

public struct EmulatorPackage {
    public let Address: URL
    public let SHA256: String

    public static func Cask(_ Data: Data, AllowUnchecked: Bool = false) throws -> Self {
        guard let Info = try JSONSerialization.jsonObject(with: Data) as? [String: Any],
              let Link = Info["url"] as? String, let Address = URL(string: Link), Address.scheme == "https",
              ["github.com", "dl.dolphin-emu.org", "buildbot.libretro.com"].contains(Address.host?.lowercased() ?? ""),
              let Digest = Info["sha256"] as? String,
              ValidDigest(Digest) || (AllowUnchecked && Digest == "no_check" && Address.host == "buildbot.libretro.com") else {
            throw Failure.InvalidPackage
        }
        return Self(Address: Address, SHA256: Digest)
    }

    public static func Release(_ Data: Data, Repository: String, Suffix: String, Prefix: String = "") throws -> Self {
        guard let Info = try JSONSerialization.jsonObject(with: Data) as? [String: Any],
              Info["draft"] as? Bool != true, Info["prerelease"] as? Bool != true,
              let Assets = Info["assets"] as? [[String: Any]] else { throw Failure.InvalidPackage }
        let Matches = Assets.filter {
            guard let Name = ($0["name"] as? String)?.lowercased() else { return false }
            return Name.hasPrefix(Prefix.lowercased()) && Name.hasSuffix(Suffix.lowercased())
        }
        guard Matches.count == 1, let Asset = Matches.first,
              let Link = Asset["browser_download_url"] as? String,
              Link.hasPrefix("https://github.com/" + Repository + "/releases/download/"),
              let Address = URL(string: Link), let Digest = Asset["digest"] as? String, Digest.hasPrefix("sha256:"),
              ValidDigest(String(Digest.dropFirst(7))) else { throw Failure.InvalidPackage }
        return Self(Address: Address, SHA256: String(Digest.dropFirst(7)))
    }

    private static func ValidDigest(_ Value: String) -> Bool {
        Value.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil
    }

    public enum Failure: LocalizedError {
        case InvalidPackage
        public var errorDescription: String? { "The emulator catalogue did not return a supported macOS package with a verified checksum." }
    }
}
