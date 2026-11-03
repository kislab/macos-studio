// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "MacOSStudio", platforms: [.macOS(.v13)],
    products: [.executable(name: "MacOSStudio", targets: ["MacOSStudio"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "StudioCore"),
        .executableTarget(name: "MacOSStudio", dependencies: ["StudioCore", .product(name: "Sparkle", package: "Sparkle")], resources: [.copy("Resources/models.json"), .copy("Resources/InstallerIcons"), .copy("Resources/Hardware")]),
        .executableTarget(name: "StudioChecks", dependencies: ["StudioCore"], path: "Tests/StudioCoreTests")
    ])
