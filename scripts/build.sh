#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:---local}"
case "$mode" in
  --local) build_args=(-c release); channel="local-preview" ;;
  --universal) build_args=(-c release --arch arm64 --arch x86_64 --scratch-path .build/universal); channel="local-preview" ;;
  *) echo "Usage: scripts/build.sh [--local|--universal]" >&2; exit 2 ;;
esac
identity="${TERN_SIGNING_IDENTITY:--}"
if [[ "$identity" != "-" && "$identity" != "Developer ID Application:"* ]]; then
  echo "TERN_SIGNING_IDENTITY must name a Developer ID Application certificate." >&2; exit 2
fi
swift build "${build_args[@]}"
bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
mkdir -p build/tools
swiftc Sources/TernCore/BrandMark.swift scripts/make-icon.swift -o build/tools/make-icon
build/tools/make-icon
app="$PWD/build/Tern.app"
# Replace only this script's generated bundle. User data lives in Application Support / preferences.
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Tern" "$app/Contents/MacOS/Tern"
cp -R "$bin_dir/Tern_TernCore.bundle" "$app/Contents/Resources/"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/PrivacyInfo.xcprivacy "$app/Contents/Resources/"
if [[ "$identity" != "-" ]]; then channel="developer-id"; fi
/usr/libexec/PlistBuddy -c "Add :TernDistributionChannel string $channel" "$app/Contents/Info.plist"
if [[ "$identity" == "-" ]]; then
  codesign --force --sign - "$app"
else
  codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
./scripts/verify-app.sh "$app"
printf 'Built %s (%s)\n' "$app" "$channel"
