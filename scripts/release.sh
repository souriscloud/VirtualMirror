#!/usr/bin/env bash
#
# VirtualMirror Release Script
#
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 1.0.0
#
# This script performs a complete release:
#   1. Preflight checks (certs, credentials, tools, clean tree)
#   2. Version bump in project.pbxproj
#   3. Archive with Release configuration
#   4. Export with Developer ID signing
#   5. Notarize and staple the .app
#   6. Create branded DMG, sign, notarize, staple
#   7. Generate Sparkle appcast via generate_appcast
#   8. Git commit, push, create GitHub Release with DMG
#
# One-time setup (before first release):
#   1. Install "Developer ID Application" certificate
#   2. Store notarization credentials:
#        xcrun notarytool store-credentials "VirtualMirror" \
#          --apple-id <email> --team-id 26GLU32796 --password <app-specific-password>
#   3. Generate Sparkle EdDSA keys:
#        ./scripts/sparkle-tools.sh generate_keys
#   4. Install GitHub CLI: brew install gh && gh auth login
#

set -euo pipefail

# --- Configuration ---
TEAM_ID="26GLU32796"
SCHEME="VirtualMirror"
PROJECT="VirtualMirror.xcodeproj"
APP_NAME="VirtualMirror"
NOTARYTOOL_PROFILE="VirtualMirror"
DMG_VOLUME_NAME="VirtualMirror"
CODESIGN_IDENTITY="Developer ID Application: Luk Novotn (26GLU32796)"
GITHUB_REPO="souriscloud/VirtualMirror"

# --- Derived paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/release"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
RELEASES_DIR="$PROJECT_DIR/releases"

# --- Helpers ---
info()    { printf "\033[1;34m==>\033[0m \033[1m%s\033[0m\n" "$*"; }
success() { printf "\033[1;32m==>\033[0m \033[1m%s\033[0m\n" "$*"; }
warn()    { printf "\033[1;33mWARN:\033[0m %s\n" "$*"; }
error()   { printf "\033[1;31mERROR:\033[0m %s\n" "$*" >&2; exit 1; }

sparkle_tool() {
    "$SCRIPT_DIR/sparkle-tools.sh" "$@"
}

cleanup() {
    rm -rf "$BUILD_DIR/dmg-staging" "$BUILD_DIR/ExportOptions.plist" "$BUILD_DIR/$APP_NAME-notarize.zip"
}
trap cleanup EXIT

# --- Validate arguments ---
VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 1.0.0"
    exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "Version must be in semver format (e.g. 1.0.0), got: $VERSION"
fi

# Parse version for build number: 1.2.3 -> 10203
IFS='.' read -ra VER_PARTS <<< "$VERSION"
MAJOR="${VER_PARTS[0]}"
MINOR="${VER_PARTS[1]}"
PATCH="${VER_PARTS[2]}"
BUILD_NUMBER=$(( MAJOR * 10000 + MINOR * 100 + PATCH ))

DMG_FILENAME="$APP_NAME-$VERSION.dmg"
DMG_BUILD_PATH="$BUILD_DIR/$DMG_FILENAME"

# ==========================================================================
# PREFLIGHT CHECKS
# ==========================================================================
info "Preflight checks for $APP_NAME v$VERSION (build $BUILD_NUMBER)"

# Check gh CLI
if ! command -v gh &>/dev/null; then
    error "GitHub CLI (gh) not found. Install: brew install gh && gh auth login"
fi
if ! gh auth status &>/dev/null 2>&1; then
    error "GitHub CLI not authenticated. Run: gh auth login"
fi

# Check Developer ID cert
if ! security find-identity -v -p codesigning | grep -q "$CODESIGN_IDENTITY"; then
    error "Codesigning identity not found: $CODESIGN_IDENTITY"
fi

# Check notarytool credentials
if ! xcrun notarytool history --keychain-profile "$NOTARYTOOL_PROFILE" &>/dev/null 2>&1; then
    error "Notarization credentials not found for profile '$NOTARYTOOL_PROFILE'. Run:\n  xcrun notarytool store-credentials \"$NOTARYTOOL_PROFILE\" --apple-id <email> --team-id $TEAM_ID --password <app-specific-password>"
fi

# Check Sparkle tools
if ! sparkle_tool generate_keys -p &>/dev/null 2>&1; then
    error "Sparkle EdDSA key not found. Run: ./scripts/sparkle-tools.sh generate_keys"
fi

# Check working tree is clean
if ! git -C "$PROJECT_DIR" diff --quiet || ! git -C "$PROJECT_DIR" diff --cached --quiet; then
    error "Working tree has uncommitted changes. Commit or stash them first."
fi
if [[ -n "$(git -C "$PROJECT_DIR" ls-files --others --exclude-standard)" ]]; then
    error "Working tree has untracked files. Commit or remove them first."
fi

# Check the tag doesn't already exist
if git -C "$PROJECT_DIR" rev-parse "v$VERSION" &>/dev/null 2>&1; then
    error "Git tag v$VERSION already exists. Choose a different version."
fi

success "All preflight checks passed"

# ==========================================================================
# STEP 1: VERSION BUMP
# ==========================================================================
info "Step 1/8: Bumping version to $VERSION (build $BUILD_NUMBER)"

PBXPROJ="$PROJECT_DIR/$PROJECT/project.pbxproj"
sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $VERSION/" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $BUILD_NUMBER/" "$PBXPROJ"

success "Version updated in project.pbxproj"

# ==========================================================================
# STEP 2: ARCHIVE
# ==========================================================================
info "Step 2/8: Archiving with Release configuration"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild archive \
    -project "$PROJECT_DIR/$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -quiet \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_IDENTITY="$CODESIGN_IDENTITY" \
    ENABLE_HARDENED_RUNTIME=YES

