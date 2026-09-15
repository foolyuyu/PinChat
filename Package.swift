// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PinChat",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PinChat", targets: ["PinChat"])
    ],
    targets: [
        .executableTarget(
            name: "PinChat",
            path: "Sources/PinChat"
        ),
        .testTarget(
            name: "PinChatTests",
            dependencies: ["PinChat"],
            path: "Tests/PinChatTests"
        )
    ]
)
