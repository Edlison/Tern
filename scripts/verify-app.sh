#!/bin/bash
set -euo pipefail
app="${1:-build/Tern.app}"
public="${2:-}"
test -x "$app/Contents/MacOS/Tern"
test -d "$app/Contents/Resources/Tern_TernCore.bundle"
test -f "$app/Contents/Resources/PrivacyInfo.xcprivacy"
plutil -lint "$app/Contents/Info.plist" "$app/Contents/Resources/PrivacyInfo.xcprivacy"
codesign --verify --deep --strict "$app"
xcrun vtool -show-build "$app/Contents/MacOS/Tern" | awk '
  $1 == "minos" { found++; if ($2 + 0 > 14.0) bad = 1 }
  END { if (!found || bad) { print "Binary minimum OS exceeds the documented macOS 14 target" > "/dev/stderr"; exit 1 } }
'
if [[ "$public" == "--public" ]]; then
  codesign -dv --verbose=4 "$app" 2>&1 | /usr/bin/grep -q '^Authority=Developer ID Application:'
  codesign -dv --verbose=4 "$app" 2>&1 | /usr/bin/grep -q 'runtime'
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=2 "$app"
fi
