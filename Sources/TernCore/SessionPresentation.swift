import Foundation

public enum SessionPresentation {
    /// Keep actionable sessions at the top; historical delivery views stay chronological.
    public static func ordered(_ sessions: [Session], prioritizeActivity: Bool) -> [Session] {
        func priority(_ s: Session) -> Int {
            guard prioritizeActivity else { return 0 }
            switch s.state { case .waiting, .failed: return 0; case .running: return 1; default: return 2 }
        }
        return sessions.sorted {
            let a = priority($0), b = priority($1)
            if a != b { return a < b }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }
    public static func projectName(_ session: Session) -> String {
        guard !session.directory.isEmpty else { return session.agent.name }
        return URL(fileURLWithPath: session.directory).lastPathComponent
    }
    public static func relativeTime(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}
