# libarchive for Swift

[![Swift](https://img.shields.io/badge/Swift-6.3-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20macOS-lightgrey.svg)](https://developer.apple.com)
[libarchive](https://github.com/libarchive/libarchive) 的 Swift Package Manager 封装,为 iOS 和 macOS 应用提供强大的多格式压缩与解压缩功能。

## 📋 简介

本项目将知名的 libarchive C 库封装为 Swift Package Manager 包,支持在 iOS 和 macOS 平台上直接使用 Swift 代码处理各种压缩格式。

### 什么是 libarchive?

libarchive 是一个功能强大、高效的多格式压缩与解压缩库,广泛用于 Unix 和 Linux 系统,支持读取和写入多种压缩格式。

### 特性

- ✅ **多格式支持**: 支持 tar、zip、cpio、7zip、rar 等多种格式
- ✅ **跨平台**: 支持 iOS 和 macOS 平台
- ✅ **易用性**: 通过 Swift Package Manager 集成,无需手动配置
- ✅ **高性能**: 基于成熟的 C 库,处理速度快
- ✅ **静态库**: 包含完整的 xcframework,无外部依赖

## 🚀 支持的格式

### 读取格式 (Read Support)
- **压缩格式**: gzip、bzip2、lz4、xz、zstd、lzop、grzip、lrzip、lzip、lzma等
- **归档格式**: tar (old gnu、gnu、pax、ustar、v7)、cpio (odc、newc、sv4c、sv4crc)、7zip、iso9660、rar、ar、cab、mtree、warc、xar、zip 等

### 写入格式 (Write Support)
- **压缩格式**: gzip、bzip2、lz4、xz、zstd、lzop、uuencode、base64 等
- **归档格式**: tar (old gnu、gnu、pax、ustar、v7)、cpio (odc、newc)、7zip、ar、iso9660、mtree、warc、xar、zip 等

## 📦 安装

### Swift Package Manager

在 Xcode 项目的 `Package.swift` 或 `.xcodeproj` 中添加依赖:

```swift
dependencies: [
    .package(
        url: "https://github.com/yourusername/libarchive.git",
        from: "1.0.0"
    )
]
```

或者在 Xcode 中:
1. 选择 `File` → `Add Package Dependencies`
2. 输入仓库 URL
3. 选择版本规则
4. 点击 `Add Package`

## 💻 使用示例

### 基本导入

```swift
import libarchive
```

### 创建 tar 归档

```swift
import Foundation

func createTarArchive(sourceFiles: [URL], destination: URL) throws {
    // 创建新的写归档
    let archive = archive_write_new()
    defer { archive_write_free(archive) }
    
    // 设置格式为 POSIX tar
    archive_write_set_format_pax_restricted(archive)
    
    // 如果需要,可以添加压缩过滤器
    // archive_write_add_filter_gzip(archive)
    
    // 打开目标文件
    archive_write_open_filename(archive, destination.path)
    
    // 遍历并添加每个文件
    for fileURL in sourceFiles {
        var entry = archive_entry_new()
        defer { archive_entry_free(entry) }
        
        // 设置文件信息
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let type = attributes[.type] as! FileAttributeType
        
        if type == .typeRegular {
            archive_entry_set_pathname(entry, fileURL.lastPathComponent)
            archive_entry_set_size(entry, attributes[.size] as! Int64)
            archive_entry_set_filetype(entry, AE_IFREG)
            archive_entry_set_perm(entry, 0644)
            
            // 写入头信息
            archive_write_header(archive, entry)
            
            // 写入文件内容
            let data = try Data(contentsOf: fileURL)
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                if let baseAddress = bytes.baseAddress {
                    archive_write_data(archive, baseAddress, data.count)
                }
            }
        }
    }
    
    archive_write_close(archive)
}
```

### 解压 tar 归档

```swift
import Foundation

func extractTarArchive(archiveURL: URL, destinationDirectory: URL) throws {
    // 创建新的读归档
    let archive = archive_read_new()
    defer { archive_read_free(archive) }
    
    // 支持所有格式和过滤器
    archive_read_support_format_all(archive)
    archive_read_support_filter_all(archive)
    
    // 打开源归档文件
    archive_read_open_filename(archive, archiveURL.path, 10240)
    
    // 创建写磁盘归档
    let disk = archive_write_disk_new()
    defer { archive_write_free(disk) }
    
    // 设置提取选项
    archive_write_disk_set_options(disk, ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM)
    
    // 遍历归档中的每个条目
    var entry: UnsafeMutablePointer<archive_entry>?
    while archive_read_next_header(archive, &entry) == ARCHIVE_OK {
        // 构建目标路径
        let path = destinationDirectory.appendingPathComponent(String(cString: archive_entry_pathname(entry!)))
        archive_entry_set_pathname(entry, path.path)
        
        // 写入文件
        archive_write_header(disk, entry)
        
        // 如果是普通文件,写入数据
        if archive_entry_filetype(entry!) == AE_IFREG {
            var buffer = [UInt8](repeating: 0, count: 8192)
            while true {
                let bytesRead = archive_read_data(archive, &buffer, buffer.count)
                if bytesRead <= 0 { break }
                archive_write_data_block(disk, buffer, bytesRead, 0)
            }
        }
        
        archive_write_finish_entry(disk)
    }
    
    archive_read_close(archive)
    archive_write_close(disk)
}
```

### 创建 zip 归档

```swift
import Foundation

func createZipArchive(sourceFiles: [URL], destination: URL) throws {
    let archive = archive_write_new()
    defer { archive_write_free(archive) }
    
    // 设置格式为 zip
    archive_write_set_format_zip(archive)
    
    // 添加 deflate 压缩
    archive_write_add_filter_deflate(archive)
    
    archive_write_open_filename(archive, destination.path)
    
    for fileURL in sourceFiles {
        var entry = archive_entry_new()
        defer { archive_entry_free(entry) }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let type = attributes[.type] as! FileAttributeType
        
        if type == .typeRegular {
            archive_entry_set_pathname(entry, fileURL.lastPathComponent)
            archive_entry_set_size(entry, attributes[.size] as! Int64)
            archive_entry_set_filetype(entry, AE_IFREG)
            archive_entry_set_perm(entry, 0644)
            
            archive_write_header(archive, entry)
            
            let data = try Data(contentsOf: fileURL)
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                if let baseAddress = bytes.baseAddress {
                    archive_write_data(archive, baseAddress, data.count)
                }
            }
        }
    }
    
    archive_write_close(archive)
}
```

### 解压 zip 归档

```swift
import Foundation

func extractZipArchive(archiveURL: URL, destinationDirectory: URL) throws {
    let archive = archive_read_new()
    defer { archive_read_free(archive) }
    
    // 支持所有格式
    archive_read_support_format_all(archive)
    archive_read_support_filter_all(archive)
    
    archive_read_open_filename(archive, archiveURL.path, 10240)
    
    let disk = archive_write_disk_new()
    defer { archive_write_free(disk) }
    
    archive_write_disk_set_options(disk, ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM | ARCHIVE_EXTRACT_ACL)
    
    var entry: UnsafeMutablePointer<archive_entry>?
    while archive_read_next_header(archive, &entry) == ARCHIVE_OK {
        let path = destinationDirectory.appendingPathComponent(String(cString: archive_entry_pathname(entry!)))
        archive_entry_set_pathname(entry, path.path)
        
        archive_write_header(disk, entry)
        
        if archive_entry_filetype(entry!) == AE_IFREG {
            var buffer = [UInt8](repeating: 0, count: 8192)
            while true {
                let bytesRead = archive_read_data(archive, &buffer, buffer.count)
                if bytesRead <= 0 { break }
                archive_write_data_block(disk, buffer, bytesRead, 0)
            }
        }
        
        archive_write_finish_entry(disk)
    }
    
    archive_read_close(archive)
    archive_write_close(disk)
}
```

### 列出归档内容

```swift
import Foundation

func listArchiveContents(archiveURL: URL) throws -> [String] {
    let archive = archive_read_new()
    defer { archive_read_free(archive) }
    
    archive_read_support_format_all(archive)
    archive_read_support_filter_all(archive)
    
    archive_read_open_filename(archive, archiveURL.path, 10240)
    
    var entries: [String] = []
    var entry: UnsafeMutablePointer<archive_entry>?
    
    while archive_read_next_header(archive, &entry) == ARCHIVE_OK {
        let path = String(cString: archive_entry_pathname(entry!))
        let size = archive_entry_size(entry!)
        let type = archive_entry_filetype(entry!)
        
        let typeString: String
        if type == AE_IFREG {
            typeString = "文件"
        } else if type == AE_IFDIR {
            typeString = "目录"
        } else {
            typeString = "其他"
        }
        
        entries.append("\(typeString): \(path) (\(size) 字节)")
    }
    
    archive_read_close(archive)
    
    return entries
}

// 使用示例
// do {
//     let entries = try listArchiveContents(archiveURL: URL(fileURLWithPath: "/path/to/archive.tar"))
//     for entry in entries {
//         print(entry)
//     }
// } catch {
//     print("错误: \(error)")
// }
```

### 创建 gzip 压缩的 tar 归档

```swift
import Foundation

func createTarGzArchive(sourceFiles: [URL], destination: URL) throws {
    let archive = archive_write_new()
    defer { archive_write_free(archive) }
    
    // 设置格式为 tar
    archive_write_set_format_pax_restricted(archive)
    
    // 添加 gzip 压缩
    archive_write_add_filter_gzip(archive)
    
    archive_write_open_filename(archive, destination.path)
    
    for fileURL in sourceFiles {
        var entry = archive_entry_new()
        defer { archive_entry_free(entry) }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let type = attributes[.type] as! FileAttributeType
        
        if type == .typeRegular {
            archive_entry_set_pathname(entry, fileURL.lastPathComponent)
            archive_entry_set_size(entry, attributes[.size] as! Int64)
            archive_entry_set_filetype(entry, AE_IFREG)
            archive_entry_set_perm(entry, 0644)
            
            archive_write_header(archive, entry)
            
            let data = try Data(contentsOf: fileURL)
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                if let baseAddress = bytes.baseAddress {
                    archive_write_data(archive, baseAddress, data.count)
                }
            }
        }
    }
    
    archive_write_close(archive)
}
```

### 使用 Swift 封装 (推荐)

虽然项目当前已包含 libarchive 的 xcframework 并支持直接使用 C API,但我建议创建一个更符合 Swift 习惯的封装层。这样可以:

- 使用 Swift 的类型系统保证类型安全
- 利用 Swift 的错误处理机制
- 提供更简洁、易用的 API

如果您需要一个完整的 Swift 封装层,我可以为您实现。

## 🔨 构建说明

### 构建 xcframework

如果需要自定义构建 xcframework,可以使用提供的构建脚本:

```bash
cd Sources
./build_libarchive_xcframework.sh
```

该脚本会:
1. 克隆 libarchive 源码
2. 为 iOS 设备构建 (arm64)
3. 为 iOS 模拟器构建 (arm64 和 x86_64)
4. 生成包含两者的 xcframework

### 构建参数

构建脚本支持以下配置:

- `IOS_MIN`: 最低 iOS 版本 (默认: 13.0)
- `SIM_ARCHS`: 模拟器架构 (默认: arm64;x86_64)
- `DEV_ARCHS`: 设备架构 (默认: arm64)

### 禁用的功能

为了减少依赖和构建复杂度,当前构建配置禁用了以下功能:

- 命令行工具 (tar、cpio、cat、unzip)
- 测试套件
- OpenSSL、Nettle、Libxml2、Expat 等外部库依赖

如需启用这些功能,请修改 [`build_libarchive_xcframework.sh`](Sources/build_libarchive_xcframework.sh:1) 中的 CMake 参数。

## 🧪 测试

运行测试:

```bash
swift test
```

## 📚 相关资源

- [libarchive 官方文档](https://github.com/libarchive/libarchive)
- [libarchive Wiki](https://github.com/libarchive/libarchive/wiki)
- [Swift Package Manager 文档](https://swift.org/package-manager/)

## 🛠️ 项目结构

```
libarchive/
├── Package.swift                    # SPM 配置文件
├── Sources/
│   ├── build_libarchive_xcframework.sh  # xcframework 构建脚本
│   ├── libarchive/
│   │   └── libarchive.swift        # Swift 封装 (开发中)
│   └── libarchive-build/
│       ├── libarchive.xcframework   # 编译好的 xcframework
│       ├── build/                  # 构建中间文件
│       └── output/                 # 构建输出
└── Tests/
    └── libarchiveTests/
        └── libarchiveTests.swift   # 测试文件
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request!

## 📄 许可证

本项目的 xcframework 包含 [libarchive](https://github.com/libarchive/libarchive),使用 BSD 2-Clause 许可证:

```
Copyright (c) 2003-2023 Tim Kientzle and others
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHORS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## 📞 支持

如有问题或建议,请提交 [GitHub Issue](https://github.com/yourusername/libarchive/issues)。

---

Made with ❤️ for Swift developers