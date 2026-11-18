// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoorKit",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "NoorKit", targets: ["NoorKit"])
    ],
    targets: [
        .target(
            name: "NoorKit",
            resources: [.process("quran.json"), .process("adhkar.json")]
        )
    ]
)
