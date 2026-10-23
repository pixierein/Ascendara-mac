// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AscendaraMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Ascendara", targets: ["Ascendara"])],
    targets: [
        .executableTarget(
            name: "Ascendara",
            exclude: ["Resources/AppIcon.icns"],
            resources: [.process("Resources")]
        )
    ]
)
