// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Paso0",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Paso0", path: "Sources/Paso0")
    ]
)
