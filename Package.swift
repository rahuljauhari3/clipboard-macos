// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClipboardMate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "clipboardmate", targets: ["ClipboardMateApp"]) 
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3")
    ],
    targets: [
        .executableTarget(
            name: "ClipboardMateApp",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "Sources/ClipboardMateApp",
            resources: [
                .process("Resources")
            ]
        )
    ]
)

