// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MonDial",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "mondialctl", targets: ["mondialctl"]),
        .executable(name: "MonDial", targets: ["MonDialApp"]),
        .library(name: "MonDialKit", targets: ["MonDialKit"])
    ],
    targets: [
        .target(
            name: "MonDialKit",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Foundation")
            ]
        ),
        .executableTarget(
            name: "mondialctl",
            dependencies: ["MonDialKit"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .executableTarget(
            name: "MonDialApp",
            dependencies: ["MonDialKit"],
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
