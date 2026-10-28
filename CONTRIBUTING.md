# Contributing

Use a supported macOS machine and Swift 5.10+ toolchain. Run `swift test`, `./scripts/audit-source.py`, and `./scripts/build.sh` before proposing a change. No third-party Swift packages are required.

Keep window geometry, transcript parsing and view receipts testable in TernCore. Use synthetic fixtures and temporary directories; never commit personal transcripts or run tests against a real account. Test state transitions rather than copies of implementation details.

Keep hover as the only expansion trigger. Do not clear a review entry merely because a jump was requested. Match provider/session/host/revision evidence, and fail visibly/conservatively for unsupported formats. Do not introduce telemetry, agent prompts, token extraction, or automatic approval of source-app actions.

Use the existing swatch theme model, provider identity colors and native AppKit/SwiftUI components. Public screenshots must use demo mode. Describe the problem, resulting behavior, relevant checks and any remaining limits in a pull request.
