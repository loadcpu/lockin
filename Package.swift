// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LockIn",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "TimerInputSupport",
            path: "Sources/TimerInputSupport"
        ),
        .executableTarget(
            name: "LockIn",
            dependencies: [
                "TimerInputSupport",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/LockIn",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .executableTarget(
            name: "TimerInputRuleChecks",
            dependencies: ["TimerInputSupport"],
            path: "Tests/TimerInputRuleChecks"
        ),
    ]
)
