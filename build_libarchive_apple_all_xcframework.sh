#!/usr/bin/env bash
set -euo pipefail

# ===== 可调最低系统版本（按需改）=====
MIN_IOS="13.0"
MIN_TVOS="13.0"
MIN_WATCHOS="6.0"
MIN_MACOS="10.15"
MIN_CATALYST_IOS="14.0"

# ===== 架构配置（按需改）=====
SIM_ARCHS="arm64;x86_64"
MAC_ARCHS="arm64;x86_64"

ROOT="$(pwd)/libarchive-apple-build"
SRC_DIR="$ROOT/libarchive"
XZ_SRC_DIR="$ROOT/xz"
ZSTD_SRC_DIR="$ROOT/zstd"
LZ4_SRC_DIR="$ROOT/lz4"
OUT_DIR="$ROOT/output"
BUILD_DIR="$ROOT/build"
XZ_BUILD_DIR="$ROOT/xz-build"
ZSTD_BUILD_DIR="$ROOT/zstd-build"
LZ4_BUILD_DIR="$ROOT/lz4-build"
XC_OUT="$ROOT/libarchive.xcframework"

# ===== CPU 核心数（并发时每个任务独占全部核心，由 OS 调度）=====
CPU_COUNT=$(sysctl -n hw.ncpu)

rm -rf "$ROOT"
mkdir -p "$ROOT" "$OUT_DIR" "$BUILD_DIR" "$XZ_BUILD_DIR" "$ZSTD_BUILD_DIR" "$LZ4_BUILD_DIR"

# ===== 获取最新版本并克隆源码 =====
echo "== Fetching latest release tags =="

