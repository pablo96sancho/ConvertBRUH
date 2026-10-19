// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ConvertBRUH",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ConvertBRUH",
            path: "Sources/ConvertBRUH"
        ),
        .testTarget(
            name: "ConvertBRUHTests",
            dependencies: ["ConvertBRUH"],
            path: "Tests/ConvertBRUHTests"
        ),
    ]
)
