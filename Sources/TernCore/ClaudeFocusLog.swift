import Foundation

public struct ClaudeFocus: Equatable, Sendable {
    public var sessionID: String?
    public var timestamp: Date
    public static func latest(in text: String, timeZone: TimeZone = .current) -> Self? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone; formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let marker = "[CCD] LocalSessions.setFocusedSession: sessionId="
        for line in text.split(separator: "\n").reversed() {
            guard let range = line.range(of: marker), let date = formatter.date(from: String(line.prefix(19))) else { continue }
            let id = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            // A null/unknown selection invalidates the previous session; don't search past it.
            let valid = id.range(of: #"^(session_|local_)[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil
            return Self(sessionID: valid ? id : nil, timestamp: date)
        }
        return nil
    }
}

struct ForegroundFocusTracker {
    private var focused: (id: String, since: Date)?
    mutating func confirm(_ id: String?, now: Date) -> String? {
        guard let id else { focused = nil; return nil }
        if focused?.id != id { focused = (id, now); return nil }
        return now.timeIntervalSince(focused!.since) >= 1 ? id : nil
    }
}
