import Foundation

public enum Agent: String, Codable, CaseIterable, Sendable {
    case codex, claude, grok
    public var name: String { switch self { case .codex: "Codex"; case .claude: "Claude Code"; case .grok: "Grok Bot" } }
    public var symbol: String { switch self { case .codex: "terminal.fill"; case .claude: "asterisk"; case .grok: "sparkle" } }
}

public enum SessionState: String, Codable, Sendable {
    case running, completed, replied, waiting, failed, interrupted, unknown
    public var label: String {
        switch self {
        case .running: "进行中"; case .completed: "本轮完成"; case .replied: "收到回复"
        case .waiting: "需要你"; case .failed: "出错了"; case .interrupted: "已中断"; case .unknown: "状态待确认"
        }
    }
    public var isDelivery: Bool { self == .completed || self == .replied }
    public var shouldAlert: Bool { isDelivery || self == .waiting || self == .failed }
}

public struct Session: Identifiable, Codable, Equatable, Sendable {
    public var id: String { agent.rawValue + ":" + (remote.map { $0.kind.rawValue + ":" + $0.host + ":" } ?? "") + sessionID }
    public var agent: Agent
    public var sessionID: String
    public var title: String
    public var directory: String
    public var summary: String
    public var state: SessionState
    public var updatedAt: Date
    public var startedAt: Date
    public var revision: String
    public var source: String
    public var sourcePath: String
    public var bridgeSessionID: String?
    public var remote: RemoteOrigin?
    public var sourceUnread: Bool?
    public var observedAt: Date?
    public var isDemo: Bool
    public init(agent: Agent, sessionID: String, title: String = "", directory: String = "", summary: String = "", state: SessionState = .unknown, updatedAt: Date = .now, startedAt: Date = .now, revision: String = "", source: String = "本地会话", sourcePath: String = "", isDemo: Bool = false) {
        self.agent = agent; self.sessionID = sessionID; self.title = title; self.directory = directory
        self.summary = summary; self.state = state; self.updatedAt = updatedAt; self.startedAt = startedAt
        self.revision = revision; self.source = source; self.sourcePath = sourcePath; self.isDemo = isDemo
    }
    public var displayTitle: String { title.isEmpty ? (directory.isEmpty ? agent.name + " 会话" : URL(fileURLWithPath: directory).lastPathComponent) : title }
    public var alertKey: String { id + ":" + state.rawValue + ":" + revision }
    public var excerpt: String { TextSummary.excerpt(summary, limit: 240) }
}

public enum TextSummary {
    public static func excerpt(_ raw: String, limit: Int = 240) -> String {
        let text = raw.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^\s*[#>*]+\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }
    public static func promptTitle(_ text: String) -> String? {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.hasPrefix("<"), !s.hasPrefix("# "), !s.contains("<environment_context>"), !s.contains("<permissions instructions>") else { return nil }
        return excerpt(s, limit: 64)
    }
}

public enum EventDate {
    public static func parse(_ value: Any?) -> Date? {
        if let ms = value as? Double { return Date(timeIntervalSince1970: ms > 10_000_000_000 ? ms / 1000 : ms) }
        guard let s = value as? String else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]; return f.date(from: s)
    }
}
