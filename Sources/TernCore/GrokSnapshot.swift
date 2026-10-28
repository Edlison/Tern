import Foundation

public enum GrokSnapshot {
    public static func decodedKey(_ filename: String) -> String? {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
        var accumulator: UInt32 = 0; var bits = 0; var bytes: [UInt8] = []
        for c in filename.replacingOccurrences(of: ".blob", with: "").lowercased() {
            guard let value = alphabet.firstIndex(of: c) else { return nil }
            accumulator = (accumulator << 5) | UInt32(value); bits += 5
            if bits >= 8 { bits -= 8; bytes.append(UInt8((accumulator >> bits) & 255)) }
            accumulator &= (1 << bits) - 1
        }
        return String(bytes: bytes, encoding: .utf8)
    }
    public static func parse(id: String, row: [String: Any], transcript: [String: Any]?, sourcePath: String) -> Session {
        let updated = EventDate.parse(row["lastActivityAt"]) ?? .distantPast
        let preview = row["lastEntry"] as? [String: Any] ?? [:]
        let title = [row["title"] as? String, row["name"] as? String].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "Grok Bot"
        var session = Session(agent: .grok, sessionID: id,
            title: title,
            directory: "", summary: preview["text"] as? String ?? "",
            updatedAt: updated, source: "桌面缓存 · 实验性", sourcePath: sourcePath)
        let entries = transcript?["entries"] as? [[String: Any]] ?? []
        // Only actual conversational messages count. Tool/automation events do not.
        if let message = entries.last(where: {
            if $0["kind"] as? String == "send-message" { return ($0["message"] as? [String: Any])?["type"] as? String == "text" }
            return $0["kind"] as? String == "message" && ["user", "assistant"].contains($0["role"] as? String ?? "")
        }) {
            session.updatedAt = EventDate.parse(message["timestampMs"]) ?? updated
            session.revision = message["id"] as? String ?? "\(session.updatedAt.timeIntervalSince1970)"
            // Grok Bot delivers most user-visible replies through send-message entries.
            let delivered = message["kind"] as? String == "send-message"
            let role = delivered ? "assistant" : message["role"] as? String
            let streaming = message["isStreaming"] as? Bool == true
            if role == "assistant" {
                let text = delivered ? (message["message"] as? [String: Any])?["content"] as? String : message["content"] as? String
                session.summary = String((text ?? session.summary).prefix(16_000))
                // A persisted reply is weaker evidence than a harness task-complete event.
                session.state = streaming ? .running : .replied
            } else { session.state = .running }
        }
        session.sourceUnread = row["hasUnread"] as? Bool
        // The roster can receive a remote reply before this Bot's transcript has been opened.
        // Require an explicit unread message identifier and typed message preview, never arbitrary text.
        let newerRoster = updated > session.updatedAt || session.revision.isEmpty
        if newerRoster {
            let typed = preview["sessionPreview"] as? [String: Any] ?? [:]
            if row["hasUnread"] as? Bool == true, preview["kind"] as? String == "text",
               typed["kind"] as? String == "message_text", let messageID = row["lastMessageId"] as? String, !messageID.isEmpty {
                session.state = .replied; session.revision = messageID; session.updatedAt = updated
                session.summary = String(((typed["text"] as? String) ?? (preview["text"] as? String) ?? "").prefix(16_000))
            } else if !session.revision.isEmpty && updated > session.updatedAt {
                // A newer activity event without reply evidence invalidates a stale transcript state.
                session.state = .unknown; session.updatedAt = updated; session.revision = ""
            }
        }
        if row["isRunning"] as? Bool == true || row["isRunningTurn"] as? Bool == true {
            session.state = .running; session.updatedAt = max(updated, session.updatedAt)
        }
        if let waiting = row["awaitingUserResponse"], !(waiting is NSNull), (waiting as? Bool) != false {
            session.state = .waiting
            session.revision = (row["newestEntryId"] as? String ?? session.revision) + ":waiting"
        }
        return session
    }
}

public struct AlertLedger {
    private var seen: Set<String>
    public init(seen: Set<String> = []) { self.seen = seen }
    public var keys: Set<String> { seen }
    public mutating func accept(_ session: Session, liveSince: Date, recoverUnread: Bool = false) -> Bool {
        guard session.state.shouldAlert, !session.revision.isEmpty else { return false }
        let fresh = seen.insert(session.alertKey).inserted
        return fresh && (session.updatedAt >= liveSince || (recoverUnread && session.sourceUnread == true))
    }
}
