// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TacticsLabMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TacticsLabMac", targets: ["TacticsLabMac"])],
    targets: [
        .target(name: "TacticsCore"),
        .executableTarget(name: "TacticsLabMac", dependencies: ["TacticsCore"]),
        .testTarget(name: "TacticsCoreTests", dependencies: ["TacticsCore"])
    ]
)
