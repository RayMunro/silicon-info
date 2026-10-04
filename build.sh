#!/bin/zsh
# Generates the Xcode project from project.yml, then builds and signs SiliconInfo.app with its widget.
# Requires Xcode and XcodeGen (brew install xcodegen). Output: build/Build/Products/Release/SiliconInfo.app
set -eo pipefail
cd "$(dirname "$0")"
xcodegen generate --quiet
xcodebuild -project SiliconInfo.xcodeproj -scheme SiliconInfo -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates build | tail -5
echo "Built build/Build/Products/Release/SiliconInfo.app"
