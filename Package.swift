// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tairi",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "tairi", targets: ["TairiApp"]),
    ],
    targets: [
        .target(
            name: "GhosttyDyn",
            path: "Sources/GhosttyDyn",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "TairiApp",
            dependencies: [
                "GhosttyDyn",
            ],
            path: "Sources/TairiApp",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
    ]
)
