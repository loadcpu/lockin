// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LockIn",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "TimerInputSupport",
            path: "Sources/TimerInputSupport"
        ),
        .executableTarget(
            name: "LockIn",
            dependencies: ["TimerInputSupport"],
            path: "Sources/LockIn",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "TimerInputRuleChecks",
            dependencies: ["TimerInputSupport"],
            path: "Tests/TimerInputRuleChecks"
        ),
    ]
)
