// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "libarchive",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "libarchive",
            targets: ["libarchive"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .binaryTarget(
            name: "libarchive",
            path: "libarchive-apple-build/libarchive.xcframework"
        ),
        .testTarget(
            name: "libarchiveTests",
            dependencies: ["libarchive"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
