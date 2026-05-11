// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ParakeetPTT",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ParakeetPTT", targets: ["ParakeetPTT"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.14.5")
    ],
    targets: [
        .executableTarget(
            name: "ParakeetPTT",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        )
    ]
)
