// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CallTape",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "CallTape",
            path: "Sources/CallTape"
        )
    ],
    swiftLanguageModes: [.v5]
)
