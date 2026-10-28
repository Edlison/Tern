import Foundation

public struct RemoteOrigin: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case ssh, cloud, remoteControl }
    public var kind: Kind
    public var host: String
    public var hostID: String?
    public var url: String?
    public init(kind: Kind, host: String, url: String? = nil, hostID: String? = nil) { self.kind = kind; self.host = host; self.url = url; self.hostID = hostID }
}

public enum ClaudeRemoteCache {
    public struct Snapshot { public var sessions: [Session]; public var observedAt: Date; public var hasMore: Bool }
    public static func parse(_ root: [String: Any], sourcePath: String) -> Snapshot? {
        guard let client = root["clientState"] as? [String: Any], let queries = client["queries"] as? [[String: Any]] else { return nil }
        var sessions: [Session] = [], observed = Date.distantPast, hasMore = false, found = false
        for query in queries {
            guard let key = query["queryKey"] as? [Any], key.first as? String == "sessions_api_list_sessions",
                  let filters = key.dropFirst().first as? [String: Any], let statuses = filters["statuses"] as? [String],
                  statuses.contains("active"), !statuses.contains("archived"),
                  let state = query["state"] as? [String: Any], let data = state["data"] as? [String: Any],
                  let pages = data["pages"] as? [[String: Any]], let fetched = EventDate.parse(state["dataUpdatedAt"]) else { continue }
            found = true; observed = max(observed, fetched)
            let org = filters["orgUuid"] as? String ?? "default"
            for page in pages {
                hasMore = page["has_more"] as? Bool ?? false
                for row in page["data"] as? [[String: Any]] ?? [] {
                    guard let id = row["id"] as? String, id.range(of: #"^session_[A-Za-z0-9]+$"#, options: .regularExpression) != nil,
                          let updated = EventDate.parse(row["updated_at"]) else { continue }
                    let summary = row["post_turn_summary"] as? [String: Any] ?? [:]
                    let bucket = row["status_bucket"] as? String ?? ""
                    let worker = row["worker_status"] as? String ?? ""
                    let status = row["session_status"] as? String ?? ""
                    let category = summary["status_category"] as? String ?? ""
                    let result: SessionState
                    if ["running", "working", "executing", "busy"].contains(worker) || ["running", "working"].contains(bucket) || status == "running" { result = .running }
                    else if bucket == "blocked" || category == "need_input" { result = .waiting }
                    else if ["completed", "review_ready"].contains(bucket) || category == "completed" { result = .completed }
                    else if ["failed", "error"].contains(bucket) { result = .failed }
                    else { result = .unknown }
                    let bridge = row["environment_kind"] as? String == "bridge"
                    let body = ["summary", "text", "description"].compactMap { summary[$0] as? String }.first ?? "远程会话\(result.label)。缓存未提供完整交付正文，请打开原会话查看。"
                    var session = Session(agent: .claude, sessionID: id, title: row["title"] as? String ?? "Claude 远程会话",
                        summary: String(body.prefix(16_000)), state: result, updatedAt: updated,
                        startedAt: EventDate.parse(row["created_at"]) ?? updated,
                        revision: "\(updated.timeIntervalSince1970):\(result.rawValue)",
                        source: bridge ? "Remote Control · 桌面缓存" : "Claude 云端 · 桌面缓存", sourcePath: sourcePath)
                    session.remote = RemoteOrigin(kind: bridge ? .remoteControl : .cloud, host: org, url: "https://claude.ai/code/\(id)")
                    session.sourceUnread = row["unread"] as? Bool; session.observedAt = fetched
                    sessions.append(session)
                }
            }
        }
        return found ? Snapshot(sessions: sessions, observedAt: observed, hasMore: hasMore) : nil
    }
}

public final class ClaudeRemoteCacheReader {
    private var stamp: String = ""
    private var cached: ClaudeRemoteCache.Snapshot?
    public init() {}
    public func read(home: URL) -> ([Session], String) {
        let root = home.appendingPathComponent("Library/Application Support/Claude/IndexedDB/https_claude.ai_0.indexeddb.blob")
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]) else { return ([], "未找到 Claude 远程缓存；需在 Claude 中打开 Code") }
        let files = walker.compactMap { $0 as? URL }.compactMap { url -> (URL, Date, Int)? in
            guard let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]), v.isRegularFile == true,
                  let size = v.fileSize, size > 0, size <= 32 * 1024 * 1024 else { return nil }
            return (url, v.contentModificationDate ?? .distantPast, size)
        }.sorted { $0.1 > $1.1 }.prefix(16)
        let nextStamp = files.map { "\($0.0.path):\($0.1.timeIntervalSince1970):\($0.2)" }.joined(separator: "|")
        if nextStamp != stamp {
            stamp = nextStamp; cached = nil
            for (file, _, _) in files {
                guard let bytes = try? Data(contentsOf: file), let object = try? BrowserCacheDecoder.decode(bytes),
                      let snapshot = ClaudeRemoteCache.parse(object, sourcePath: file.path) else { continue }
                if cached == nil || snapshot.observedAt > cached!.observedAt { cached = snapshot }
            }
        }
        guard let cached else { return ([], "远程缓存不可读或尚未载入会话列表") }
        let minutes = max(0, Int(Date().timeIntervalSince(cached.observedAt) / 60))
        let status = minutes > 2 ? "缓存已 \(minutes) 分钟未更新；请打开 Claude Code 刷新" : "远程缓存已连接 · \(cached.sessions.count) 个会话"
        return (cached.sessions, status + (cached.hasMore ? " · 仅覆盖已载入分页" : ""))
    }
}

/// A source cache must first report this delivery unread, then report it read in a newer fetch.
/// Source app activation alone cannot acknowledge a delivery.
public struct RemoteReadTracker {
    private var unread: [String: (revision: String, fetched: Date)] = [:]
    public init() {}
    public mutating func observe(sessions: [Session], pending: [String: PendingDelivery], foregroundApp: String?) -> [SessionViewReceipt] {
        var receipts: [SessionViewReceipt] = []
        for session in sessions where session.agent == .claude && [.cloud, .remoteControl].contains(session.remote?.kind) {
            guard let entry = pending[session.id], let fetched = session.observedAt,
                  fetched >= entry.session.updatedAt, session.revision == entry.session.revision else { unread.removeValue(forKey: session.id); continue }
            if session.sourceUnread == true { unread[session.id] = (session.revision, fetched) }
            else if session.sourceUnread == false, let previous = unread.removeValue(forKey: session.id),
                    previous.revision == entry.session.revision, fetched > previous.fetched,
                    foregroundApp == "com.anthropic.claudefordesktop" {
                receipts.append(SessionViewReceipt(sessionKey: session.id, revision: entry.session.revision, viewedAt: fetched, evidence: .claudeRemoteReadTransition))
            }
        }
        unread = unread.filter { pending[$0.key] != nil }
        return receipts
    }
}
