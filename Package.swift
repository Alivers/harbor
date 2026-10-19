// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Harbor",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "Harbor", targets: ["Harbor"])],
    targets: [
        .target(name: "HarborCore"),
        .executableTarget(name: "Harbor", dependencies: ["HarborCore"]),
        .executableTarget(name: "HarborChecks", dependencies: ["HarborCore"], path: "Tests/HarborCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
