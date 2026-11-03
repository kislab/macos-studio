// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "MacOSStudio", platforms: [.macOS(.v13)],
    products: [.executable(name: "MacOSStudio", targets: ["MacOSStudio"])],
    targets: [
        .target(name: "StudioCore"),
        .executableTarget(name: "MacOSStudio", dependencies: ["StudioCore"], resources: [.copy("Resources/models.json"), .copy("Resources/InstallerIcons"), .copy("Resources/Hardware")]),
        .executableTarget(name: "StudioChecks", dependencies: ["StudioCore"], path: "Tests/StudioCoreTests")
    ])
