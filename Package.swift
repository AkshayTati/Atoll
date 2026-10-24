// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Atoll",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Atoll", targets: ["Atoll"]),
        .executable(name: "mediaspike", targets: ["mediaspike"])
    ],
    targets: [
        .executableTarget(
            name: "Atoll",
            path: "Sources/Atoll"
        ),
        .target(
            name: "MediaRemoteShim",
            path: "Sources/MediaRemoteShim",
            cSettings: [
                .unsafeFlags(["-fblocks"])
            ]
        ),
        .executableTarget(
            name: "mediaspike",
            dependencies: ["MediaRemoteShim"],
            path: "Sources/mediaspike"
        )
    ]
)
