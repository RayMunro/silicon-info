// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SiliconInfo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SiliconWidget",
            linkerSettings: [.linkedFramework("IOKit")]
        )
    ]
)
