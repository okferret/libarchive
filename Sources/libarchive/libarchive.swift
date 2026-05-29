// libarchive
// 此文件作为包装层，将 libarchive XCFramework 暴露给外部 SPM 依赖方使用。
// 外部项目只需 import libarchive 即可访问 libarchive 的 C API。

@_exported import libarchive
