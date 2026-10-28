#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-}"
case "$mode" in
  --preview)
    unset TERN_SIGNING_IDENTITY
    suffix="-preview"
    ;;
  --signed)
    : "${TERN_SIGNING_IDENTITY:?Set a Developer ID Application certificate name}"
    : "${TERN_NOTARY_PROFILE:?Set the name of an existing notarytool keychain profile}"
    [[ "$TERN_SIGNING_IDENTITY" == "Developer ID Application:"* ]] || { echo "Invalid signing identity" >&2; exit 2; }
    if [[ -n "$(git status --porcelain)" ]]; then echo "Commit/review source changes before a signed release." >&2; exit 2; fi
    suffix=""
    ;;
  *) echo "Usage: scripts/package-release.sh --preview|--signed" >&2; exit 2 ;;
esac
./scripts/audit-source.py
./scripts/build.sh --universal
app="$PWD/build/Tern.app"
archs="$(lipo -archs "$app/Contents/MacOS/Tern")"
[[ " $archs " == *" arm64 "* && " $archs " == *" x86_64 "* ]] || { echo "Universal binary required" >&2; exit 1; }
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
mkdir -p dist
archive="$PWD/dist/Tern-$version$suffix-universal.zip"
if [[ "$mode" == "--signed" ]]; then
  submission="$PWD/build/Tern-notary-submission.zip"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$submission"
  xcrun notarytool submit "$submission" --keychain-profile "$TERN_NOTARY_PROFILE" --wait
  xcrun stapler staple "$app"
  ./scripts/verify-app.sh "$app" --public
fi
ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
(cd dist && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
printf '%s\n' "$archive"
if [[ "$mode" == "--preview" ]]; then echo "Preview only: ad-hoc signed, not notarized. Do not publish as the verified public release."; fi
