import Foundation

public actor SessionMonitor {
    private struct Cursor {
        var offset: UInt64 = 0
        var inode: UInt64 = 0
        var lines = LineBuffer()
        var parser: TranscriptParser
    }
    private var cursors: [String: Cursor] = [:]
    private var files: [(URL, Agent)] = []
    private var lastDiscovery = Date.distantPast
    private let home: URL
    private let environment: [String: String]
    private let remote: RemoteMonitor
    private let claudeRemote = ClaudeRemoteCacheReader()
    private var grokCache: [String: (Date, [String: Any])] = [:]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.home = home; self.environment = environment
        let codexHome = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        remote = RemoteMonitor(home: home, codexHome: codexHome, enabled: home == FileManager.default.homeDirectoryForCurrentUser)
    }

    public func poll(waitForRemote: Bool = false) async -> ([Session], [String: String]) {
        let fm = FileManager.default
        let codex = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        let claude = environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
        let roots: [(URL, Agent)] = [(codex.appendingPathComponent("sessions"), .codex), (claude.appendingPathComponent("projects"), .claude)]
        var health: [String: String] = [:]
        if Date().timeIntervalSince(lastDiscovery) > 15 {
            var found: [(URL, Agent, Date)] = []
            for (root, agent) in roots {
                guard let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
                while let url = walker.nextObject() as? URL {
                    guard url.pathExtension == "jsonl", !url.path.contains("/subagents/") else { continue }
                    let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    if date > Date().addingTimeInterval(-7 * 86400) { found.append((url, agent, date)) }
                }
            }
            files = [Agent.codex, Agent.claude].flatMap { agent in found.filter { $0.1 == agent }.sorted { $0.2 > $1.2 }.prefix(100).map { ($0.0, $0.1) } }
            let paths = Set(files.map { $0.0.path }); cursors = cursors.filter { paths.contains($0.key) }
            lastDiscovery = .now
        }
        for (root, agent) in roots { health[agent.rawValue] = fm.isReadableFile(atPath: root.path) ? "正在监听本地会话" : "未找到会话目录" }
        var sessions: [Session] = []
        for (url, agent) in files {
            do {
                let attributes = try fm.attributesOfItem(atPath: url.path)
                let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
                let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
                var cursor = cursors[url.path] ?? Cursor(parser: TranscriptParser(agent: agent, fallbackID: url.deletingPathExtension().lastPathComponent, path: url.path))
                if cursor.offset > size || (cursor.inode != 0 && cursor.inode != inode) {
                    cursor = Cursor(parser: TranscriptParser(agent: agent, fallbackID: url.deletingPathExtension().lastPathComponent, path: url.path))
                }
                cursor.inode = inode
                if cursor.offset < size {
                    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
                    if cursor.offset == 0 && size > 4 * 1024 * 1024 {
                        // Recover session metadata from the head, then replay a bounded recent tail.
                        let head = try handle.read(upToCount: 64 * 1024) ?? Data()
                        var headLines = LineBuffer()
                        for line in headLines.append(head) { cursor.parser.consume(line) }
                        let start = size - 4 * 1024 * 1024
                        try handle.seek(toOffset: start)
                        let tail = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
                        if let newline = tail.firstIndex(of: 10) {
                            for line in cursor.lines.append(Data(tail[tail.index(after: newline)...])) { cursor.parser.consume(line) }
                        }
                        cursor.offset = start + UInt64(tail.count)
                    } else {
                        try handle.seek(toOffset: cursor.offset)
                        let data = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
                        for line in cursor.lines.append(data) { cursor.parser.consume(line) }
                        cursor.offset += UInt64(data.count)
                    }
                }
                cursors[url.path] = cursor
                if cursor.parser.session.updatedAt != .distantPast { sessions.append(cursor.parser.session) }
            } catch { health[agent.rawValue] = "读取失败：\(error.localizedDescription)" }
        }
        let grokRoot = home.appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence")
        do {
            let urls = try fm.contentsOfDirectory(at: grokRoot, includingPropertiesForKeys: [.contentModificationDateKey])
            var rosters: [(String, [String: Any])] = []
            var transcripts: [String: [String: Any]] = [:]
            for url in urls where url.pathExtension == "blob" {
                guard let key = GrokSnapshot.decodedKey(url.lastPathComponent), key.hasSuffix(".roster.last-roster") || key.contains(".transcript.replicas.") else { continue }
                let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
                let object: [String: Any]
                if let cached = grokCache[url.path], cached.0 == date { object = cached.1 }
                else {
                    guard let data = try? Data(contentsOf: url), data.count < 32 * 1024 * 1024,
                          let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          (envelope["schemaVersion"] as? Int) == (key.hasSuffix(".roster.last-roster") ? 4 : 1),
                          let value = envelope["value"] as? [String: Any] else { continue }
                    object = value; grokCache[url.path] = (date, object)
                }
                if key.hasSuffix(".roster.last-roster") { rosters.append((key, object)) }
                else { transcripts[key] = object }
            }
            for (key, roster) in rosters {
                let prefix = String(key.dropLast("roster.last-roster".count))
                for row in roster["rows"] as? [[String: Any]] ?? [] {
                    guard let id = row["id"] as? String, row["isRemovedFromSidebar"] as? Bool != true else { continue }
                    sessions.append(GrokSnapshot.parse(id: id, row: row, transcript: transcripts[prefix + "transcript.replicas." + id], sourcePath: grokRoot.path))
                }
            }
            health["grok"] = rosters.isEmpty ? "等待 Grok Bot 写入会话缓存" : "桌面缓存已连接 · 实验性"
        } catch { health["grok"] = "未找到 Grok Bot 桌面缓存" }
        let cloud = claudeRemote.read(home: home)
        sessions += cloud.0; health["claude-remote"] = cloud.1
        let remoteValues = await remote.snapshot(wait: waitForRemote)
        sessions += remoteValues.0; health.merge(remoteValues.1) { _, new in new }
        sessions = SessionReconciler.merge(sessions, localClaudeRoot: claude)
        // Old live records are uncertain, never silently successful.
        sessions = sessions.map { value in
            var s = value
            if s.state == .running && Date().timeIntervalSince(s.updatedAt) > 30 * 60 { s.state = .unknown }
            return s
        }
        var latest: [String: Session] = [:]
        for s in sessions where latest[s.id] == nil || latest[s.id]!.updatedAt < s.updatedAt { latest[s.id] = s }
        return (Array(latest.values).filter { $0.updatedAt > Date().addingTimeInterval(-7 * 86400) }.sorted { $0.updatedAt > $1.updatedAt }, health)
    }
}
