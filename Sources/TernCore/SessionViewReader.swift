import Foundation
import SQLite3

public struct SessionViewSnapshot: Sendable {
    public var receipts: [SessionViewReceipt] = []
    public var codex: CodexReadSnapshot?
    public var health: [String: String] = [:]
    public var claudeDesktopSessionIDs: Set<String> = []
    public var claudeDesktopRoutes: [String: String] = [:]
    public init() {}
}

/// Reads source-app receipt metadata only. It never writes or marks an agent session read.
public actor SessionViewReader {
    private let home: URL
    private let codexHome: URL
    private var remoteReads = RemoteReadTracker()
    private var claudeFocusStamp: Date?
    private var claudeFocus: ClaudeFocus?
    private var foregroundFocus = ForegroundFocusTracker()
    private var codexNavigation: (session: Session, requestedAt: Date)?
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.home = home
        codexHome = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
    }
    public func expectCodexSessionView(_ session: Session, requestedAt: Date = .now) {
        guard session.agent == .codex else { return }
        codexNavigation = (session, requestedAt)
    }
    public func read(pending: [String: PendingDelivery], foregroundApp: String? = nil, sessions: [Session] = [], foregroundLaunchedAt: Date? = nil, now: Date = .now) -> SessionViewSnapshot {
        var snapshot = SessionViewSnapshot()
        let fm = FileManager.default
        let stateFile = codexHome.appendingPathComponent(".codex-global-state.json")
        if let root = object(stateFile),
           let date = try? stateFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           var codex = CodexReadSnapshot.parse(root, modifiedAt: date) {
            codex.publishedTurnByThread = publishedCodexTurns(pending)
            for session in sessions where session.agent == .codex && session.remote?.kind == .ssh {
                if let entry = pending[session.id], session.revision == entry.session.revision,
                   (session.observedAt ?? .distantPast) >= entry.session.updatedAt {
                    codex.publishedTurnBySession[session.id] = session.revision
                }
            }
            codex.sourceAppIsForeground = foregroundApp == "com.openai.codex"
            snapshot.codex = codex
            snapshot.health["codex"] = "读取原应用的会话已读变化"
            let navigationScopes = codexNavigation.map { navigation in
                codex.unreadByScope.filter { codex.scopeMatches($0.key, session: navigation.session) }
            } ?? [:]
            if let navigation = codexNavigation, Date().timeIntervalSince(navigation.requestedAt) >= 1,
               Date().timeIntervalSince(navigation.requestedAt) < 90,
               navigation.requestedAt >= navigation.session.updatedAt,
               codex.sourceAppIsForeground, navigationScopes.count == 1,
               let unread = navigationScopes.values.first,
               let scope = navigationScopes.keys.first,
               let entry = pending[navigation.session.id],
               entry.codexUnreadScopes.isEmpty || entry.codexUnreadScopes.contains(scope),
               !unread.contains(navigation.session.sessionID),
               codex.publishedTurn(for: navigation.session) == navigation.session.revision,
               entry.session.revision == navigation.session.revision {
                // The exact deep link was accepted, its app is frontmost, and its published turn
                // is now reported read by the original app. An open request alone is insufficient.
                snapshot.receipts.append(SessionViewReceipt(sessionKey: navigation.session.id, revision: navigation.session.revision,
                    viewedAt: .now, evidence: .codexOpenedSession))
                codexNavigation = nil
            }
        } else { snapshot.health["codex"] = "查看信号不可用，待检查提示会保留" }

        var desktopRoutes: [String: String] = [:]
        let claudeRoot = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        if let files = fm.enumerator(at: claudeRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            snapshot.health["claude"] = "读取 Claude 桌面会话聚焦时间"
            var focusedSessions: [(String, Date)] = []
            for case let file as URL in files where file.pathExtension == "json" {
                guard let row = object(file), let id = row["cliSessionId"] as? String,
                      let viewedAt = EventDate.parse(row["lastFocusedAt"]) else { continue }
                focusedSessions.append((id, viewedAt))
                snapshot.claudeDesktopSessionIDs.insert(id)
                if let desktopID = row["sessionId"] as? String {
                    snapshot.claudeDesktopRoutes[id] = desktopID; desktopRoutes[id] = desktopID
                    for bridge in row["bridgeSessionIds"] as? [String] ?? [] { desktopRoutes[bridge] = desktopID }
                }
            }
            // Each persisted focus time is an explicit receipt for that session, including
            // bridge aliases. A later app switch must not invalidate an earlier completed view.
            for (cliID, viewedAt) in focusedSessions {
                let desktopID = desktopRoutes[cliID]
                for entry in pending.values where entry.session.agent == .claude {
                    let id = entry.session.sessionID
                    let sameSession = (entry.session.remote == nil && id == cliID) ||
                        ([.cloud, .remoteControl].contains(entry.session.remote?.kind) && id.hasPrefix("session_") && desktopID != nil && desktopRoutes[id] == desktopID)
                    if sameSession && viewedAt >= entry.session.updatedAt {
                        snapshot.receipts.append(SessionViewReceipt(sessionKey: entry.session.id, revision: entry.session.revision,
                            viewedAt: viewedAt, evidence: .claudeFocusedSession))
                    }
                }
            }
        } else { snapshot.health["claude"] = "未找到桌面查看记录；终端会话保持待检查" }

        let log = home.appendingPathComponent("Library/Logs/Claude/main.log")
        let logDate = try? log.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if logDate != claudeFocusStamp {
            claudeFocusStamp = logDate; claudeFocus = nil
            if let handle = try? FileHandle(forReadingFrom: log) {
                defer { try? handle.close() }
                let size = (try? handle.seekToEnd()) ?? 0
                try? handle.seek(toOffset: size > 2 * 1024 * 1024 ? size - 2 * 1024 * 1024 : 0)
                if let data = try? handle.read(upToCount: 2 * 1024 * 1024) {
                    claudeFocus = ClaudeFocus.latest(in: String(decoding: data, as: UTF8.self))
                }
            }
        }
        let isClaude = foregroundApp == "com.anthropic.claudefordesktop"
        let fromThisLaunch = claudeFocus.map { foregroundLaunchedAt == nil || $0.timestamp >= foregroundLaunchedAt!.addingTimeInterval(-1) } ?? false
        let selected = foregroundFocus.confirm(isClaude && fromThisLaunch ? claudeFocus?.sessionID : nil, now: now)
        if let selected {
            for entry in pending.values where entry.session.agent == .claude && now.timeIntervalSince(entry.session.updatedAt) >= 1 {
                let id = entry.session.sessionID
                if selected == id || desktopRoutes[id] == selected {
                    snapshot.receipts.append(SessionViewReceipt(sessionKey: entry.session.id, revision: entry.session.revision,
                        viewedAt: now, evidence: .claudeVisibleSession))
                }
            }
            snapshot.health["claude"] = "已连接原应用的当前会话聚焦记录"
        }

        let grokRoot = home.appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence")
        if let files = try? fm.contentsOfDirectory(at: grokRoot, includingPropertiesForKeys: nil) {
            var found = false
            var selected: [String: String] = [:]
            for file in files where file.pathExtension == "blob" {
                guard let key = GrokSnapshot.decodedKey(file.lastPathComponent), key.hasSuffix(".selection.last-agent"),
                      let envelope = object(file), envelope["schemaVersion"] as? Int == 1, let value = envelope["value"] as? [String: Any],
                      let id = value["agentId"] as? String else { continue }
                selected[String(key.dropLast("selection.last-agent".count))] = id
            }
            for file in files where file.pathExtension == "blob" {
                guard let key = GrokSnapshot.decodedKey(file.lastPathComponent), key.hasSuffix(".roster.last-roster"),
                      let envelope = object(file), envelope["schemaVersion"] as? Int == 4,
                      let value = envelope["value"] as? [String: Any], let rows = value["rows"] as? [[String: Any]] else { continue }
                found = true
                let selectedID = selected[String(key.dropLast("roster.last-roster".count))]
                for row in rows {
                    guard foregroundApp == "com.anysphere.sand", let id = row["id"] as? String, id == selectedID,
                          let entry = pending[Agent.grok.rawValue + ":" + id],
                          row["hasUnread"] as? Bool == false else { continue }
                    let exactMessage = row["lastMessageId"] as? String == entry.session.revision || (row["newestEntryId"] as? String).map { $0 + ":waiting" == entry.session.revision } == true
                    guard let viewedAt = EventDate.parse(row["lastViewedAt"]) ?? (exactMessage ? now : nil) else { continue }
                    let confirmedAt = exactMessage && now.timeIntervalSince(entry.session.updatedAt) >= 1 ? max(viewedAt, now) : viewedAt
                    snapshot.receipts.append(SessionViewReceipt(sessionKey: entry.session.id, revision: entry.session.revision,
                        viewedAt: confirmedAt, evidence: .grokViewedSession))
                }
            }
            snapshot.health["grok"] = found ? "读取 Grok Bot 会话查看时间" : "查看信号不可用，待检查提示会保留"
        } else { snapshot.health["grok"] = "查看信号不可用，待检查提示会保留" }
        snapshot.receipts += remoteReads.observe(sessions: sessions, pending: pending, foregroundApp: foregroundApp)
        return snapshot
    }
    private func publishedCodexTurns(_ pending: [String: PendingDelivery]) -> [String: String] {
        let ids = pending.values.filter { $0.session.agent == .codex && $0.session.remote == nil }.map { $0.session.sessionID }
        guard !ids.isEmpty else { return [:] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(codexHome.appendingPathComponent("state_5.sqlite").path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; return [:]
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 25)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT last_published_turn FROM thread_read_receipts WHERE thread_id = ?", -1, &statement, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(statement) }
        var result: [String: String] = [:]
        for id in ids {
            sqlite3_reset(statement); sqlite3_clear_bindings(statement)
            _ = id.withCString { sqlite3_bind_text(statement, 1, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            if sqlite3_step(statement) == SQLITE_ROW, let value = sqlite3_column_text(statement, 0) {
                result[id] = String(cString: value)
            }
        }
        return result
    }
    private func object(_ file: URL) -> [String: Any]? {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size < 16 * 1024 * 1024, let data = try? Data(contentsOf: file) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
