// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PiNative",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PiKit", targets: ["PiKit"]),
        .executable(name: "PiNative", targets: ["PiNative"]),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/textual", from: "0.1.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.5"),
        .package(url: "https://github.com/raspu/Highlightr", from: "2.2.1"),
    ],
    targets: [
        .target(name: "PiKit", path: "Sources/PiKit"),
        .executableTarget(
            name: "PiNative",
            dependencies: [
                "PiKit",
                .product(name: "Textual", package: "textual"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Highlightr", package: "Highlightr"),
            ],
            path: "Sources/PiNative"
        ),
        .testTarget(name: "PiKitTests", dependencies: ["PiKit"], path: "Tests/PiKitTests"),
    ],
    swiftLanguageModes: [.v5]
)
