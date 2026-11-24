// swift-tools-version:5.9
// OPUlation's core (pairing, her face, the key song, her brain, his circuit) as a package, so `swift test` checks it
// against the web version's vectors (data/vectors.json, vectors2.json) on macOS or Linux. The app compiles the same files.
import PackageDescription

let package = Package(
    name: "OPUlationCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "OPUlationCore", targets: ["OPUlationCore"])],
    dependencies: [.package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"4.0.0")],
    targets: [
        .target(name: "OPUlationCore",
                dependencies: [.product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))],
                path: "OPUlation/Core"),
        .testTarget(name: "OPUlationCoreTests", dependencies: ["OPUlationCore"], path: "Tests/CoreTests"),
    ]
)
