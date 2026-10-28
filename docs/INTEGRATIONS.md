# Integration contracts

Tern reads source evidence; it does not send agent prompts, change source read states, or infer success from elapsed time. Cache formats are private integration details and can change with provider upgrades.

## Local transcripts

- Codex: `CODEX_HOME/sessions`, default `~/.codex/sessions`. `task_started` starts a turn; `task_complete` / `task_completed` finish it. Aborts and failures remain distinct. Assistant/tool items alone do not complete a turn.
- Claude Code: `CLAUDE_CONFIG_DIR/projects`, default `~/.claude/projects`. Explicit assistant stop reasons and supported turn-duration events finish a turn. Sidechains and tool results are excluded.
- File discovery occurs every 15 seconds, limited to seven days and 100 files per provider. Reads are incremental. Large initial logs replay a metadata head and a bounded 4 MiB tail. Partial UTF-8/JSON lines wait for a newline.
- A running record with no activity for 30 minutes becomes unknown, never completed.

## SSH

Only aliases already stored in Codex's managed remote connections are discovered; arbitrary SSH config hosts are not scanned. Up to four hosts are probed independently using BatchMode, strict known-host checking, a connection timeout, and a 12-second command deadline. Python 3 must already exist remotely. Nothing is installed on the host.

The bundled Python probe reads bounded transcript tails and returns whitelisted status/text fields, omitting tool output. File versions avoid repeated transcript parsing. Explicit Claude `sessionId` / `bridgeSessionId` mappings reconcile Remote Control entries; titles are never identity evidence.

Codex deep links carry the saved `hostId`. Plain SSH sessions with no desktop route open a locally generated, shell-quoted `.command` file in Terminal to resume the original session. This action happens only on a user click. Such terminal sessions currently lack a reliable automatic viewing receipt.

## Cloud and desktop caches

- Codex cloud uses the installed CLI's existing authentication and `cloud list --json --limit 20`. Tern never calls `cloud exec`, `apply`, or sends a new prompt. Unknown status values remain unknown.
- Claude Desktop's persisted React Query session list is read from its IndexedDB blob store. A bounded Snappy / structured-clone decoder supports the observed JSON-compatible wire formats without executing JavaScript. Unknown formats fail closed. Current cache age and incomplete pagination are shown in source health.
- When an explicit bridge mapping is available, execution logs supply actual reply content. Without it, a cached cloud row may supply only status and title. Cache refresh is controlled by Claude, not Tern.
- Grok Bot currently uses roster schema 4 and transcript schema 1. Only explicit text replies or typed unread message previews count as a reply; ordinary activity and tools do not prove completion. Newer roster activity invalidates stale transcript state. This adapter remains experimental.

## Review confirmation

Inbox entries are persisted by source session identity and delivery revision. Clicking, hovering, opening Tern, muting, hiding components, or disabling a source does not by itself acknowledge a delivery.

- **Codex:** read-state scopes are tied to the account/host and published turn. Witnessed unread state survives restart. A known desktop thread already read before the first poll may be acknowledged only with a matching host, current published revision, sufficiently recent state, and absence from every unread set. Unknown CLI sessions are not treated as read just because they are absent.
- **Claude local / bridged:** persisted `lastFocusedAt` is matched through explicit CLI/Desktop/bridge IDs. A later app switch does not invalidate an earlier positive view. Old focus cannot clear a later delivery; local focus cannot clear an unrelated SSH copy.
- **Claude currently visible:** an explicit current-session focus event from the current application process, with the original app in the foreground and a short stable dwell, handles a session left open before delivery. A null/other session invalidates that evidence.
- **Claude remote fallback:** a newer source-cache fetch reporting the exact delivery read may confirm a previously witnessed unread entry. Stale cache alone cannot prove a view.
- **Grok Bot:** selection, unread flag, viewed time or exact delivered message ID must agree for the original app in the foreground.

These signals are conservative approximations of a source-app view. There is no claim to know whether a person read or understood the result. Unsupported formats and missing receipts retain the review indicator. Historical explicitly unread results can be recovered silently without replaying old audio.

## Compatibility and validation

Primary functional validation uses synthetic fixtures, isolated preferences, temporary JSON/SQLite files, command timeout/output limits, and read-only live checks. Tests do not launch paid agent tasks. The original desktop app UI can remain outside automation access; its integration must not require bypassing a denied UI surface.

Provider references: [Codex CLI](https://learn.chatgpt.com/docs/developer-commands), [Claude Desktop](https://code.claude.com/docs/en/desktop), [Claude Remote Control](https://code.claude.com/docs/en/remote-control), [Grok Bot](https://x.ai/bot).
