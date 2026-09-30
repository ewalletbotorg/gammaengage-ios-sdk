// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GammaEngage",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "GammaEngage", targets: ["GammaEngage"]),
    ],
    targets: [
        .target(name: "GammaEngage"),
        .testTarget(name: "GammaEngageTests", dependencies: ["GammaEngage"]),
    ]
)
