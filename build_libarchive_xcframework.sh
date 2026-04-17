#!/usr/bin/env bash
set -euo pipefail

# ====== 配置 ======
IOS_MIN=13.0
ROOT="$(pwd)/libarchive-build"
SRC_DIR="$ROOT/libarchive"
OUT_DIR="$ROOT/output"
BUILD_DIR="$ROOT/build"

# 需要同时支持 Intel 模拟器就保留 x86_64；若只支持 Apple Silicon 模拟器可改为仅 arm64
SIM_ARCHS="arm64;x86_64"
DEV_ARCHS="arm64"

# ====== 准备目录 ======
rm -rf "$ROOT"
mkdir -p "$ROOT" "$OUT_DIR" "$BUILD_DIR"

# ====== 拉源码 ======
git clone --depth 1 https://github.com/libarchive/libarchive.git "$SRC_DIR"

# ====== 通用 CMake 参数（尽量减少外部依赖，保证可编译） ======
COMMON_CMAKE_ARGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON

  # 关键：不构建命令行工具与测试（避免 bsdcat/bsdtar/... 的 install 报错）
  -DENABLE_TAR=OFF
  -DENABLE_CPIO=OFF
  -DENABLE_CAT=OFF
  -DENABLE_UNZIP=OFF
  -DENABLE_TEST=OFF

  # 可选：进一步减少依赖
  -DENABLE_CNG=OFF
  -DENABLE_OPENSSL=OFF
  -DENABLE_NETTLE=OFF
  -DENABLE_LIBXML2=OFF
  -DENABLE_EXPAT=OFF
  -DENABLE_ICONV=OFF
)

build_one() {
  local PLATFORM="$1"      # iphoneos / iphonesimulator
  local ARCHS="$2"         # "arm64" or "arm64;x86_64"
  local BUILD_SUB="$BUILD_DIR/$PLATFORM"
  local INSTALL_SUB="$OUT_DIR/$PLATFORM"

  rm -rf "$BUILD_SUB" "$INSTALL_SUB"
  mkdir -p "$BUILD_SUB" "$INSTALL_SUB"

  cmake -S "$SRC_DIR" -B "$BUILD_SUB" \
    -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$PLATFORM" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCHS" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_SUB" \
    "${COMMON_CMAKE_ARGS[@]}"

  cmake --build "$BUILD_SUB" --config Release -- -j"$(sysctl -n hw.ncpu)"
  cmake --install "$BUILD_SUB"
}

echo "== Build device =="
build_one "iphoneos" "$DEV_ARCHS"

echo "== Build simulator =="
build_one "iphonesimulator" "$SIM_ARCHS"

# ====== 生成 xcframework（静态库+头文件） ======
LIB_DEV="$OUT_DIR/iphoneos/lib/libarchive.a"
LIB_SIM="$OUT_DIR/iphonesimulator/lib/libarchive.a"
HDRS="$OUT_DIR/iphoneos/include"

rm -rf "$ROOT/libarchive.xcframework"
xcodebuild -create-xcframework \
  -library "$LIB_DEV" -headers "$HDRS" \
  -library "$LIB_SIM" -headers "$HDRS" \
  -output "$ROOT/libarchive.xcframework"

# ====== 清理中间文件，只保留 xcframework ======
echo "== Cleaning intermediate files =="
rm -rf "$SRC_DIR"      # 删除源码目录
rm -rf "$BUILD_DIR"    # 删除构建目录
rm -rf "$OUT_DIR"      # 删除输出目录（包含 .a 文件和头文件）

echo "✅ Done: $ROOT/libarchive.xcframework"