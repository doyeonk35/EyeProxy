// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EyeProxyKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "EyeProxyKit", targets: ["EyeProxyKit"])],
    dependencies: [.package(path: "../EyeProxyCore")],
    targets: [
        .target(
            name: "EyeProxyKit",
            dependencies: [.product(name: "EyeProxyCore", package: "EyeProxyCore")]
        ),
        .testTarget(name: "EyeProxyKitTests", dependencies: ["EyeProxyKit"]),
    ]
)
