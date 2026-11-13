#!/bin/bash
# Builds Qlix.app (universal: Apple Silicon + Intel). Requires Xcode Command Line Tools:
#   xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

# If Terminal is running under Rosetta on an Apple Silicon Mac, relaunch natively
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ] && [ "$(uname -m)" != "arm64" ]; then
  echo "Rosetta detected, relaunching natively…"
  exec arch -arm64 bash "$0" "$@"
fi

NAME="Qlix"
BUNDLE_ID="com.oldsoultech.qlix"
VERSION="1.0"
APP="build/$NAME.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling…"
swiftc -O -target arm64-apple-macos12  main.swift -o "build/$NAME-arm64"
swiftc -O -target x86_64-apple-macos12 main.swift -o "build/$NAME-x86_64"
lipo -create "build/$NAME-arm64" "build/$NAME-x86_64" -output "$APP/Contents/MacOS/$NAME"
rm "build/$NAME-arm64" "build/$NAME-x86_64"

# Optional icon: drop a 1024x1024 icon.png next to this script
ICON_KEY=""
if [ -f icon.png ]; then
  echo "Building icon…"
  SET="build/icon.iconset"
  mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s           icon.png --out "$SET/icon_${s}x${s}.png"     >/dev/null
    sips -z $((s*2)) $((s*2)) icon.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$SET"
  ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSCameraUsageDescription</key><string>$NAME needs camera access if the page requests it.</string>
  <key>NSMicrophoneUsageDescription</key><string>$NAME needs microphone access if the page requests it.</string>
  $ICON_KEY
</dict>
</plist>
EOF

# Ad-hoc sign so macOS will run it locally
codesign --force --deep --sign - "$APP"

echo
echo "Done: $(pwd)/$APP"
echo "Run:      open \"$APP\""
echo "Install:  cp -R \"$APP\" /Applications/"