LATEST_TAG=$(curl -fsSL https://api.github.com/repos/libarchive/libarchive/releases/latest \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
echo "Latest libarchive version: $LATEST_TAG"

XZ_TAG=$(curl -fsSL https://api.github.com/repos/tukaani-project/xz/releases/latest \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
echo "Latest xz version: $XZ_TAG"

ZSTD_TAG=$(curl -fsSL https://api.github.com/repos/facebook/zstd/releases/latest \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
echo "Latest zstd version: $ZSTD_TAG"

LZ4_TAG=$(curl -fsSL https://api.github.com/repos/lz4/lz4/releases/latest \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])")
echo "Latest lz4 version: $LZ4_TAG"

echo "== Cloning sources =="
git clone --depth 1 --branch "$LATEST_TAG" https://github.com/libarchive/libarchive.git "$SRC_DIR" &
CLONE_PIDS=($!)
git clone --depth 1 --branch "$XZ_TAG"     https://github.com/tukaani-project/xz.git    "$XZ_SRC_DIR" &
CLONE_PIDS+=($!)
git clone --depth 1 --branch "$ZSTD_TAG"   https://github.com/facebook/zstd.git          "$ZSTD_SRC_DIR" &
CLONE_PIDS+=($!)
git clone --depth 1 --branch "$LZ4_TAG"    https://github.com/lz4/lz4.git               "$LZ4_SRC_DIR" &
CLONE_PIDS+=($!)

for PID in "${CLONE_PIDS[@]}"; do wait "$PID" || { echo "❌ Clone failed"; exit 1; }; done
echo "== All sources cloned =="

# ===== 检测 Homebrew 安装的库路径（仅用于 macOS 回退）=====
HOMEBREW_PREFIX=""
if command -v brew &>/dev/null; then
  HOMEBREW_PREFIX="$(brew --prefix 2>/dev/null)" || HOMEBREW_PREFIX=""
fi
echo "Homebrew prefix: ${HOMEBREW_PREFIX:-（未找到）}"

# ===== 通用交叉编译函数 =====
# 参数：BUILD_DIR_BASE SRC_DIR NAME SDK ARCHS DEPLOY CMAKE_EXTRA_ARGS...
build_static_lib() {
  local BBASE="$1"; local LSRC="$2"; local NAME="$3"
  local SDK="$4";   local ARCHS="$5"; local DEPLOY="$6"
  shift 6
  local EXTRA_ARGS=("$@")

  local BDIR="$BBASE/$NAME"
  local IDIR="$OUT_DIR/$NAME"
  rm -rf "$BDIR" "$IDIR"
  mkdir -p "$BDIR" "$IDIR"

  local SDKROOT
  SDKROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"

  cmake -S "$LSRC" -B "$BDIR" \
    -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_OSX_SYSROOT="$SDK" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCHS" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY" \
    -DCMAKE_INSTALL_PREFIX="$IDIR" \
    "${EXTRA_ARGS[@]}"

  cmake --build "$BDIR" --config Release -- -j"$CPU_COUNT"
  cmake --install "$BDIR"
}

# ===== 交叉编译 liblzma（xz-utils）=====
build_liblzma() {
  local NAME="$1"; local SDK="$2"; local ARCHS="$3"; local DEPLOY="$4"
  echo "== Build liblzma: $NAME (archs: $ARCHS) =="
  build_static_lib "$XZ_BUILD_DIR" "$XZ_SRC_DIR" "lzma-$NAME" "$SDK" "$ARCHS" "$DEPLOY" \
    -DBUILD_TESTING=OFF \
    -DXZ_TOOL_XZ=OFF \
    -DXZ_TOOL_XZDEC=OFF \
    -DXZ_TOOL_LZMADEC=OFF \
    -DXZ_TOOL_LZMAINFO=OFF \
    -DXZ_TOOL_LZMA=OFF \
    -DXZ_TOOL_SCRIPTS=OFF \
    -DXZ_TOOL_SYMLINKS=OFF \
    -DCREATE_XZ_SYMLINKS=OFF \
    -DCREATE_LZMA_SYMLINKS=OFF \
    -DENABLE_NLS=OFF
  echo "== Done: liblzma $NAME =="
}

# ===== 交叉编译 libzstd =====
build_libzstd() {
  local NAME="$1"; local SDK="$2"; local ARCHS="$3"; local DEPLOY="$4"
  echo "== Build libzstd: $NAME (archs: $ARCHS) =="
  build_static_lib "$ZSTD_BUILD_DIR" "$ZSTD_SRC_DIR/build/cmake" "zstd-$NAME" "$SDK" "$ARCHS" "$DEPLOY" \
    -DZSTD_BUILD_SHARED=OFF \
    -DZSTD_BUILD_STATIC=ON \
    -DZSTD_BUILD_PROGRAMS=OFF \
    -DZSTD_BUILD_TESTS=OFF \
    -DZSTD_BUILD_CONTRIB=OFF \
    -DZSTD_MULTITHREAD_SUPPORT=OFF
  echo "== Done: libzstd $NAME =="
}

# ===== 交叉编译 liblz4 =====
build_liblz4() {
  local NAME="$1"; local SDK="$2"; local ARCHS="$3"; local DEPLOY="$4"
  echo "== Build liblz4: $NAME (archs: $ARCHS) =="
  build_static_lib "$LZ4_BUILD_DIR" "$LZ4_SRC_DIR/build/cmake" "lz4-$NAME" "$SDK" "$ARCHS" "$DEPLOY" \
    -DLZ4_BUILD_CLI=OFF \
    -DLZ4_BUILD_LEGACY_LZ4C=OFF
  echo "== Done: liblz4 $NAME =="
}

# ===== 并发编译所有平台的第三方库 =====
echo "== Building third-party libs for all Apple platforms =="

THIRD_PARTY_PIDS=()

for FUNC in build_liblzma build_libzstd build_liblz4; do
  $FUNC "ios-device"     "iphoneos"         "arm64"       "$MIN_IOS"     &
  THIRD_PARTY_PIDS+=($!)
  $FUNC "ios-sim"        "iphonesimulator"  "$SIM_ARCHS"  "$MIN_IOS"     &
  THIRD_PARTY_PIDS+=($!)
  $FUNC "tvos-device"    "appletvos"        "arm64"       "$MIN_TVOS"    &
  THIRD_PARTY_PIDS+=($!)
  $FUNC "tvos-sim"       "appletvsimulator" "$SIM_ARCHS"  "$MIN_TVOS"    &
  THIRD_PARTY_PIDS+=($!)
  $FUNC "watchos-device" "watchos"          "arm64_32"    "$MIN_WATCHOS" &
  THIRD_PARTY_PIDS+=($!)
  $FUNC "watchos-sim"    "watchsimulator"   "$SIM_ARCHS"  "$MIN_WATCHOS" &
  THIRD_PARTY_PIDS+=($!)
  $FUNC "macos"          "macosx"           "$MAC_ARCHS"  "$MIN_MACOS"   &
  THIRD_PARTY_PIDS+=($!)
done

echo "== Waiting for third-party lib builds =="
TP_FAILED=0
for PID in "${THIRD_PARTY_PIDS[@]}"; do
  if ! wait "$PID"; then
    echo "❌ Third-party build task (PID=$PID) failed"
    TP_FAILED=1
  fi
done
[ "$TP_FAILED" -eq 1 ] && { echo "❌ Third-party builds failed. Aborting."; exit 1; }
echo "== All third-party libs built =="

# ===== 不依赖外部库的静态 CMake 参数（平台无关）=====
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

  # ===== 启用所有支持的压缩/解压格式 =====
  # zlib / bzip2：所有 Apple SDK 均内置，始终启用
  -DENABLE_ZLIB=ON       # deflate/gzip/zip 基础压缩
  -DENABLE_BZip2=ON      # .bz2 格式

  # ===== 归档格式支持（libarchive 内置，无需外部库）=====
  # tar, pax, cpio, shar, iso9660, zip, 7zip, ar, mtree, xar, lha/lzh, rar, cab 等
  # 这些格式由 libarchive 内置实现，默认全部启用，无需额外 CMake 选项

  # ===== 加密/哈希支持 =====
  # OpenSSL — 用于加密 zip/7z 等格式的读写（Apple 平台系统自带）
  -DENABLE_OPENSSL=ON
  # 禁用其他加密后端（避免与 OpenSSL 冲突）
  -DENABLE_CNG=OFF
  -DENABLE_NETTLE=OFF

  # ===== XML 解析支持（用于 xar 格式）=====
  # libxml2 — Apple 平台系统自带，用于解析 xar 归档的 XML 目录
  -DENABLE_LIBXML2=ON
  # expat — 备用 XML 解析器（已有 libxml2，禁用 expat 避免重复）
  -DENABLE_EXPAT=OFF

  # ===== 字符编码转换 =====
  # iconv — 用于文件名编码转换（Apple 平台 libc 内置）
  -DENABLE_ICONV=ON
)

# ===== 动态生成 SDK 相关 CMake 参数 =====
# 参数：SDK IS_MACOS PLATFORM_NAME
# PLATFORM_NAME 与 build_liblzma/build_libzstd/build_liblz4 的 NAME 一致
make_sdk_cmake_args() {
  local SDK="$1"
  local IS_MACOS="${2:-false}"
  local PLATFORM_NAME="${3:-}"   # 用于查找交叉编译的第三方库

  local SDKROOT
  SDKROOT="$(xcrun --sdk "$SDK" --show-sdk-path 2>/dev/null)" || {
    echo "Warning: xcrun failed for SDK '$SDK', skipping SDK-specific library paths" >&2
    return
  }
  local INC="$SDKROOT/usr/include"
  local LIB="$SDKROOT/usr/lib"

  # zlib — 所有 Apple SDK 均有 zlib.h
  echo "-DZLIB_INCLUDE_DIR=${INC}"
  echo "-DZLIB_LIBRARY=${LIB}/libz.tbd"

  # bzip2 — 所有 Apple SDK 均有 bzlib.h
  echo "-DBZIP2_INCLUDE_DIR=${INC}"
  echo "-DBZIP2_LIBRARIES=${LIB}/libbz2.tbd"

  # libxml2 — 所有 Apple SDK 均有（头文件在 usr/include/libxml2）
  echo "-DLIBXML2_INCLUDE_DIR=${INC}/libxml2"
  echo "-DLIBXML2_LIBRARY=${LIB}/libxml2.tbd"

  # OpenSSL — Apple SDK 通过 CommonCrypto 提供，libarchive 会自动检测
  # 不需要手动指定路径，CMake 会通过系统检测自动找到

  # ===== lzma/xz =====
  local LZMA_INC="$OUT_DIR/lzma-${PLATFORM_NAME}/include"
  local LZMA_LIB="$OUT_DIR/lzma-${PLATFORM_NAME}/lib/liblzma.a"
  if [ -n "$PLATFORM_NAME" ] && [ -f "$LZMA_LIB" ] && [ -d "$LZMA_INC" ]; then
    echo "-DENABLE_LZMA=ON"
    echo "-DLIBLZMA_INCLUDE_DIR=${LZMA_INC}"
    echo "-DLIBLZMA_LIBRARY=${LZMA_LIB}"
    echo "  [lzma] 使用交叉编译静态库 (${PLATFORM_NAME})，已启用" >&2
  elif [ -f "${INC}/lzma.h" ]; then
    echo "-DENABLE_LZMA=ON"
    echo "-DLIBLZMA_INCLUDE_DIR=${INC}"
    echo "-DLIBLZMA_LIBRARY=${LIB}/liblzma.tbd"
    echo "  [lzma] SDK 自带头文件，已启用" >&2
  elif [ "$IS_MACOS" = "true" ] && [ -n "$HOMEBREW_PREFIX" ]; then
    local HB_XZ_INC="" HB_XZ_LIB=""
    [ -f "${HOMEBREW_PREFIX}/include/lzma.h" ] && { HB_XZ_INC="${HOMEBREW_PREFIX}/include"; HB_XZ_LIB="${HOMEBREW_PREFIX}/lib/liblzma.a"; }
    [ -z "$HB_XZ_INC" ] && [ -f "${HOMEBREW_PREFIX}/opt/xz/include/lzma.h" ] && { HB_XZ_INC="${HOMEBREW_PREFIX}/opt/xz/include"; HB_XZ_LIB="${HOMEBREW_PREFIX}/opt/xz/lib/liblzma.a"; }
    if [ -n "$HB_XZ_INC" ] && [ -f "$HB_XZ_LIB" ]; then
      echo "-DENABLE_LZMA=ON"
      echo "-DLIBLZMA_INCLUDE_DIR=${HB_XZ_INC}"
      echo "-DLIBLZMA_LIBRARY=${HB_XZ_LIB}"
      echo "  [lzma] 使用 Homebrew 静态库，已启用" >&2
    else
      echo "-DENABLE_LZMA=OFF"
      echo "  [lzma] 无可用库，已禁用" >&2
    fi
  else
    echo "-DENABLE_LZMA=OFF"
    echo "  [lzma] 无可用头文件/库，已禁用" >&2
  fi

  # ===== zstd =====
  local ZSTD_INC="$OUT_DIR/zstd-${PLATFORM_NAME}/include"
  local ZSTD_LIB="$OUT_DIR/zstd-${PLATFORM_NAME}/lib/libzstd.a"
  if [ -n "$PLATFORM_NAME" ] && [ -f "$ZSTD_LIB" ] && [ -d "$ZSTD_INC" ]; then
    echo "-DENABLE_ZSTD=ON"
    echo "-DZSTD_INCLUDE_DIR=${ZSTD_INC}"
    echo "-DZSTD_LIBRARY=${ZSTD_LIB}"
    echo "  [zstd] 使用交叉编译静态库 (${PLATFORM_NAME})，已启用" >&2
  elif [ -f "${INC}/zstd.h" ]; then
    echo "-DENABLE_ZSTD=ON"
    echo "-DZSTD_INCLUDE_DIR=${INC}"
    echo "-DZSTD_LIBRARY=${LIB}/libzstd.tbd"
    echo "  [zstd] SDK 自带头文件，已启用" >&2
  elif [ "$IS_MACOS" = "true" ] && [ -n "$HOMEBREW_PREFIX" ]; then
    local HB_ZSTD_INC="" HB_ZSTD_LIB=""
    [ -f "${HOMEBREW_PREFIX}/include/zstd.h" ] && { HB_ZSTD_INC="${HOMEBREW_PREFIX}/include"; HB_ZSTD_LIB="${HOMEBREW_PREFIX}/lib/libzstd.a"; }
    [ -z "$HB_ZSTD_INC" ] && [ -f "${HOMEBREW_PREFIX}/opt/zstd/include/zstd.h" ] && { HB_ZSTD_INC="${HOMEBREW_PREFIX}/opt/zstd/include"; HB_ZSTD_LIB="${HOMEBREW_PREFIX}/opt/zstd/lib/libzstd.a"; }
    if [ -n "$HB_ZSTD_INC" ] && [ -f "$HB_ZSTD_LIB" ]; then
      echo "-DENABLE_ZSTD=ON"
      echo "-DZSTD_INCLUDE_DIR=${HB_ZSTD_INC}"
      echo "-DZSTD_LIBRARY=${HB_ZSTD_LIB}"
      echo "  [zstd] 使用 Homebrew 静态库，已启用" >&2
    else
      echo "-DENABLE_ZSTD=OFF"
      echo "  [zstd] 无可用库，已禁用" >&2
    fi
  else
    echo "-DENABLE_ZSTD=OFF"
    echo "  [zstd] 无可用头文件/库，已禁用" >&2
  fi

  # ===== lz4 =====
  local LZ4_INC="$OUT_DIR/lz4-${PLATFORM_NAME}/include"
  local LZ4_LIB="$OUT_DIR/lz4-${PLATFORM_NAME}/lib/liblz4.a"
  if [ -n "$PLATFORM_NAME" ] && [ -f "$LZ4_LIB" ] && [ -d "$LZ4_INC" ]; then
    echo "-DENABLE_LZ4=ON"
    echo "-DLZ4_INCLUDE_DIR=${LZ4_INC}"
    echo "-DLZ4_LIBRARY=${LZ4_LIB}"
    echo "  [lz4] 使用交叉编译静态库 (${PLATFORM_NAME})，已启用" >&2
  elif [ -f "${INC}/lz4.h" ]; then
    echo "-DENABLE_LZ4=ON"
    echo "-DLZ4_INCLUDE_DIR=${INC}"
    echo "-DLZ4_LIBRARY=${LIB}/liblz4.tbd"
    echo "  [lz4] SDK 自带头文件，已启用" >&2
  elif [ "$IS_MACOS" = "true" ] && [ -n "$HOMEBREW_PREFIX" ]; then
    local HB_LZ4_INC="" HB_LZ4_LIB=""
    [ -f "${HOMEBREW_PREFIX}/include/lz4.h" ] && { HB_LZ4_INC="${HOMEBREW_PREFIX}/include"; HB_LZ4_LIB="${HOMEBREW_PREFIX}/lib/liblz4.a"; }
    [ -z "$HB_LZ4_INC" ] && [ -f "${HOMEBREW_PREFIX}/opt/lz4/include/lz4.h" ] && { HB_LZ4_INC="${HOMEBREW_PREFIX}/opt/lz4/include"; HB_LZ4_LIB="${HOMEBREW_PREFIX}/opt/lz4/lib/liblz4.a"; }
    if [ -n "$HB_LZ4_INC" ] && [ -f "$HB_LZ4_LIB" ]; then
      echo "-DENABLE_LZ4=ON"
      echo "-DLZ4_INCLUDE_DIR=${HB_LZ4_INC}"
      echo "-DLZ4_LIBRARY=${HB_LZ4_LIB}"
      echo "  [lz4] 使用 Homebrew 静态库，已启用" >&2
    else
      echo "-DENABLE_LZ4=OFF"
      echo "  [lz4] 无可用库，已禁用" >&2
    fi
  else
    echo "-DENABLE_LZ4=OFF"
    echo "  [lz4] 无可用头文件/库，已禁用" >&2
  fi
}

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

  # 判断是否为 macOS 构建（可使用 Homebrew 库补充）
  local IS_MACOS_BUILD="false"
  [ "$SDK" = "macosx" ] && IS_MACOS_BUILD="true"

  # 动态获取目标 SDK 的库路径参数（含格式可用性检测）
  # 传入平台名称（与 build_liblzma/build_libzstd/build_liblz4 的 NAME 一致）
  local SDK_CMAKE_ARGS=()
  while IFS= read -r line; do
    [ -n "$line" ] && SDK_CMAKE_ARGS+=("$line")
  done < <(make_sdk_cmake_args "$SDK" "$IS_MACOS_BUILD" "$NAME")

  local CMAKE_CMD=(
    cmake -S "$SRC_DIR" -B "$BDIR"
    -G "Unix Makefiles"
    -DCMAKE_SYSTEM_NAME="$SYSNAME"
    -DCMAKE_OSX_SYSROOT="$SDK"
    -DCMAKE_OSX_ARCHITECTURES="$ARCHS"
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOY"
    -DCMAKE_INSTALL_PREFIX="$IDIR"
    "${COMMON_CMAKE_ARGS[@]}"
    "${SDK_CMAKE_ARGS[@]}"
  )

  if [ ${#EXTRA_ARGS[@]} -gt 0 ]; then
    CMAKE_CMD+=("${EXTRA_ARGS[@]}")
  fi

  "${CMAKE_CMD[@]}"

  echo "== Build $NAME =="
  cmake --build "$BDIR" --config Release -- -j"$CPU_COUNT"

  echo "== Install $NAME =="
  cmake --install "$BDIR"

  # ===== 将第三方静态库合并进 libarchive.a（解决 Undefined Symbol 问题）=====
  # libarchive 编译时以外部依赖方式链接第三方库，符号不会自动合并进 .a
  # 必须手动用 libtool -static 将所有 .a 合并成一个胖静态库
  local MERGED_LIBS=("$IDIR/lib/libarchive.a")

  local LZMA_A="$OUT_DIR/lzma-${NAME}/lib/liblzma.a"
  local ZSTD_A="$OUT_DIR/zstd-${NAME}/lib/libzstd.a"
  local LZ4_A="$OUT_DIR/lz4-${NAME}/lib/liblz4.a"

  [ -f "$LZMA_A" ] && MERGED_LIBS+=("$LZMA_A") && echo "  [merge] liblzma.a -> libarchive.a"
  [ -f "$ZSTD_A" ] && MERGED_LIBS+=("$ZSTD_A") && echo "  [merge] libzstd.a -> libarchive.a"
  [ -f "$LZ4_A"  ] && MERGED_LIBS+=("$LZ4_A")  && echo "  [merge] liblz4.a  -> libarchive.a"

  if [ ${#MERGED_LIBS[@]} -gt 1 ]; then
    local MERGED_TMP="$IDIR/lib/libarchive_merged.a"
    libtool -static -o "$MERGED_TMP" "${MERGED_LIBS[@]}"
    mv "$MERGED_TMP" "$IDIR/lib/libarchive.a"
    echo "  [merge] Done: libarchive.a now contains all third-party symbols"
  fi

  echo "== Done: $NAME =="
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

  # Catalyst 不使用交叉编译的第三方库（macabi ABI 与普通 macos 静态库不兼容）
  local SDK_CMAKE_ARGS=()
  while IFS= read -r line; do
    [ -n "$line" ] && SDK_CMAKE_ARGS+=("$line")
  done < <(make_sdk_cmake_args "macosx" "false" "")

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
    "${COMMON_CMAKE_ARGS[@]}" \
    "${SDK_CMAKE_ARGS[@]}"

  cmake --build "$BDIR" --config Release -- -j"$CPU_COUNT"
  cmake --install "$BDIR"

  # Catalyst 不合并第三方库（macabi ABI 与普通 macos 静态库不兼容）
  # 如需支持，需单独为 macabi target 交叉编译第三方库
  echo "== Done: $NAME =="
}

# ===== 并发编译所有平台 =====
echo "== Starting parallel builds (CPU cores: $CPU_COUNT) =="

# iOS device
build_one "ios-device" "iOS" "iphoneos" "arm64" "$MIN_IOS" &
PIDS=($!)

# iOS simulator
build_one "ios-sim" "iOS" "iphonesimulator" "$SIM_ARCHS" "$MIN_IOS" &
PIDS+=($!)

# tvOS device
build_one "tvos-device" "tvOS" "appletvos" "arm64" "$MIN_TVOS" \
  -DENABLE_PROGRAM_FILTERS=OFF \
  -DHAVE_FORK=OFF \
  -DHAVE_VFORK=OFF \
  -DHAVE_POSIX_SPAWN=OFF \
  -DHAVE_POSIX_SPAWNP=OFF &
PIDS+=($!)

# tvOS simulator
build_one "tvos-sim" "tvOS" "appletvsimulator" "$SIM_ARCHS" "$MIN_TVOS" \
  -DENABLE_PROGRAM_FILTERS=OFF \
  -DHAVE_FORK=OFF \
  -DHAVE_VFORK=OFF \
  -DHAVE_POSIX_SPAWN=OFF \
  -DHAVE_POSIX_SPAWNP=OFF &
PIDS+=($!)

# watchOS simulator
build_one "watchos-sim" "watchOS" "watchsimulator" "$SIM_ARCHS" "$MIN_WATCHOS" \
  -DENABLE_PROGRAM_FILTERS=OFF \
  -DHAVE_FORK=OFF \
  -DHAVE_VFORK=OFF \
  -DHAVE_POSIX_SPAWN=OFF \
  -DHAVE_POSIX_SPAWNP=OFF &
PIDS+=($!)

# macOS
build_one "macos" "Darwin" "macosx" "$MAC_ARCHS" "$MIN_MACOS" &
PIDS+=($!)

# watchOS 真机（arm64_32 优先，失败则回退 arm64，串行处理避免回退逻辑竞争）
(
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
) &
PIDS+=($!)

# 等待所有并发任务完成
echo "== Waiting for all parallel builds to complete =="
FAILED=0
for PID in "${PIDS[@]}"; do
  if ! wait "$PID"; then
    echo "❌ A parallel build task (PID=$PID) failed"
    FAILED=1
  fi
done
[ "$FAILED" -eq 1 ] && { echo "❌ One or more builds failed. Aborting."; exit 1; }
echo "== All parallel builds completed =="

# ===== Mac Catalyst（串行，因需 unset 环境变量）=====
echo "== Mac Catalyst =="
# 注意：Catalyst 编译在某些 CMake/Xcode 版本中可能失败
# 新版 Xcode (>= 26) 要求 Catalyst iOS 版本 >= 14.0
# 如果失败，可以注释掉这部分，因为 macOS 库也可以在 Catalyst 应用中使用
echo "Info: Using MIN_CATALYST_IOS=${MIN_CATALYST_IOS} for Catalyst target"

# 检测当前 Xcode 主版本，若 >= 26 则跳过 x86_64 Catalyst（Apple Silicon Mac 不需要）
XCODE_MAJOR=$(xcodebuild -version 2>/dev/null | awk '/^Xcode/{print int($2)}')
echo "Detected Xcode major version: ${XCODE_MAJOR}"

SKIP_CATALYST_X86=false
if [ "${XCODE_MAJOR}" -ge 26 ] 2>/dev/null; then
  echo "Xcode >= 26 detected: skipping x86_64 Catalyst (not needed on Apple Silicon)"
  SKIP_CATALYST_X86=true
fi

if [ "$SKIP_CATALYST_X86" = false ]; then
  build_catalyst_arch "x86_64" || {
    echo "Catalyst x86_64 build failed, skipping Catalyst support"
    rm -rf "$OUT_DIR/catalyst-x86_64" "$OUT_DIR/catalyst-arm64" "$OUT_DIR/catalyst"
    # 创建一个标记文件表示 Catalyst 不可用
    touch "$OUT_DIR/.catalyst_unavailable"
  }
fi

if [ ! -f "$OUT_DIR/.catalyst_unavailable" ]; then
  build_catalyst_arch "arm64" || {
    echo "Catalyst arm64 build failed, skipping Catalyst support"
    rm -rf "$OUT_DIR/catalyst-x86_64" "$OUT_DIR/catalyst-arm64" "$OUT_DIR/catalyst"
    touch "$OUT_DIR/.catalyst_unavailable"
  }
fi

# 合并 Catalyst 的 fat 库（如果可用）
if [ ! -f "$OUT_DIR/.catalyst_unavailable" ]; then
  HAS_X86_CATALYST=false
  HAS_ARM64_CATALYST=false
  [ -f "$OUT_DIR/catalyst-x86_64/lib/libarchive.a" ] && HAS_X86_CATALYST=true
  [ -f "$OUT_DIR/catalyst-arm64/lib/libarchive.a" ] && HAS_ARM64_CATALYST=true

  if [ "$HAS_X86_CATALYST" = true ] && [ "$HAS_ARM64_CATALYST" = true ]; then
    echo "== Merging Catalyst architectures (arm64 + x86_64) =="
    mkdir -p "$OUT_DIR/catalyst/lib"
    lipo -create \
      "$OUT_DIR/catalyst-x86_64/lib/libarchive.a" \
      "$OUT_DIR/catalyst-arm64/lib/libarchive.a" \
      -output "$OUT_DIR/catalyst/lib/libarchive.a"
    cp -r "$OUT_DIR/catalyst-arm64/include" "$OUT_DIR/catalyst/"
    echo "Catalyst fat library (arm64 + x86_64) created"
  elif [ "$HAS_ARM64_CATALYST" = true ]; then
    echo "== Using Catalyst arm64-only library =="
    mkdir -p "$OUT_DIR/catalyst/lib"
    cp "$OUT_DIR/catalyst-arm64/lib/libarchive.a" "$OUT_DIR/catalyst/lib/libarchive.a"
    cp -r "$OUT_DIR/catalyst-arm64/include" "$OUT_DIR/catalyst/"
    echo "Catalyst arm64-only library created"
  else
    echo "Catalyst support disabled or build failed"
    touch "$OUT_DIR/.catalyst_unavailable"
  fi
else
  echo "Catalyst support disabled or build failed"
fi

# 验证所有生成的库
echo "== Verifying all libraries =="
find "$OUT_DIR" -name "libarchive.a" -type f | while read -r lib; do
  echo "  $(basename $(dirname $(dirname $lib)))/$(basename $lib):"
  lipo -info "$lib" 2>/dev/null | sed 's/^/    /' || echo "    Not a fat library or invalid"
done

# ===== 为每个平台的 Headers 目录生成 module.modulemap（Swift 导入所需）=====
# module.modulemap 让 Swift 可以直接 import libarchive
echo "== Generating module.modulemap for Swift support =="

# module.modulemap 内容：将 archive.h 和 archive_entry.h 暴露为 libarchive 模块
# 注意：静态库（.a）使用 "module"，不使用 "framework module"
MODULEMAP_CONTENT='module libarchive {
    header "archive.h"
    header "archive_entry.h"

    export *
}'

# 为每个平台的 include 目录写入 module.modulemap
for PLATFORM_DIR in \
  "$OUT_DIR/ios-device" \
  "$OUT_DIR/ios-sim" \
  "$OUT_DIR/tvos-device" \
  "$OUT_DIR/tvos-sim" \
  "$OUT_DIR/watchos-device" \
  "$OUT_DIR/watchos-sim" \
  "$OUT_DIR/macos" \
  "$OUT_DIR/catalyst"; do
  if [ -d "$PLATFORM_DIR/include" ]; then
    echo "$MODULEMAP_CONTENT" > "$PLATFORM_DIR/include/module.modulemap"
    echo "  ✓ Written: $PLATFORM_DIR/include/module.modulemap"
  fi
done

# 创建 XCFramework
echo "== Creating XCFramework =="
rm -rf "$XC_OUT"

XC_ARGS=()

# 每个平台使用自己的 headers 目录（包含 module.modulemap）
[ -f "$OUT_DIR/ios-device/lib/libarchive.a" ]     && XC_ARGS+=(-library "$OUT_DIR/ios-device/lib/libarchive.a"     -headers "$OUT_DIR/ios-device/include")
[ -f "$OUT_DIR/ios-sim/lib/libarchive.a" ]         && XC_ARGS+=(-library "$OUT_DIR/ios-sim/lib/libarchive.a"         -headers "$OUT_DIR/ios-sim/include")
[ -f "$OUT_DIR/tvos-device/lib/libarchive.a" ]     && XC_ARGS+=(-library "$OUT_DIR/tvos-device/lib/libarchive.a"     -headers "$OUT_DIR/tvos-device/include")
[ -f "$OUT_DIR/tvos-sim/lib/libarchive.a" ]        && XC_ARGS+=(-library "$OUT_DIR/tvos-sim/lib/libarchive.a"        -headers "$OUT_DIR/tvos-sim/include")
[ -f "$OUT_DIR/watchos-device/lib/libarchive.a" ]  && XC_ARGS+=(-library "$OUT_DIR/watchos-device/lib/libarchive.a"  -headers "$OUT_DIR/watchos-device/include")
[ -f "$OUT_DIR/watchos-sim/lib/libarchive.a" ]     && XC_ARGS+=(-library "$OUT_DIR/watchos-sim/lib/libarchive.a"     -headers "$OUT_DIR/watchos-sim/include")
[ -f "$OUT_DIR/macos/lib/libarchive.a" ]           && XC_ARGS+=(-library "$OUT_DIR/macos/lib/libarchive.a"           -headers "$OUT_DIR/macos/include")
[ -f "$OUT_DIR/catalyst/lib/libarchive.a" ]        && XC_ARGS+=(-library "$OUT_DIR/catalyst/lib/libarchive.a"        -headers "$OUT_DIR/catalyst/include")

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

  echo -e "\nModule map files (Swift support):"
  find "$XC_OUT" -name "module.modulemap" | while read -r f; do
    echo "  ✓ $f"
  done
else
  echo "Error: No libraries found to create XCFramework"
  exit 1
fi

# ===== 清理中间文件，只保留最终的 XCFramework =====
echo ""
echo "== Cleaning up intermediate files =="

rm -rf "$SRC_DIR"      && echo "  ✓ Removed libarchive source directory"
rm -rf "$XZ_SRC_DIR"   && echo "  ✓ Removed xz source directory"
rm -rf "$ZSTD_SRC_DIR" && echo "  ✓ Removed zstd source directory"
rm -rf "$LZ4_SRC_DIR"  && echo "  ✓ Removed lz4 source directory"
rm -rf "$BUILD_DIR"    && echo "  ✓ Removed libarchive build directory"
rm -rf "$XZ_BUILD_DIR"   && echo "  ✓ Removed xz build directory"
rm -rf "$ZSTD_BUILD_DIR" && echo "  ✓ Removed zstd build directory"
rm -rf "$LZ4_BUILD_DIR"  && echo "  ✓ Removed lz4 build directory"
rm -rf "$OUT_DIR"      && echo "  ✓ Removed output directory"
rmdir "$ROOT" 2>/dev/null || true

echo ""
echo "✅ Cleanup complete! Only XCFramework remains:"
echo "   $XC_OUT"
echo ""
echo "📦 Final output size:"
du -sh "$XC_OUT" 2>/dev/null || echo "  (unable to determine size)"

# 可选：将 XCFramework 移动到当前目录
# mv "$XC_OUT" ./libArchive.xcframework
# echo "   Moved to: $(pwd)/libArchive.xcframework"
