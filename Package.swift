// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tairi",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "tairi", targets: ["TairiApp"])
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
                "GhosttyDyn"
            ],
            path: "Sources/TairiApp",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ])
            ]
        ),
        .testTarget(
            name: "TairiAppTests",
            dependencies: [
                "TairiApp"
            ],
            path: "Tests/TairiAppTests"
        ),
    ]
)
