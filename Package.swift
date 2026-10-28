// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tern",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tern", targets: ["Tern"])],
    targets: [
        .target(name: "TernCore", resources: [.copy("Resources/remote-sessions.py")]),
        .executableTarget(name: "Tern", dependencies: ["TernCore"]),
        .testTarget(name: "TernCoreTests", dependencies: ["TernCore"]),
        .testTarget(name: "TernTests", dependencies: ["Tern", "TernCore"])
    ]
)
