// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Darniri",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "Darniri",
            targets: ["DarniriApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/mattt/swift-toml.git", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "Darniri",
            dependencies: [
                .product(name: "TOML", package: "swift-toml")
            ],
            path: "Sources/Darniri",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("QuartzCore"),
                .unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "SkyLight"])
            ]
        ),
        .executableTarget(
            name: "DarniriApp",
            dependencies: ["Darniri"],
            path: "Sources/DarniriApp",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "DarniriTests",
            dependencies: ["Darniri"],
            path: "Tests/DarniriTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
