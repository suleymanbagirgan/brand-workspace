// swift-tools-version: 6.0
import PackageDescription

// Command Line Tools içindeki Swift Testing çerçevesi için yol (Xcode kuruluysa gerekmez).
let cltFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

let package = Package(
    name: "MarkaCalismaAlani",
    defaultLocalization: "tr",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MarkaApp", targets: ["MarkaApp"]),
        .library(name: "MarkaCore", targets: ["MarkaCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "MarkaCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "MarkaApp",
            dependencies: ["MarkaCore"]
        ),
        .executableTarget(
            name: "MarkaDogrula",
            dependencies: ["MarkaCore"]
        ),
        .testTarget(
            name: "MarkaCoreTests",
            dependencies: ["MarkaCore"]
        ),
    ]
)
