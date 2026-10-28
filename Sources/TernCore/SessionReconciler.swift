import Foundation

public enum SessionReconciler {
    /// Only an explicit CLI-to-bridge ID mapping joins two records; titles never identify a task.
    public static func merge(_ sessions: [Session], localClaudeRoot: URL? = nil) -> [Session] {
        var bridges: [String: String] = [:]
        if let root = localClaudeRoot, let files = try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("sessions"), includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files where file.pathExtension == "json" {
                guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 65536,
                      let data = try? Data(contentsOf: file), let row = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      let id = row["sessionId"] as? String, let bridge = row["bridgeSessionId"] as? String else { continue }
                bridges[id] = bridge
            }
        }
        let cloud = sessions.filter { $0.agent == .claude && [.cloud, .remoteControl].contains($0.remote?.kind) }
        var replaced = Set<String>(), output: [Session] = []
        for original in sessions where !cloud.contains(where: { $0.id == original.id }) {
            var session = original
            if session.agent == .claude {
                let bridge = session.bridgeSessionID ?? (session.remote == nil ? bridges[session.sessionID] : nil)
                let matches = cloud.filter { $0.sessionID == bridge }
                if matches.count == 1, let remote = matches.first {
                    // Logs supply current status and actual delivery text; cloud supplies route/unread metadata.
                    if remote.updatedAt > session.updatedAt {
                        session.state = remote.state; session.updatedAt = remote.updatedAt; session.revision = remote.revision
                        if session.summary.isEmpty { session.summary = remote.summary }
                        else { session.summary = "执行主机最近回复：\n" + session.summary }
                    }
                    session.sessionID = remote.sessionID; session.remote = remote.remote
                    session.title = remote.title; session.sourceUnread = remote.sourceUnread
                    session.observedAt = remote.observedAt
                    session.source = "Remote Control · " + (original.remote?.host ?? "本机")
                    replaced.insert(remote.id)
                }
            }
            output.append(session)
        }
        output += cloud.filter { !replaced.contains($0.id) }
        return output
    }
}

public enum SessionNavigation {
    public static func codexURL(_ session: Session) -> URL? {
        guard session.agent == .codex, UUID(uuidString: session.sessionID) != nil else { return nil }
        var route = URLComponents(); route.scheme = "codex"; route.host = "threads"; route.path = "/" + session.sessionID
        if let remote = session.remote {
            guard remote.kind == .ssh, let host = remote.hostID, !host.isEmpty else { return nil }
            route.queryItems = [URLQueryItem(name: "hostId", value: host)]
        }
        return route.url
    }
    public static func resumeCommand(_ session: Session) -> String? {
        guard let remote = session.remote, remote.kind == .ssh, RemoteDiscovery.validAlias(remote.host),
              [.codex, .claude].contains(session.agent) else { return nil }
        let quote: (String) -> String = { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let inner = (session.directory.isEmpty ? "" : "cd -- \(quote(session.directory)) && ") +
            (session.agent == .claude ? "claude --resume " : "codex resume ") + quote(session.sessionID)
        return "ssh -t -- \(quote(remote.host)) \(quote(inner))"
    }
}
