// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChallengeCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "ChallengeCore", targets: ["ChallengeCore"]),
    ],
    targets: [
        .target(name: "ChallengeCore"),
        .testTarget(name: "ChallengeCoreTests", dependencies: ["ChallengeCore"]),
    ]
)
