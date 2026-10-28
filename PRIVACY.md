# Privacy

Tern has no analytics endpoint, advertising identifier, crash-upload service, Tern account, or remote summary-generation service. Session titles, snippets and review state are processed on your Mac.

## What it reads

While running, Tern probes supported agents' transcript and desktop-cache files, plus source metadata needed to distinguish unread and viewed deliveries. Provider switches control display and new alerts; they are not a filesystem-access boundary. It reads file timestamps to discover recent records and avoid parsing unchanged files. It does not directly extract authentication tokens or cookies.

SSH monitoring uses existing, agent-configured connections. A read-only Python probe runs on those hosts and returns bounded session status/text to your Mac. Codex cloud listing is performed by the already-installed, already-authenticated CLI; ordinary provider authentication and network behavior remain governed by that tool. Tern does not submit new agent tasks.

Clicking a session opens its original app. When only an SSH CLI route exists, Tern creates a private local resume script and opens it in Terminal. The script restores the selected session without a new prompt.

## What it stores

- Preferences and the pending/acknowledged delivery inbox in the app's UserDefaults domain. Pending entries include a bounded source reply snapshot.
- Imported sounds and generated resume scripts in `~/Library/Application Support/Tern`.
- Short-lived synthesized speech files in the system temporary directory.

The legacy bundle identifier is retained for upgrade compatibility. Existing selected sounds may still refer to the prototype's Application Support folder.

## Notifications and outputs

If enabled, titles and summaries may appear in macOS notifications or be spoken through your selected output, including HomePod/AirPlay. Mute and notification settings are separate from keeping a review record. System permissions and Focus mode can affect delivery.

## Control and removal

Disable a source to stop showing new observations from it. Existing review records remain until confirmed. Quit Tern to stop all monitoring. Removing the app does not delete provider data. To remove Tern's own saved data, quit it and remove its preferences and Application Support folder; uninstall instructions should never delete Codex, Claude, Grok, SSH or Keychain data.

Diagnostics and screenshots can reveal sensitive project information. Do not post raw source logs, caches, credentials or real-session screenshots publicly. The `--inspect` diagnostic prints counts and health, but health may include configured host aliases: review it before sharing.

The included privacy manifest declares no tracking/collected data and the required-reason use of app preferences and timestamps for user-authorized monitoring files. This is not an App Store approval or an independent privacy certification.
