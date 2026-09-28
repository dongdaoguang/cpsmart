#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build/core-tests"
MODULE_CACHE="$PROJECT_DIR/.build/module-cache-tests"
SDK_PATH="${CLIPSHELF_SDK_PATH:-}"

# 完整 Xcode 提供 XCTest；仅安装 Command Line Tools 的机器没有该模块。
# 有 XCTest 时始终走 SwiftPM 标准测试目标，下面的直接编译只作为兼容回退。
if xcrun --find xctest >/dev/null 2>&1; then
    cd "$PROJECT_DIR"
    exec swift test
fi

if [[ -z "$SDK_PATH" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi
if [[ -z "$SDK_PATH" ]]; then
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" swiftc \
    -sdk "$SDK_PATH" \
    -target "$(uname -m)-apple-macosx13.0" \
    "$PROJECT_DIR/Sources/cpsmart/Models.swift" \
    "$PROJECT_DIR/Sources/cpsmart/Localization.swift" \
    "$PROJECT_DIR/Sources/cpsmart/HistoryStore.swift" \
    "$PROJECT_DIR/Sources/cpsmart/PinboardStore.swift" \
    "$PROJECT_DIR/Sources/cpsmart/PinboardInteractionSupport.swift" \
    "$PROJECT_DIR/Sources/cpsmart/ClipboardMonitor.swift" \
    "$PROJECT_DIR/Sources/cpsmart/SearchFilter.swift" \
    "$PROJECT_DIR/Sources/cpsmart/HistoryFilterState.swift" \
    "$PROJECT_DIR/Sources/cpsmart/ThumbnailProvider.swift" \
    "$PROJECT_DIR/Sources/cpsmart/AdaptivePreviewSizing.swift" \
    "$PROJECT_DIR/Sources/cpsmart/HistoryPreviewState.swift" \
    "$PROJECT_DIR/Sources/cpsmart/DisplayGeometry.swift" \
    "$PROJECT_DIR/Sources/cpsmart/HistorySelectionState.swift" \
    "$PROJECT_DIR/Sources/cpsmart/AccessibilityPermissionSupport.swift" \
    "$PROJECT_DIR/Sources/cpsmart/UpdateSupport.swift" \
    "$PROJECT_DIR/Sources/cpsmart/KeyboardShortcuts.swift" \
    "$PROJECT_DIR/Tests/cpsmartTests/CoreTestSupport.swift" \
    "$PROJECT_DIR/Scripts/core_test_runner.swift" \
    -o "$BUILD_DIR/cpsmartCoreTests"

"$BUILD_DIR/cpsmartCoreTests"
