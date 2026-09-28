#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$BUILD_DIR/cpsmart.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/CPSmartAppIcon.iconset"
STAGING_DIR="$BUILD_DIR/dmg-staging"
SDK_PATH="${CPSMART_SDK_PATH:-}"
VERSION="${CPSMART_VERSION:-$(tr -d '[:space:]' < "$PROJECT_DIR/VERSION")}"
BUILD_NUMBER="${CPSMART_BUILD_NUMBER:-$(tr -d '[:space:]' < "$PROJECT_DIR/BUILD_NUMBER")}"
SIGN_IDENTITY="${CPSMART_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${CPSMART_NOTARY_PROFILE:-}"
BUILD_MODE="local"

usage() {
    echo "Usage: $0 [--local | --self-signed | --release] [--version X.Y.Z] [--build-number N]"
    echo "          [--sign-identity NAME] [--notary-profile PROFILE]"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --local)
            BUILD_MODE="local"
            shift
            ;;
        --self-signed)
            BUILD_MODE="self-signed"
            shift
            ;;
        --release)
            BUILD_MODE="release"
            shift
            ;;
        --version)
            VERSION="${2:?--version requires a value}"
            shift 2
            ;;
        --build-number)
            BUILD_NUMBER="${2:?--build-number requires a value}"
            shift 2
            ;;
        --sign-identity)
            SIGN_IDENTITY="${2:?--sign-identity requires a value}"
            shift 2
            ;;
        --notary-profile)
            NOTARY_PROFILE="${2:?--notary-profile requires a value}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid version '$VERSION'; expected X.Y.Z" >&2
    exit 2
fi
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid build number '$BUILD_NUMBER'; expected a positive integer" >&2
    exit 2
fi
if [[ "$BUILD_MODE" == "self-signed" && "$SIGN_IDENTITY" == "-" ]]; then
    echo "A self-signed release requires --sign-identity with the long-lived cpsmart identity" >&2
    exit 2
fi
if [[ "$BUILD_MODE" == "release" && "$SIGN_IDENTITY" == "-" ]]; then
    echo "A formal release requires --sign-identity with a Developer ID Application identity" >&2
    exit 2
fi
if [[ "$BUILD_MODE" == "release" && -z "$NOTARY_PROFILE" ]]; then
    echo "A formal release requires --notary-profile for notarytool" >&2
    exit 2
fi
if [[ "$BUILD_MODE" != "release" && -n "$NOTARY_PROFILE" ]]; then
    echo "--notary-profile is only valid with --release" >&2
    exit 2
fi

DMG_PATH="$DIST_DIR/cpsmart-$VERSION-universal.dmg"

if [[ -z "$SDK_PATH" && -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
    SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
fi
if [[ -z "$SDK_PATH" ]]; then
    SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

mkdir -p "$BUILD_DIR" "$DIST_DIR" "$MACOS_DIR" "$RESOURCES_DIR"

build_architecture() {
    local architecture="$1"
    local scratch_path="$PROJECT_DIR/.build/$architecture"
    local module_cache="$PROJECT_DIR/.build/module-cache-$architecture"
    mkdir -p "$module_cache"
    SDKROOT="$SDK_PATH" \
    CLANG_MODULE_CACHE_PATH="$module_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" \
    swift build \
        --package-path "$PROJECT_DIR" \
        --disable-sandbox \
        --configuration release \
        --product cpsmart \
        --triple "$architecture-apple-macosx13.0" \
        --scratch-path "$scratch_path" >&2 || return 1
    local binary_path="$scratch_path/$architecture-apple-macosx/release/cpsmart"
    if [[ ! -x "$binary_path" ]]; then
        echo "Missing $architecture build product: $binary_path" >&2
        return 1
    fi
    echo "$binary_path"
}

X86_BINARY="$(build_architecture x86_64 | tail -n 1)"
ARM_BINARY="$(build_architecture arm64 | tail -n 1)"

lipo -create "$X86_BINARY" "$ARM_BINARY" -output "$MACOS_DIR/cpsmart"
chmod 755 "$MACOS_DIR/cpsmart"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp -R "$PROJECT_DIR/Resources/en.lproj" "$PROJECT_DIR/Resources/zh-Hans.lproj" "$RESOURCES_DIR/"
for language in en zh-Hans; do
    cp "$PROJECT_DIR/Sources/cpsmart/Resources/$language.lproj/Localizable.strings" \
        "$RESOURCES_DIR/$language.lproj/Localizable.strings"
done
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

rm -rf "$ICONSET_DIR"
rm -f "$RESOURCES_DIR/AppIcon.icns" "$RESOURCES_DIR/CPSmartAppIcon.icns"
CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache-icon" \
    swift -sdk "$SDK_PATH" "$PROJECT_DIR/Scripts/generate_icon.swift" "$ICONSET_DIR"
CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache-icon" \
    swift -sdk "$SDK_PATH" "$PROJECT_DIR/Scripts/create_icns.swift" \
    "$ICONSET_DIR" "$RESOURCES_DIR/CPSmartAppIcon.icns"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP_DIR"
elif [[ "$BUILD_MODE" == "self-signed" ]]; then
    codesign \
        --force \
        --options runtime \
        --timestamp=none \
        --sign "$SIGN_IDENTITY" \
        "$APP_DIR"
else
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$SIGN_IDENTITY" \
        "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"

if [[ "$BUILD_MODE" == "self-signed" ]]; then
    DESIGNATED_REQUIREMENT="$(codesign --display -r- "$APP_DIR" 2>&1)"
    if [[ "$DESIGNATED_REQUIREMENT" == *"cdhash"* ]]; then
        echo "Self-signed release has a version-specific designated requirement; refusing to package" >&2
        exit 1
    fi
    if [[ "$DESIGNATED_REQUIREMENT" != *'identifier "com.cpsmart.app"'* ]]; then
        echo "Self-signed release does not identify com.cpsmart.app; refusing to package" >&2
        exit 1
    fi
fi

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/cpsmart.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "cpsmart Installer" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

if [[ "$BUILD_MODE" == "release" ]]; then
    xcrun notarytool submit \
        "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
fi

echo "cpsmart $VERSION (build $BUILD_NUMBER)"
echo "Mode: $BUILD_MODE"
echo "$DMG_PATH"
