// swift-tools-version:5.9
// Unit tests for Dime's pure logic. Run with `swift test` from the repository root.
// The iOS app itself is built from app/dime.xcodeproj.

import PackageDescription

let package = Package(
    name: "DimeLogic",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "DimeSchedule",
            path: "app/dime/Data",
            exclude: ["Helper.swift", "DataController.swift", "MainModel.xcdatamodeld"],
            sources: ["Schedule.swift"]
        ),
        .testTarget(
            name: "DimeScheduleTests",
            dependencies: ["DimeSchedule"],
            path: "Tests/DimeScheduleTests"
        )
    ]
)
