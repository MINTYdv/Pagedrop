#!/usr/bin/env bash
#
# Builds a Release version of Pagedrop, signs it ad hoc and zips it.
#
# There is no Developer ID certificate behind this build, so the app is signed with the
# ad-hoc identity ("-"). macOS will ask for confirmation the first time it is opened.
#
# Usage: scripts/release.sh
# Output: build/Pagedrop.zip

set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR="build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP="$BUILD_DIR/Pagedrop.app"
ZIP="$BUILD_DIR/Pagedrop.zip"
ENTITLEMENTS="Pagedrop/Resources/Pagedrop.entitlements"

rm -rf "$APP" "$ZIP"

echo "Building Release…"
xcodebuild \
    -project Pagedrop.xcodeproj \
    -scheme Pagedrop \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -quiet \
    CODE_SIGNING_ALLOWED=NO \
    build

cp -R "$DERIVED_DATA/Build/Products/Release/Pagedrop.app" "$APP"

echo "Signing (ad hoc)…"
# Re-sign everything with the hardened runtime and the sandbox entitlements.
codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" -s - "$APP"
codesign --verify --deep --strict "$APP"

echo "Zipping…"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "$PWD/$ZIP"
