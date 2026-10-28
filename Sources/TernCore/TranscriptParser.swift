import Foundation

/// Only explicit terminal events finish a turn. Silence and tool results never do.
public struct TranscriptParser {
    public var session: Session
    public init(agent: Agent, fallbackID: String, path: String = "") {
        session = Session(agent: agent, sessionID: fallbackID, updatedAt: .distantPast, startedAt: .distantPast, sourcePath: path)
    }
    public mutating func consume(_ data: Data) {
        guard let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        if session.agent == .codex { codex(row) } else if session.agent == .claude { claude(row) }
    }
    private mutating func transition(_ state: SessionState, at date: Date, revision: String) {
        if state == .running && session.state != .running { session.startedAt = date }
        session.state = state; session.updatedAt = date; session.revision = revision
    }
    private mutating func codex(_ row: [String: Any]) {
        let kind = row["type"] as? String ?? ""
        let p = row["payload"] as? [String: Any] ?? [:]
        let time = EventDate.parse(row["timestamp"]) ?? session.updatedAt
        let event = p["type"] as? String ?? ""
        if kind == "session_meta" {
            session.sessionID = p["id"] as? String ?? p["session_id"] as? String ?? session.sessionID
            session.directory = p["cwd"] as? String ?? ""
        }
        if kind == "turn_context", let cwd = p["cwd"] as? String { session.directory = cwd }
        if kind == "response_item", event == "message" {
            let body = Self.content(p["content"])
            if p["role"] as? String == "user", let title = TextSummary.promptTitle(body) { session.title = title }
            if p["role"] as? String == "assistant", !body.isEmpty {
                session.summary = String(body.prefix(16_000)); session.updatedAt = time
            }
        }
        guard kind == "event_msg" else { return }
        let revision = p["turn_id"] as? String ?? row["timestamp"] as? String ?? ""
        switch event {
        case "task_started", "turn_started": transition(.running, at: time, revision: revision)
        case "task_complete", "task_completed":
            if let text = p["last_agent_message"] as? String, !text.isEmpty { session.summary = String(text.prefix(16_000)) }
            transition(.completed, at: time, revision: revision)
        case "turn_aborted", "task_aborted": transition(.interrupted, at: time, revision: revision)
        case "task_failed", "turn_failed": transition(.failed, at: time, revision: revision)
        case "user_message":
            if let text = p["message"] as? String, let title = TextSummary.promptTitle(text) { session.title = title }
        case "agent_message":
            if let text = p["message"] as? String { session.summary = String(text.prefix(16_000)); session.updatedAt = time }
        case "item_completed":
            let item = p["item"] as? [String: Any] ?? [:]
            if (item["type"] as? String) == "AgentMessage" || (item["type"] as? String) == "agentMessage" {
                if let text = item["text"] as? String { session.summary = String(text.prefix(16_000)) }
            }
            if session.state == .running { session.updatedAt = time }
        default: break
        }
    }
    private mutating func claude(_ row: [String: Any]) {
        guard row["isSidechain"] as? Bool != true else { return }
        let kind = row["type"] as? String ?? ""
        if let id = row["sessionId"] as? String { session.sessionID = id }
        if let cwd = row["cwd"] as? String { session.directory = cwd }
        let time = EventDate.parse(row["timestamp"]) ?? session.updatedAt
        let msg = row["message"] as? [String: Any] ?? [:]
        let revision = msg["id"] as? String ?? row["uuid"] as? String ?? "\(time.timeIntervalSince1970)"
        if kind == "custom-title", let title = row["customTitle"] as? String { session.title = TextSummary.excerpt(title, limit: 64) }
        if kind == "last-prompt", let text = row["lastPrompt"] as? String, let title = TextSummary.promptTitle(text) { session.title = title }
        if kind == "user" {
            let blocks = msg["content"] as? [[String: Any]] ?? []
            guard !blocks.contains(where: { $0["type"] as? String == "tool_result" }) else { return }
            let text = Self.content(msg["content"])
            if let title = TextSummary.promptTitle(text) { session.title = title; transition(.running, at: time, revision: revision) }
        }
        if kind == "assistant" {
            let body = Self.content(msg["content"])
            if !body.isEmpty { session.summary = String(body.prefix(16_000)) }
            switch msg["stop_reason"] as? String {
            case "end_turn", "stop_sequence": transition(.completed, at: time, revision: revision)
            case "max_tokens", "refusal": transition(.failed, at: time, revision: revision)
            default: transition(.running, at: time, revision: revision)
            }
        }
        if kind == "system", row["subtype"] as? String == "turn_duration", session.state == .running {
            transition(.completed, at: time, revision: revision)
        }
    }
    public static func content(_ value: Any?) -> String {
        if let text = value as? String { return text }
        return (value as? [[String: Any]] ?? []).compactMap { block -> String? in
            guard ["text", "input_text", "output_text"].contains(block["type"] as? String ?? "") else { return nil }
            return block["text"] as? String
        }.joined(separator: "\n")
    }
}

/// Holds incomplete UTF-8 and JSON lines until the writer has appended a newline.
public struct LineBuffer {
    private var pending = Data()
    private var dropping = false
    public init() {}
    public mutating func append(_ data: Data) -> [Data] {
        pending.append(data)
        var lines: [Data] = []
        while let end = pending.firstIndex(of: 10) {
            let line = Data(pending[..<end])
            if !dropping && line.count <= 8 * 1024 * 1024 { lines.append(line) }
            dropping = false; pending.removeSubrange(...end)
        }
        if pending.count > 8 * 1024 * 1024 { pending.removeAll(keepingCapacity: false); dropping = true }
        return lines
    }
}
