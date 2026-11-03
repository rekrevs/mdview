// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mdview",
    platforms: [.macOS(.v13)],
    targets: [
        // Shared by the reader app and the Quick Look extension. The renderer resources stay
        // in the app target (mdview_mdview.bundle); bundle.sh copies them into both bundles.
        .target(name: "ReaderCore", path: "Sources/ReaderCore"),
        .executableTarget(name: "mdview", dependencies: ["ReaderCore"], path: "Sources",
                          exclude: ["ReaderCore", "QuickLook"], resources: [.copy("Resources")]),
        // The Quick Look preview extension executable (packaged as mdviewQuickLook.appex).
        .executableTarget(name: "mdviewQuickLook", dependencies: ["ReaderCore"], path: "Sources/QuickLook",
                          linkerSettings: [.linkedFramework("QuickLookUI"), .linkedFramework("WebKit")]),
        .testTarget(name: "mdviewTests", dependencies: ["mdview", "ReaderCore"], path: "Tests/mdviewTests")
    ]
)
