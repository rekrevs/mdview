// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mdview",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "mdview", path: "Sources", resources: [.copy("Resources")]),
        .testTarget(name: "mdviewTests", dependencies: ["mdview"], path: "Tests/mdviewTests")
    ]
)
