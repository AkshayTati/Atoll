// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Islet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Islet", targets: ["Islet"]),
        .executable(name: "mediaspike", targets: ["mediaspike"])
    ],
    targets: [
        .executableTarget(
            name: "Islet",
            dependencies: ["MediaRemoteShim"],
            path: "Sources/Islet"
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
