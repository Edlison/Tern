# Release guide

The repository can be published independently of a notarized application release. **An ad-hoc preview is not the public macOS release.**

## Source readiness

```sh
./scripts/audit-source.py
swift test
./scripts/package-release.sh --preview
```

Review the tracked file list, README, integration limitations, MIT license, privacy document and branding provenance. Include only original/synthetic screenshots. The audit is a pattern-based guard, not a proof that all sensitive information is absent. CI runs tests, audits source and builds a universal preview artifact on macOS; it does not publish a GitHub Release.

The preview ZIP in `dist/` contains a universal arm64/x86_64 app and a SHA-256 sidecar. Its filename contains `preview`. Build/test logs and generated ZIPs are ignored by Git. Local code-sign verification does not mean notarization or Gatekeeper acceptance.

## Public application release

Prerequisites:

1. A valid **Developer ID Application** identity and private key in the signing machine's Keychain.
2. An existing `notarytool` Keychain profile authorized for the correct Apple developer team.
3. A clean, reviewed source revision and matching version/build values in `Resources/Info.plist`.

Do not commit certificates, private keys, Apple credentials or notarization secrets. Configure credentials outside the repository.

```sh
export TERN_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export TERN_NOTARY_PROFILE='your-existing-keychain-profile'
./scripts/package-release.sh --signed
```

This command is an explicit release operation: it builds both architectures, signs with Hardened Runtime and a timestamp, uploads the ZIP to Apple's notary service, waits, staples the app, verifies Developer ID/Hardened Runtime/stapling/Gatekeeper acceptance, then creates the final ZIP and checksum. Any failure stops packaging. It never creates a certificate, signs in, modifies an agent account, or publishes a GitHub Release.

The `--signed` path is intentionally unavailable without the signing identity and notary profile. Do not rename a preview to remove that requirement. Public verification is also available separately:

```sh
./scripts/verify-app.sh build/Tern.app --public
```

## Before announcing

- Test the notarized ZIP on a clean supported Mac with quarantine intact, including Intel if distributing the Intel slice.
- Confirm current provider cache versions, local/cloud/SSH coverage, a real new delivery, read confirmation and offline behavior. Do not claim end-to-end cloud validation from parser fixtures alone.
- Check hover-only expansion, fixed top edge, both width ranges, Reduce Motion, multiple screens/Spaces, notification permission and audio routing. HomePod needs actual hardware verification.
- Review release notes, attach the final signed/notarized ZIP and matching SHA-256, and only then publish the release using your chosen repository host.

## Upgrade identity

`dev.bolin.agent-island` remains the bundle identifier to preserve prototype preferences, inbox state and notification permissions. Product, executable, package and source target names are Tern. Changing the identifier later needs an explicit preferences/inbox migration.

## Apple references

[Developer ID](https://developer.apple.com/developer-id/) · [Notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [Privacy manifest](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
