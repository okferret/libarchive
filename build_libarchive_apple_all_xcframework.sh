#!/usr/bin/env bash
set -euo pipefail

# ===== 可调最低系统版本（按需改）=====
MIN_IOS="13.0"
MIN_TVOS="13.0"
MIN_WATCHOS="6.0"
MIN_MACOS="10.15"
MIN_CATALYST_IOS="13.0"

# ===== 架构配置（按需改）=====
SIM_ARCHS="arm64;x86_64"
MAC_ARCHS="arm64;x86_64"

ROOT="$(pwd)/libarchive-apple-build"
SRC_DIR="$ROOT/libarchive"
OUT_DIR="$ROOT/output"
BUILD_DIR="$ROOT/build"
XC_OUT="$ROOT/libarchive.xcframework"

rm -rf "$ROOT"
mkdir -p "$ROOT" "$OUT_DIR" "$BUILD_DIR"

echo "== Clone libarchive =="
git clone --depth 1 https://github.com/libarchive/libarchive.git "$SRC_DIR"

COMMON_CMAKE_ARGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON

  # 只构建库：禁用命令行工具与测试
  -DENABLE_TAR=OFF
  -DENABLE_CPIO=OFF
  -DENABLE_CAT=OFF
  -DENABLE_UNZIP=OFF
  -DENABLE_TEST=OFF

  # 启用常用压缩格式
  -DENABLE_ZLIB=ON
  -DENABLE_BZip2=ON
  -DENABLE_LZMA=ON
  -DENABLE_ZSTD=ON
  -DENABLE_LZ4=ON

  # 禁用不需要的加密库
  -DENABLE_CNG=OFF
  -DENABLE_OPENSSL=OFF
  -DENABLE_NETTLE=OFF
  
  # 禁用不需要的 XML/Iconv 依赖
  -DENABLE_LIBXML2=OFF
  -DENABLE_EXPAT=OFF
  -DENABLE_ICONV=OFF
)

build_one() {
  local NAME="$1"
  local SYSNAME="$2"
  local SDK="$3"
  local ARCHS="$4"
  local DEPLOY="$5"
  shift 5
  local EXTRA_ARGS=("$@")

  local BDIR="$BUILD_DIR/$NAME"
  local IDIR="$OUT_DIR/$NAME"
  rm -rf "$BDIR" "$IDIR"
  mkdir -p "$BDIR" "$IDIR"

  echo "== Configure $NAME (arch: $ARCHS) =="
  
  local CMAKE_CMD=(
    cmake -S "$SRC_DIR" -B "$BDIR"
    -G "Unix Makefiles"
    -DCMAKE_SYSTEM_NAME="$SYSNAME"
    -DCMAKE_OSX_SYSROOT="$SDK"
    -DCMAKE_OSX_ARCHITECTURES="$ARCHS"
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY"
    -DCMAKE_INSTALL_PREFIX="$IDIR"
    "${COMMON_CMAKE_ARGS[@]}"
  )
  
  if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    CMAKE_CMD+=("${EXTRA_ARGS[@]}")
  fi
  
  "${CMAKE_CMD[@]}"

  echo "== Build $NAME =="
  local CPU_COUNT=$(sysctl -n hw.ncpu)
  local HALF_CPU=$((CPU_COUNT / 2))
  [ $HALF_CPU -lt 1 ] && HALF_CPU=1
  cmake --build "$BDIR" --config Release -- -j"$HALF_CPU"

  echo "== Install $NAME =="
  cmake --install "$BDIR"
}

# 为 Catalyst 单独编译单个架构（使用环境变量避免冲突）
build_catalyst_arch() {
  local ARCH="$1"
  local NAME="catalyst-$ARCH"
  local IDIR="$OUT_DIR/$NAME"
  
  echo "== Build Catalyst for $ARCH =="
  
  local BDIR="$BUILD_DIR/$NAME"
  rm -rf "$BDIR" "$IDIR"
  mkdir -p "$BDIR" "$IDIR"
  
  # 不使用 CMAKE_OSX_DEPLOYMENT_TARGET，只通过 CFLAGS 传递 target
  # 清除可能冲突的环境变量
  unset MACOSX_DEPLOYMENT_TARGET
  unset SDKROOT
  
  # 构建 CMake 命令
  cmake -S "$SRC_DIR" -B "$BDIR" \
    -G "Unix Makefiles" \
    -DCMAKE_SYSTEM_NAME="Darwin" \
    -DCMAKE_OSX_SYSROOT="macosx" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_INSTALL_PREFIX="$IDIR" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="" \
    -DCMAKE_C_FLAGS="-target ${ARCH}-apple-ios${MIN_CATALYST_IOS}-macabi" \
    -DCMAKE_CXX_FLAGS="-target ${ARCH}-apple-ios${MIN_CATALYST_IOS}-macabi" \
    -DCMAKE_EXE_LINKER_FLAGS="-target ${ARCH}-apple-ios${MIN_CATALYST_IOS}-macabi" \
    -DCMAKE_SHARED_LINKER_FLAGS="-target ${ARCH}-apple-ios${MIN_CATALYST_IOS}-macabi" \
    -DCMAKE_MODULE_LINKER_FLAGS="-target ${ARCH}-apple-ios${MIN_CATALYST_IOS}-macabi" \
    "${COMMON_CMAKE_ARGS[@]}"
  
  local CPU_COUNT=$(sysctl -n hw.ncpu)
  local HALF_CPU=$((CPU_COUNT / 2))
  [ $HALF_CPU -lt 1 ] && HALF_CPU=1
  
  cmake --build "$BDIR" --config Release -- -j"$HALF_CPU"
  cmake --install "$BDIR"
}

