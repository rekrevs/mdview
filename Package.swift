// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mdview",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.5.0"),
        .package(url: "https://github.com/mgriebling/SwiftMath", from: "1.7.0")
    ],
    targets: [
        .executableTarget(
            name: "mdview",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "SwiftMath", package: "SwiftMath")
            ],
            path: "Sources"
        )
    ]
)
