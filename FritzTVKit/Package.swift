// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FritzTVKit",
    platforms: [
        .tvOS(.v17),
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "FritzTVKit", targets: ["FritzTVKit"])
    ],
    targets: [
        .target(name: "FritzTVKit"),
        .testTarget(
            name: "FritzTVKitTests",
            dependencies: ["FritzTVKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