echo "== iOS device =="
build_one "ios-device" "iOS" "iphoneos" "arm64" "$MIN_IOS"

echo "== iOS simulator =="
build_one "ios-sim" "iOS" "iphonesimulator" "$SIM_ARCHS" "$MIN_IOS"

echo "== tvOS device =="
build_one "tvos-device" "tvOS" "appletvos" "arm64" "$MIN_TVOS" \
  -DENABLE_PROGRAM_FILTERS=OFF \
  -DHAVE_FORK=OFF \
  -DHAVE_VFORK=OFF \
  -DHAVE_POSIX_SPAWN=OFF \
  -DHAVE_POSIX_SPAWNP=OFF

echo "== tvOS simulator =="
build_one "tvos-sim" "tvOS" "appletvsimulator" "$SIM_ARCHS" "$MIN_TVOS" \
  -DENABLE_PROGRAM_FILTERS=OFF \
  -DHAVE_FORK=OFF \
  -DHAVE_VFORK=OFF \
  -DHAVE_POSIX_SPAWN=OFF \
  -DHAVE_POSIX_SPAWNP=OFF

echo "== watchOS device =="
# watchOS 真机
build_one "watchos-device" "watchOS" "watchos" "arm64_32" "$MIN_WATCHOS" \
  -DENABLE_PROGRAM_FILTERS=OFF \
  -DHAVE_FORK=OFF \
  -DHAVE_VFORK=OFF \
  -DHAVE_POSIX_SPAWN=OFF \
  -DHAVE_POSIX_SPAWNP=OFF || {
  echo "Warning: arm64_32 build failed, trying arm64..."
  build_one "watchos-device" "watchOS" "watchos" "arm64" "$MIN_WATCHOS" \
    -DENABLE_PROGRAM_FILTERS=OFF \
    -DHAVE_FORK=OFF \
    -DHAVE_VFORK=OFF \
    -DHAVE_POSIX_SPAWN=OFF \
    -DHAVE_POSIX_SPAWNP=OFF
}

echo "== watchOS simulator =="
build_one "watchos-sim" "watchOS" "watchsimulator" "$SIM_ARCHS" "$MIN_WATCHOS" \
  -DENABLE_PROGRAM_FILTERS=OFF \
  -DHAVE_FORK=OFF \
  -DHAVE_VFORK=OFF \
  -DHAVE_POSIX_SPAWN=OFF \
  -DHAVE_POSIX_SPAWNP=OFF

echo "== macOS =="
build_one "macos" "Darwin" "macosx" "$MAC_ARCHS" "$MIN_MACOS"

echo "== Mac Catalyst =="
# 注意：Catalyst 编译在某些 CMake 版本中可能失败
# 如果失败，可以注释掉这部分，因为 macOS 库也可以在 Catalyst 应用中使用
echo "Warning: Catalyst compilation may fail due to CMake/Xcode compatibility issues"
echo "If it fails, you can still use the macOS framework in Catalyst apps"

# 分别编译两个架构
build_catalyst_arch "x86_64" || {
  echo "Catalyst x86_64 build failed, skipping Catalyst support"
  rm -rf "$OUT_DIR/catalyst-x86_64" "$OUT_DIR/catalyst-arm64" "$OUT_DIR/catalyst"
  # 创建一个标记文件表示 Catalyst 不可用
  touch "$OUT_DIR/.catalyst_unavailable"
}

if [ ! -f "$OUT_DIR/.catalyst_unavailable" ]; then
  build_catalyst_arch "arm64" || {
    echo "Catalyst arm64 build failed, skipping Catalyst support"
    rm -rf "$OUT_DIR/catalyst-x86_64" "$OUT_DIR/catalyst-arm64" "$OUT_DIR/catalyst"
    touch "$OUT_DIR/.catalyst_unavailable"
  }
fi

