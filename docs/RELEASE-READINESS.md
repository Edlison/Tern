# 0.7.0 readiness snapshot

Local validation on 2026-10-28. This is a verification record, not a public-release announcement.

| Item | Result |
| --- | --- |
| Source migration | Project moved to its Tern directory; authored inputs were SHA-256 checked before edits. Prior diagnostics/backups are outside the repository. |
| Product identity | Tern naming, original folded-wing artwork, 512px icon source and generated ICNS. Prototype bundle ID retained for settings compatibility. |
| Tests | 84 tests passed: 69 core and 15 application tests. |
| Production build | Universal arm64 + x86_64 binary built; both load commands report minimum macOS 14.0. |
| Bundle | Info.plist and privacy manifest validated; strict code-sign verification passed for the ad-hoc preview. |
| Packaging | Universal preview ZIP and SHA-256 generated. |
| Release gates | A preview fails the public Developer ID/notarization gate; missing signing credentials stop the signed path before submission. |
| Source audit | No generated/private payloads detected in the publishable file set by the configured patterns; demo screenshot was manually checked for synthetic-only data. |
| Native UI | New identity/colors verified; both slider minimums/maximums exercised; prior layout/audio preferences restored after testing. |
| Live read-only check | Local Codex/Claude, SSH source, Grok cache and Codex cloud-list availability checked. Claude cache staleness remains visible rather than presented as real-time data. |
| CI | macOS test/audit/universal-build workflow prepared with pinned upstream actions. Remote CI has not been run before repository publication. |

## Outstanding for a public binary release

- Supply a valid Developer ID Application identity and a configured notarytool Keychain profile; neither was available on the validation machine. No notarization submission was made.
- Run the signed workflow, staple, and pass Gatekeeper with quarantine intact on a clean supported machine.
- Runtime on Intel/macOS 14, physical-notch/multiple-display coverage and actual HomePod output need the corresponding hardware. The Intel slice was compiled, not runtime-tested here.
- Recheck provider cache compatibility and real completion/read events for the versions used at release time. Parser tests and a cloud-list query do not prove a paid cloud task's full lifecycle.

The **source repository is prepared for publication**. The included **preview ZIP is for local evaluation**, not a signed/notarized public app release. See [RELEASING.md](RELEASING.md).
