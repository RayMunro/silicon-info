#!/bin/zsh
# Builds "Silicon Info.app", a floating CPU / GPU / Neural Engine widget.
# Quit it with `pkill SiliconWidget`.
set -e
cd "$(dirname "$0")"
swift build -c release
APP="Silicon Info.app"
rm -rf "$APP" SiliconWidget.app && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SiliconWidget "$APP/Contents/MacOS/"
swift scripts/make_icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Silicon Info</string>
<key>CFBundleDisplayName</key><string>Silicon Info</string>
<key>CFBundleIdentifier</key><string>com.raymunro.siliconinfo</string>
<key>CFBundleExecutable</key><string>SiliconWidget</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Ray Munro</string>
<key>LSUIElement</key><true/>
</dict></plist>
PL
codesign --force --sign - "$APP"
echo "Built $APP"
