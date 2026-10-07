// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Perasma", platforms: [.macOS("26.0")], products: [.executable(name: "Perasma", targets: ["Perasma"])], targets: [.target(name: "PerasmaCore"), .executableTarget(name: "Perasma", dependencies: ["PerasmaCore"]), .testTarget(name: "PerasmaCoreTests", dependencies: ["PerasmaCore"])], swiftLanguageModes: [.v5])