[[ -d "$ARCHIVE_PATH" ]] || error "Archive failed — $ARCHIVE_PATH not found"
success "Archive created"

# ==========================================================================
# STEP 3: EXPORT
# ==========================================================================
info "Step 3/8: Exporting with Developer ID signing"

cat > "$BUILD_DIR/ExportOptions.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>26GLU32796</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -quiet

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || error "Export failed — $APP_PATH not found"
success "Exported signed app"

# ==========================================================================
# STEP 4: NOTARIZE + STAPLE THE APP
# ==========================================================================
info "Step 4/8: Notarizing app with Apple"

NOTARIZE_ZIP="$BUILD_DIR/$APP_NAME-notarize.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARIZE_ZIP"

xcrun notarytool submit "$NOTARIZE_ZIP" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

info "Stapling notarization ticket to app"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

success "App notarized and stapled"

# ==========================================================================
# STEP 5: CREATE BRANDED DMG
# ==========================================================================
info "Step 5/8: Creating branded DMG"

DMG_STAGING="$BUILD_DIR/dmg-staging"
DMG_TEMP="$BUILD_DIR/$APP_NAME-temp.dmg"
mkdir -p "$DMG_STAGING"

# Copy app and create Applications symlink
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

# Copy background images if they exist
BG_2X="$SCRIPT_DIR/dmg-background@2x.png"
if [[ -f "$BG_2X" ]]; then
    mkdir -p "$DMG_STAGING/.background"
    cp "$BG_2X" "$DMG_STAGING/.background/background@2x.png"
    [[ -f "$SCRIPT_DIR/dmg-background.png" ]] && cp "$SCRIPT_DIR/dmg-background.png" "$DMG_STAGING/.background/background.png"
    HAS_BACKGROUND=true
else
    HAS_BACKGROUND=false
fi

# Create read-write temp DMG
hdiutil create -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDRW \
    "$DMG_TEMP" \
    -quiet

# Mount and customize icon layout
MOUNT_DIR=$(hdiutil attach -readwrite -noverify "$DMG_TEMP" | grep "/Volumes/" | sed 's/.*\(\/Volumes\/.*\)/\1/')

if [[ "$HAS_BACKGROUND" == "true" ]]; then
    osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$DMG_VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 740, 580}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set background picture of theViewOptions to file ".background:background@2x.png"
        set position of item "$APP_NAME.app" of container window to {160, 240}
        set position of item "Applications" of container window to {480, 240}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
else
    osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$DMG_VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 640, 480}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 128
        set position of item "$APP_NAME.app" of container window to {140, 200}
        set position of item "Applications" of container window to {400, 200}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
fi

hdiutil detach "$MOUNT_DIR" -quiet

# Convert to compressed read-only DMG
hdiutil convert "$DMG_TEMP" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_BUILD_PATH" \
    -quiet

rm -f "$DMG_TEMP"
success "DMG created: $DMG_FILENAME"

# ==========================================================================
# STEP 6: SIGN + NOTARIZE THE DMG
# ==========================================================================
info "Step 6/8: Signing and notarizing DMG"

codesign --force --sign "$CODESIGN_IDENTITY" "$DMG_BUILD_PATH"

xcrun notarytool submit "$DMG_BUILD_PATH" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait

xcrun stapler staple "$DMG_BUILD_PATH"

success "DMG signed, notarized, and stapled"

# ==========================================================================
# STEP 7: GENERATE SPARKLE APPCAST
# ==========================================================================
info "Step 7/8: Generating Sparkle appcast"

mkdir -p "$RELEASES_DIR"

# Copy the final DMG to releases/ directory
cp "$DMG_BUILD_PATH" "$RELEASES_DIR/$DMG_FILENAME"

DOWNLOAD_PREFIX="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/"

# generate_appcast reads all DMGs in the directory, extracts version info
# from the embedded app bundles, signs them with the EdDSA key from the
# Keychain, and writes a properly formatted appcast.xml.
#
# --download-url-prefix sets the base URL for each DMG's download link.
# Since each version may have a different GH release tag URL, we use
# --versions to only process the new DMG (preserving existing entries).
sparkle_tool generate_appcast \
    --download-url-prefix "$DOWNLOAD_PREFIX" \
    -o "$PROJECT_DIR/appcast.xml" \
    "$RELEASES_DIR"

success "Appcast updated at appcast.xml"

# ==========================================================================
# STEP 8: GIT COMMIT, PUSH, GITHUB RELEASE
# ==========================================================================
info "Step 8/8: Publishing release"

cd "$PROJECT_DIR"

# Commit version bump + appcast
git add "$PBXPROJ" appcast.xml
git commit -m "Release v$VERSION"

# Push to remote
CURRENT_BRANCH=$(git branch --show-current)
git push origin "$CURRENT_BRANCH"

# Create GitHub release with DMG attached
gh release create "v$VERSION" \
    "$RELEASES_DIR/$DMG_FILENAME" \
    --repo "$GITHUB_REPO" \
    --title "v$VERSION" \
    --notes "VirtualMirror v$VERSION" \
    --latest

RELEASE_URL="https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"

# ==========================================================================
# DONE
# ==========================================================================
echo ""
success "Release v$VERSION published!"
echo ""
echo "  GitHub Release:  $RELEASE_URL"
echo "  DMG download:    ${DOWNLOAD_PREFIX}${DMG_FILENAME}"
echo "  Appcast:         https://raw.githubusercontent.com/$GITHUB_REPO/main/appcast.xml"
echo ""
echo "  Users running VirtualMirror will be notified of the update"
echo "  via Sparkle within a few minutes (GitHub raw CDN cache)."
echo ""
