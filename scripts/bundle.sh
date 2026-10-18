#!/usr/bin/env bash
# Builds Switchboard.app into ./build from the Swift package.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/Switchboard.app"
VERSION="${VERSION:-0.1.0}"

swift build -c "$CONFIG" --arch arm64 --arch x86_64
BIN="$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)/Switchboard"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Switchboard"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Switchboard</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.jpc4729.switchboard</string>
    <key>CFBundleName</key>
    <string>Switchboard</string>
    <key>CFBundleDisplayName</key>
    <string>Switchboard</string>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>io.github.jpc4729.switchboard</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>switchboard</string>
            </array>
        </dict>
    </array>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so the app runs locally without a developer account.
codesign --force --sign - "$APP"

echo "Built $APP"
