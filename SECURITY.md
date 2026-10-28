# Security reports

Do not attach agent logs, account caches, authentication files, private keys, or real project screenshots to a public issue.

For a security-sensitive report, use the repository host's private vulnerability reporting feature when enabled. If it is unavailable, open a non-sensitive issue requesting a private contact channel without including exploit details or personal data.

Tern is a local companion with read access to user-authorized agent session data. Its shell commands must use validated hosts and safely quoted arguments; monitoring commands must remain read-only. A user-clicked resume action is distinct from monitoring. Source-app cache data is untrusted input and must never be executed as instructions.

Before distribution, use Developer ID signing and Apple's notarization flow. Never ask users to disable Gatekeeper or give Tern unexpected system permissions to work around a failed build.
