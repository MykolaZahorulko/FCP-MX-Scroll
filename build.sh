#!/bin/zsh
set -euo pipefail

APP_NAME="FCP-MX-Scroll"
BUNDLE_ID="com.mriynick.FCP-MX-Scroll"
BUILD_DIR="build/dmg_root"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"

rm -rf build
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"
if [[ -f AppIcon.icns ]]; then
    cp AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
    cp AppIcon.icns "${BUILD_DIR}/.VolumeIcon.icns"
fi
cp README.txt "${BUILD_DIR}/README.txt"
ln -sf /Applications "${BUILD_DIR}/Applications"

swiftc -O -target arm64-apple-macos13.0 \
    -framework Cocoa \
    -framework SwiftUI \
    -framework CoreGraphics \
    -framework ApplicationServices \
    -framework ServiceManagement \
    main.swift \
    -o "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

codesign --force --deep --sign - -i "${BUNDLE_ID}" "${APP_BUNDLE}"
hdiutil create -volname "${APP_NAME}" -srcfolder "${BUILD_DIR}" -ov -format UDZO "${APP_NAME}.dmg"
echo "Built ${APP_NAME}.dmg successfully."
