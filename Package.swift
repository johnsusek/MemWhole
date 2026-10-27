// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MemWhole",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "memwhole", targets: ["memwhole"]),
        .library(name: "MemWholeKit", targets: ["MemWholeKit"]),
    ],
    targets: [
        .target(
            name: "MemWholeKit",
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
