import Foundation

struct CommandResult { var data: Data; var status: Int32 }
enum ReadOnlyCommand {
    enum Failure: Error { case timeout, oversized }
    /// Output goes to a private temporary file to avoid pipe deadlocks or unbounded memory.
    static func run(_ executable: String, _ arguments: [String], input: Data? = nil, timeout: TimeInterval = 15, limit: Int = 12 * 1024 * 1024) throws -> CommandResult {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tern-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? FileManager.default.removeItem(at: file) }
        let output = try FileHandle(forWritingTo: file); defer { try? output.close() }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        process.standardInput = input == nil ? FileHandle.nullDevice : pipe
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        process.environment = env
        try process.run()
        if let input { DispatchQueue.global(qos: .utility).async { try? pipe.fileHandleForWriting.write(contentsOf: input); try? pipe.fileHandleForWriting.close() } }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if Date() > deadline || size > limit {
                process.terminate()
                // Kill only this owned read-only subprocess if it ignores termination.
                let grace = Date().addingTimeInterval(0.5)
                while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.02) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                throw size > limit ? Failure.oversized : Failure.timeout
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        let size = (try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard size <= limit else { throw Failure.oversized }
        return CommandResult(data: try Data(contentsOf: file), status: process.terminationStatus)
    }
}

public enum RemoteDiscovery {
    public static func sshAliases(codexHome: URL) -> [String] {
        let file = codexHome.appendingPathComponent(".codex-global-state.json")
        guard let data = try? Data(contentsOf: file), let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        return Array(Set((root["codex-managed-remote-connections"] as? [[String: Any]] ?? []).compactMap { row in
            guard let alias = row["alias"] as? String, validAlias(alias) else { return nil }; return alias
        })).sorted()
    }
    public static func hostIDs(codexHome: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: codexHome.appendingPathComponent(".codex-global-state.json")),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for row in root["codex-managed-remote-connections"] as? [[String: Any]] ?? [] {
            if let alias = row["alias"] as? String, validAlias(alias), let host = row["hostId"] as? String { result[alias] = host }
        }
        return result
    }
    public static func validAlias(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$"#, options: .regularExpression) != nil
    }
}

