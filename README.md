# libArchive

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20Catalyst-lightgrey)](https://developer.apple.com)
[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

为 Apple 全平台预编译的 [libarchive](https://github.com/libarchive/libarchive) 静态 XCFramework，支持通过 Swift Package Manager 直接集成。

## 特性

- 📦 **多平台支持**：iOS、macOS、tvOS、watchOS、Mac Catalyst
- 🏗️ **多架构支持**：arm64、x86_64（模拟器 fat binary）、arm64_32（watchOS 真机）
- 🔧 **静态链接**：所有依赖（liblzma、libzstd、liblz4）已合并进单一 `.a` 文件，无需额外配置
- 🐦 **Swift 友好**：内置 `module.modulemap`，可直接 `import libarchive`
- 🗜️ **全格式支持**：tar、zip、7z、gz、bz2、xz、zstd、lz4、rar、iso9660、cab 等

## 支持的压缩格式

| 格式 | 读取 | 写入 | 依赖 |
|------|------|------|------|
| gzip / deflate | ✅ | ✅ | 系统 zlib |
| bzip2 | ✅ | ✅ | 系统 libbz2 |
| xz / lzma | ✅ | ✅ | 内置 liblzma |
| zstd | ✅ | ✅ | 内置 libzstd |
| lz4 | ✅ | ✅ | 内置 liblz4 |

## 支持的归档格式

tar、pax、cpio、zip、7-Zip、ar、mtree、xar、lha/lzh、rar、cab、iso9660、shar 等

## 平台要求

| 平台 | 最低版本 |
|------|---------|
| iOS | 13.0 |
| macOS | 10.15 |
| tvOS | 13.0 |
| watchOS | 6.0 |
| Mac Catalyst | 14.0 |

## 安装

### Swift Package Manager

在 `Package.swift` 中添加依赖：

```swift
dependencies: [
    .package(url: "https://github.com/<owner>/libArchive.git", from: "<version>"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["libArchive"]
    ),
]
```

或在 Xcode 中通过 **File → Add Package Dependencies** 搜索本仓库 URL 添加。

## 使用

### Swift

```swift
import libarchive

// 读取归档文件
let archive = archive_read_new()
archive_read_support_filter_all(archive)
archive_read_support_format_all(archive)

let r = archive_read_open_filename(archive, "/path/to/archive.tar.gz", 10240)
guard r == ARCHIVE_OK else {
    print("Failed to open archive")
    return
}

var entry: OpaquePointer?
while archive_read_next_header(archive, &entry) == ARCHIVE_OK {
    let name = String(cString: archive_entry_pathname(entry!))
    print("Entry: \(name)")
    archive_read_data_skip(archive)
}

archive_read_free(archive)
```

### C / Objective-C

```objc
#import <libarchive/archive.h>
#import <libarchive/archive_entry.h>

struct archive *a = archive_read_new();
archive_read_support_filter_all(a);
archive_read_support_format_all(a);
// ...
archive_read_free(a);
```

## 构建 XCFramework

如需从源码重新构建，运行项目根目录下的构建脚本：

```bash
chmod +x build_libarchive_apple_all_xcframework.sh
./build_libarchive_apple_all_xcframework.sh
```

脚本会自动：

1. 获取 libarchive、xz、zstd、lz4 的最新 Release 版本
2. 并发交叉编译所有 Apple 平台的静态库
3. 将第三方依赖合并进 `libarchive.a`（解决 Undefined Symbol 问题）
4. 生成 `module.modulemap`（Swift 导入支持）
5. 打包为 `libarchive-apple-build/libArchive.xcframework`
6. 清理所有中间文件

### 构建依赖

- macOS + Xcode（含命令行工具）
- CMake（`brew install cmake`）
- Git

## XCFramework 结构

```
libArchive.xcframework/
├── ios-arm64/                          # iOS 真机
├── ios-arm64_x86_64-simulator/         # iOS 模拟器（fat binary）
├── ios-arm64-maccatalyst/              # Mac Catalyst
├── macos-arm64_x86_64/                 # macOS（fat binary）
├── tvos-arm64/                         # tvOS 真机
├── tvos-arm64_x86_64-simulator/        # tvOS 模拟器（fat binary）
├── watchos-arm64_32/                   # watchOS 真机
└── watchos-arm64_x86_64-simulator/     # watchOS 模拟器（fat binary）
```

每个切片均包含：
- `libarchive.a`（含 liblzma、libzstd、liblz4 的合并静态库）
- `archive.h` / `archive_entry.h`
- `module.modulemap`

## License

本项目遵循 [MIT License](LICENSE)。

libarchive 本身遵循 [New BSD License](https://github.com/libarchive/libarchive/blob/master/COPYING)。
