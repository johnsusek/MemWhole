// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MemWhole",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "memwhole", targets: ["memwhole"]),
    ],
    targets: [
        .executableTarget(
            name: "memwhole",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
    ]
)