# 合并 Catalyst 的 fat 库（如果可用）
if [ ! -f "$OUT_DIR/.catalyst_unavailable" ] && \
   [ -f "$OUT_DIR/catalyst-x86_64/lib/libarchive.a" ] && \
   [ -f "$OUT_DIR/catalyst-arm64/lib/libarchive.a" ]; then
  echo "== Merging Catalyst architectures =="
  mkdir -p "$OUT_DIR/catalyst/lib"
  lipo -create \
    "$OUT_DIR/catalyst-x86_64/lib/libarchive.a" \
    "$OUT_DIR/catalyst-arm64/lib/libarchive.a" \
    -output "$OUT_DIR/catalyst/lib/libarchive.a"
  
  cp -r "$OUT_DIR/catalyst-arm64/include" "$OUT_DIR/catalyst/"
  
  echo "Catalyst fat library created"
else
  echo "Catalyst support disabled or build failed"
fi

# 验证所有生成的库
echo "== Verifying all libraries =="
find "$OUT_DIR" -name "libarchive.a" -type f | while read -r lib; do
  echo "  $(basename $(dirname $(dirname $lib)))/$(basename $lib):"
  lipo -info "$lib" 2>/dev/null | sed 's/^/    /' || echo "    Not a fat library or invalid"
done

# 创建 XCFramework
echo "== Creating XCFramework =="
rm -rf "$XC_OUT"

XC_ARGS=()

# 使用 ios-device 的头文件作为标准（所有平台头文件相同）
HDRS="$OUT_DIR/ios-device/include"

[ -f "$OUT_DIR/ios-device/lib/libarchive.a" ] && XC_ARGS+=(-library "$OUT_DIR/ios-device/lib/libarchive.a" -headers "$HDRS")
[ -f "$OUT_DIR/ios-sim/lib/libarchive.a" ] && XC_ARGS+=(-library "$OUT_DIR/ios-sim/lib/libarchive.a" -headers "$HDRS")
[ -f "$OUT_DIR/tvos-device/lib/libarchive.a" ] && XC_ARGS+=(-library "$OUT_DIR/tvos-device/lib/libarchive.a" -headers "$HDRS")
[ -f "$OUT_DIR/tvos-sim/lib/libarchive.a" ] && XC_ARGS+=(-library "$OUT_DIR/tvos-sim/lib/libarchive.a" -headers "$HDRS")
[ -f "$OUT_DIR/watchos-device/lib/libarchive.a" ] && XC_ARGS+=(-library "$OUT_DIR/watchos-device/lib/libarchive.a" -headers "$HDRS")
[ -f "$OUT_DIR/watchos-sim/lib/libarchive.a" ] && XC_ARGS+=(-library "$OUT_DIR/watchos-sim/lib/libarchive.a" -headers "$HDRS")
[ -f "$OUT_DIR/macos/lib/libarchive.a" ] && XC_ARGS+=(-library "$OUT_DIR/macos/lib/libarchive.a" -headers "$HDRS")
[ -f "$OUT_DIR/catalyst/lib/libarchive.a" ] && XC_ARGS+=(-library "$OUT_DIR/catalyst/lib/libarchive.a" -headers "$HDRS")

if [ ${#XC_ARGS[@]} -gt 0 ]; then
  xcodebuild -create-xcframework \
    "${XC_ARGS[@]}" \
    -output "$XC_OUT"
  
  echo "✅ XCFramework created: $XC_OUT"
  
  echo "== XCFramework Info =="
  echo "Framework slices:"
  plutil -p "$XC_OUT/Info.plist" | grep -A 5 "AvailableLibraries"
  
  echo -e "\nIndividual library architectures:"
  find "$XC_OUT" -name "libarchive.a" -exec lipo -info {} \;
else
  echo "Error: No libraries found to create XCFramework"
  exit 1
fi

# ===== 清理中间文件，只保留最终的 XCFramework =====
echo ""
echo "== Cleaning up intermediate files =="

# 删除源码目录
rm -rf "$SRC_DIR"
echo "  ✓ Removed source directory"

# 删除编译目录
rm -rf "$BUILD_DIR"
echo "  ✓ Removed build directory"

# 删除输出目录（包含所有 .a 文件和头文件）
rm -rf "$OUT_DIR"
echo "  ✓ Removed output directory"

# 删除根目录下的空文件夹（如果存在）
rmdir "$ROOT" 2>/dev/null || true

echo ""
echo "✅ Cleanup complete! Only XCFramework remains:"
echo "   $XC_OUT"
echo ""
echo "📦 Final output size:"
du -sh "$XC_OUT" 2>/dev/null || echo "  (unable to determine size)"

# 可选：将 XCFramework 移动到当前目录
# mv "$XC_OUT" ./libarchive.xcframework
# echo "   Moved to: $(pwd)/libarchive.xcframework"