// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "lumina_mouse_capture",
    platforms: [
        .macOS("10.15")
    ],
    products: [
        .library(name: "lumina-mouse-capture", targets: ["lumina_mouse_capture"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "lumina_mouse_capture",
            dependencies: []
        )
    ]
)
