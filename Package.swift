// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MemWhole",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "memwhole", targets: ["memwhole"]),
        .library(name: "MemWholeKit", targets: ["MemWholeKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "MemWholeKit",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "memwhole",
            dependencies: ["MemWholeKit"]
        ),
        .testTarget(
            name: "MemWholeKitTests",
            dependencies: ["MemWholeKit"]
        ),
    ]
)
