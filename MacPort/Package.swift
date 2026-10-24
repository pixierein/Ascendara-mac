// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AscendaraMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ascendara", targets: ["Ascendara"]),
        .executable(name: "AscendaraDownloadWorker", targets: ["AscendaraDownloadWorker"]),
        .executable(name: "AscendaraGameHandler", targets: ["AscendaraGameHandler"]),
        .executable(name: "AscendaraTorrentHandler", targets: ["AscendaraTorrentHandler"]),
        .executable(name: "AscendaraCrashReporter", targets: ["AscendaraCrashReporter"])
    ],
    targets: [
        .executableTarget(name: "AscendaraDownloadWorker", path: "Source/AscendaraDownloadWorker"),
        .executableTarget(name: "AscendaraGameHandler", path: "Source/AscendaraGameHandler"),
        .executableTarget(name: "AscendaraTorrentHandler", path: "Source/AscendaraTorrentHandler"),
        .executableTarget(name: "AscendaraCrashReporter", path: "Source/AscendaraCrashReporter"),
        .executableTarget(
            name: "Ascendara",
            path: "Source/Ascendara",
            exclude: ["Resources/AppIcon.icns"],
            resources: [.process("Resources")]
        )
    ]
)
