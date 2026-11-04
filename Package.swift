// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FujiRecipes",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // Shared with the future Mac / iPhone app.
        .library(name: "FujiKit", targets: ["FujiKit"]),
        .executable(name: "fuji", targets: ["fuji"]),
    ],
    targets: [
        // Recipes, the library folder, the custom-slot codec, PTP over ImageCaptureCore, a simulated camera.
        .target(name: "FujiKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        // `fuji` CLI and `fuji mcp` (the MCP server for agents).
        .executableTarget(
            name: "fuji",
            dependencies: ["FujiKit"],
            exclude: ["Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                                           "-Xlinker", "Sources/fuji/Info.plist"])]
        ),
        .testTarget(name: "FujiKitTests", dependencies: ["FujiKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        // End to end: the built `fuji` binary, as Claude runs it, against the simulated X-E5 and a throwaway library.
        .testTarget(name: "FujiCLITests", dependencies: ["fuji"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