public actor RemoteMonitor {
    private struct HostCache { var files: [String: (version: String, session: Session)] = [:] }
    private var hosts: [String: HostCache] = [:]
    private var sessions: [Session] = []
    private var health: [String: String] = [:]
    private var refresh: Task<Void, Never>?
    private var lastRefresh = Date.distantPast
    private let home: URL
    private let codexHome: URL
    private let enabled: Bool
    public init(home: URL, codexHome: URL, enabled: Bool) { self.home = home; self.codexHome = codexHome; self.enabled = enabled }
    public func snapshot(wait: Bool = false) async -> ([Session], [String: String]) {
        guard enabled else { return ([], [:]) }
        if refresh == nil && Date().timeIntervalSince(lastRefresh) >= 15 {
            lastRefresh = .now
            let old = hosts
            let hostIDs = RemoteDiscovery.hostIDs(codexHome: codexHome)
            let aliases = RemoteDiscovery.sshAliases(codexHome: codexHome)
            let binary = Self.codexExecutable(home: home)
            refresh = Task.detached(priority: .utility) { [weak self] in
                var newHosts: [String: HostCache] = [:], values: [Session] = [], statuses: [String: String] = [:]
                await withTaskGroup(of: (String, HostCache?, [Session], String).self) { group in
                    for alias in aliases.prefix(4) {
                        group.addTask {
                            do {
                                let cache = try Self.readSSH(alias, hostID: hostIDs[alias], previous: old[alias] ?? HostCache())
                                return (alias, cache, cache.files.values.map(\.session), "已连接 · 每 15 秒读取 Codex / Claude · \(cache.files.count) 个会话")
                            } catch {
                                let retained = (old[alias]?.files.values.map(\.session) ?? []).map { s -> Session in var s = s; if s.state == .running { s.state = .unknown }; return s }
                                return (alias, old[alias], retained, "连接失败或读取超时；保留上次结果")
                            }
                        }
                    }
                    if let binary {
                        group.addTask {
                            do {
                                let result = try ReadOnlyCommand.run(binary, ["cloud", "list", "--json", "--limit", "20"])
                                guard result.status == 0 else { throw CocoaError(.fileReadUnknown) }
                                let list = try CodexCloud.parse(result.data)
                                return ("codex-cloud", nil, list.sessions, "云端 API 已连接 · \(list.sessions.count) 个任务" + (list.hasMore ? " · 仅最新 20 项" : ""))
                            } catch { return ("codex-cloud", nil, [], "云端查询失败；检查 Codex CLI 登录状态") }
                        }
                    } else { statuses["codex-cloud"] = "未找到 Codex CLI；云端列表不可用" }
                    for await (key, cache, batch, status) in group {
                        if let cache { newHosts[key] = cache }; values += batch
                        statuses[key == "codex-cloud" ? key : "ssh:" + key] = status
                    }
                }
                if aliases.isEmpty { statuses["ssh"] = "没有 Agent 已配置的 SSH 连接" }
                await self?.finish(hosts: newHosts, sessions: values, health: statuses)
            }
        }
        if wait { await refresh?.value }
        return (sessions, health)
    }
    private static func codexExecutable(home: URL) -> String? {
        let entries = [home.appendingPathComponent(".local/bin/codex").path, "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        for entry in entries where FileManager.default.isExecutableFile(atPath: entry) {
            let resolved = URL(fileURLWithPath: entry).resolvingSymlinksInPath()
            if resolved.pathExtension == "js" {
                let root = resolved.deletingLastPathComponent().deletingLastPathComponent()
                #if arch(arm64)
                let package = "codex-darwin-arm64", triple = "aarch64-apple-darwin"
                #else
                let package = "codex-darwin-x64", triple = "x86_64-apple-darwin"
                #endif
                for candidate in ["node_modules/@openai/\(package)/vendor/\(triple)/bin/codex", "vendor/\(triple)/bin/codex"] {
                    let native = root.appendingPathComponent(candidate).path
                    if FileManager.default.isExecutableFile(atPath: native) { return native }
                }
            }
            return entry
        }
        return nil
    }
    private func finish(hosts: [String: HostCache], sessions: [Session], health: [String: String]) {
        // A failed API read cannot remove a previously observed delivery.
        var values = sessions
        if health["codex-cloud"]?.contains("失败") == true {
            values += self.sessions.filter { $0.agent == .codex && $0.remote?.kind == .cloud }.map { s in var s = s; if s.state == .running { s.state = .unknown }; return s }
        }
        self.hosts = hosts; self.sessions = values; self.health = health; refresh = nil
    }
    private static func readSSH(_ alias: String, hostID: String?, previous: HostCache) throws -> HostCache {
        guard RemoteDiscovery.validAlias(alias), let resource = Bundle.module.url(forResource: "remote-sessions", withExtension: "py") else { throw CocoaError(.fileReadUnknown) }
        let versions = previous.files.mapValues(\.version)
        let encoded = try JSONSerialization.data(withJSONObject: versions).base64EncodedString()
        let script = try String(contentsOf: resource, encoding: .utf8).replacingOccurrences(of: "__PREVIOUS__", with: encoded)
        let result = try ReadOnlyCommand.run("/usr/bin/ssh", ["-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=1", "-o", "StrictHostKeyChecking=yes", "--", alias, "python3", "-"], input: Data(script.utf8), timeout: 12)
        guard result.status == 0, let root = try JSONSerialization.jsonObject(with: result.data) as? [String: Any], let rows = root["files"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        let bridges = root["bridges"] as? [String: String] ?? [:]
        var cache = HostCache()
        for row in rows {
            guard let path = row["path"] as? String, let version = row["version"] as? String,
                  let name = row["agent"] as? String, let agent = Agent(rawValue: name) else { continue }
            if let lines = row["lines"] as? [[String: Any]] {
                var parser = TranscriptParser(agent: agent, fallbackID: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, path: path)
                for line in lines { parser.consume(try JSONSerialization.data(withJSONObject: line)) }
                var session = parser.session
                guard session.updatedAt != .distantPast else { continue }
                session.bridgeSessionID = bridges[session.sessionID]
                session.remote = RemoteOrigin(kind: .ssh, host: alias, hostID: hostID)
                session.source = "SSH · \(alias)"; session.observedAt = .now
                cache.files[path] = (version, session)
            } else if var old = previous.files[path] { old.session.bridgeSessionID = bridges[old.session.sessionID]; old.session.remote?.hostID = hostID; cache.files[path] = old }
        }
        return cache
    }
}

public enum CodexCloud {
    public static func parse(_ data: Data) throws -> (sessions: [Session], hasMore: Bool) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], let tasks = root["tasks"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
        let sessions = tasks.compactMap { row -> Session? in
            guard let id = row["id"] as? String, let updated = EventDate.parse(row["updated_at"]) else { return nil }
            let status = row["status"] as? String ?? ""
            let state: SessionState
            switch status.lowercased() {
            case "ready", "completed", "complete", "done": state = .completed
            case "running", "queued", "pending", "in_progress": state = .running
            case "failed", "error": state = .failed
            case "cancelled", "canceled": state = .interrupted
            default: state = .unknown
            }
            var session = Session(agent: .codex, sessionID: id, title: row["title"] as? String ?? "Codex 云端任务", summary: row["summary"] as? String ?? "云端任务\(state.label)。请打开原任务查看交付。", state: state, updatedAt: updated, revision: "\(updated.timeIntervalSince1970):\(status)", source: "Codex 云端 · CLI")
            let url = (row["url"] as? String).flatMap { URL(string: $0) }
            let valid = url?.scheme == "https" && ["chatgpt.com", "chat.openai.com"].contains(url?.host ?? "")
            session.remote = RemoteOrigin(kind: .cloud, host: "codex-cloud", url: valid ? url?.absoluteString : nil); session.observedAt = .now
            return session
        }
        return (sessions, root["cursor"] as? String != nil)
    }
}
