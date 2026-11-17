// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SeichiCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SeichiCore", targets: ["SeichiCore"]),
    ],
    targets: [
        .target(name: "SeichiCore"),
        .testTarget(name: "SeichiCoreTests", dependencies: ["SeichiCore"]),
    ]
)
