// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "libArchive",
    platforms: [
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .macOS(.v10_15),
        .macCatalyst(.v14),
    ],
    products: [
        // 对外暴露 libarchive XCFramework，其他项目通过 SPM 依赖此包即可使用
        .library(
            name: "libarchive",
            targets: ["libarchive"]
        ),
    ],
    targets: [
        // ===== 二进制目标：libarchive XCFramework =====
        // 本地开发时使用 path 指向本地 XCFramework
        // 发布到 GitHub Release 后，改用 url + checksum 方式：
        //
        // .binaryTarget(
        //     name: "libarchive",
        //     url: "https://github.com/<owner>/libArchive/releases/download/<tag>/libArchive.xcframework.zip",
        //     checksum: "e9be266dcd5faee3e5967e38f2000af78fabf0c2649aeec9f073595dacf4c46f"
        // ),
        .binaryTarget(
            name: "libarchive",
            path: "libarchive-apple-build/libarchive.xcframework"
        ),
        .testTarget(
            name: "libArchiveTests",
            dependencies: ["libarchive"]
        ),
    ]
)
