#!/bin/bash
set -e

PROJECT="ClaudeUsageMonitor.xcodeproj"
SCHEME="ClaudeUsageMonitor"
APP_NAME="Claude Usage Monitor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
DIST_DIR="$REPO_ROOT/dist"
ICON_SRC="$SCRIPT_DIR/claude_usage_monitor_icon.png"
PROJECT="$REPO_ROOT/$PROJECT"

mkdir -p "$DIST_DIR"

build_and_package() {
    local ARCH=$1
    local ARCH_LABEL=$2
    local ARCHIVE_PATH="$BUILD_DIR/$ARCH_LABEL/$APP_NAME.xcarchive"
    local DMG_NAME="${APP_NAME}-${ARCH_LABEL}.dmg"

    echo "==> Building for $ARCH_LABEL ($ARCH)..."

    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" \
        ARCHS="$ARCH" \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=YES \
        OTHER_CODE_SIGN_FLAGS="--deep" \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        | xcpretty 2>/dev/null || true

    echo "==> Extracting .app from archive..."
    APP_PATH=$(find "$ARCHIVE_PATH/Products" -name "*.app" | head -1)
    if [ -z "$APP_PATH" ]; then
        echo "ERROR: Could not find .app in archive"
        exit 1
    fi

    echo "==> Creating styled DMG for $ARCH_LABEL..."
    local STAGING_DIR="$BUILD_DIR/$ARCH_LABEL/dmg_staging"
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"
    cp -R "$APP_PATH" "$STAGING_DIR/"
    ln -s /Applications "$STAGING_DIR/Applications"

    # Set custom icon on the .app using the logo PNG
    local ICON_ICNS="$BUILD_DIR/$ARCH_LABEL/AppIcon.icns"
    local ICONSET_DIR="$BUILD_DIR/$ARCH_LABEL/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    sips -z 16  16  "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png"     > /dev/null
    sips -z 32  32  "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png"  > /dev/null
    sips -z 32  32  "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png"     > /dev/null
    sips -z 64  64  "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png"  > /dev/null
    sips -z 128 128 "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png"   > /dev/null
    sips -z 256 256 "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png"> /dev/null
    sips -z 256 256 "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png"   > /dev/null
    sips -z 512 512 "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png"> /dev/null
    sips -z 512 512 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png"      > /dev/null
    sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null
    iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
    # Apply icon to .app bundle
    cp "$ICON_ICNS" "$STAGING_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns"
    # Clear the kHasCustomIcon FinderInfo bit — it conflicts with CFBundleIconFile for .app bundles
    xattr -wx com.apple.FinderInfo \
        "0000000000000000000000000000000000000000000000000000000000000000" \
        "$STAGING_DIR/$APP_NAME.app" 2>/dev/null || true
    # Register with Launch Services so the icon is pre-indexed
    LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
    "$LSREG" -f "$STAGING_DIR/$APP_NAME.app" 2>/dev/null || true
    touch "$STAGING_DIR/$APP_NAME.app"

    local DMG_TMP="$BUILD_DIR/$ARCH_LABEL/${APP_NAME}_tmp.dmg"
    local DMG_OUT="$DIST_DIR/$DMG_NAME"
    rm -f "$DMG_TMP" "$DMG_OUT"

    # Create a writable DMG large enough to customize
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$STAGING_DIR" \
        -ov \
        -format UDRW \
        -size 200m \
        "$DMG_TMP"

    # Ensure mount point is free before attaching
    local MOUNT_DIR="/Volumes/${APP_NAME}"
    hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
    hdiutil attach "$DMG_TMP" -mountpoint "$MOUNT_DIR" -noautoopen -quiet

    # Use AppleScript to style the Finder window
    osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 200, 940, 540}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        set position of item "$APP_NAME.app" of container window to {130, 200}
        set position of item "Applications" of container window to {410, 200}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT

    # Unmount
    sync
    hdiutil detach "$MOUNT_DIR" -force -quiet

    # Convert to compressed read-only DMG
    hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_OUT"
    rm -f "$DMG_TMP"

    echo "==> Done: $DMG_OUT"
    echo ""
}

build_and_package "arm64" "arm64"
build_and_package "x86_64" "x86_64"

echo "=== Build complete ==="
echo "Output files:"
ls -lh "$DIST_DIR/"
