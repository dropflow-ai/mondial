// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ScreenMix",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "screenmixctl", targets: ["screenmixctl"]),
        .executable(name: "ScreenMix", targets: ["ScreenMixApp"]),
        .library(name: "ScreenMixKit", targets: ["ScreenMixKit"])
    ],
    targets: [
        .target(
            name: "ScreenMixKit",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation")
            ]
        ),
        .executableTarget(
            name: "screenmixctl",
            dependencies: ["ScreenMixKit"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .executableTarget(
            name: "ScreenMixApp",
            dependencies: ["ScreenMixKit"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
