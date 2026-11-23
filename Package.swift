// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HoverFocus",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CSkyLight"),
        .target(name: "HoverFocusCore"),
        .target(name: "HoverFocusPlatform", dependencies: ["HoverFocusCore", "CSkyLight"]),
        .executableTarget(name: "hoverfocus", dependencies: ["HoverFocusCore", "HoverFocusPlatform"]),
        .executableTarget(name: "hoverfocus-selftest", dependencies: ["HoverFocusCore", "HoverFocusPlatform"]),
    ]
)
