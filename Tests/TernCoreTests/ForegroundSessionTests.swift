import XCTest
@testable import TernCore

final class ForegroundSessionTests: XCTestCase {
    private func write(_ text: String, to path: URL, modified: Date = .now) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: path.path)
    }
    private func focusLine(_ id: String, date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date) + " [info] [CCD] LocalSessions.setFocusedSession: sessionId=" + id + "\n"
    }
    func testClaudeAlreadyOpenBeforeDeliveryConfirmsCurrentSessionWithoutCacheTransition() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(), log = home.appendingPathComponent("Library/Logs/Claude/main.log")
        try write(focusLine("session_one", date: now.addingTimeInterval(-60)), to: log)
        var s = Session(agent: .claude, sessionID: "session_one", state: .completed, updatedAt: now.addingTimeInterval(-10), revision: "turn")
        s.remote = RemoteOrigin(kind: .remoteControl, host: "org"); s.sourceUnread = true; s.observedAt = now.addingTimeInterval(-1000)
        let pending = [s.id: PendingDelivery(session: s)]
        let reader = SessionViewReader(home: home, environment: [:])
        let first = await reader.read(pending: pending, foregroundApp: "com.anthropic.claudefordesktop", sessions: [s], foregroundLaunchedAt: now.addingTimeInterval(-120), now: now)
        XCTAssertTrue(first.receipts.isEmpty)
        let confirmed = await reader.read(pending: pending, foregroundApp: "com.anthropic.claudefordesktop", sessions: [s], foregroundLaunchedAt: now.addingTimeInterval(-120), now: now.addingTimeInterval(2))
        XCTAssertEqual(confirmed.receipts.map(\.sessionKey), [s.id]); XCTAssertEqual(confirmed.receipts.first?.evidence, .claudeVisibleSession)
        try write(focusLine("session_other", date: now), to: log, modified: now.addingTimeInterval(3))
        let different = await reader.read(pending: pending, foregroundApp: "com.anthropic.claudefordesktop", now: now.addingTimeInterval(4))
        XCTAssertTrue(different.receipts.isEmpty)
    }
    func testClaudeClearedFocusBackgroundOrOldProcessCannotAcknowledge() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(), log = home.appendingPathComponent("Library/Logs/Claude/main.log")
        let line = focusLine("session_one", date: now.addingTimeInterval(-60))
        try write(line, to: log)
        let s = Session(agent: .claude, sessionID: "session_one", state: .completed, updatedAt: now.addingTimeInterval(-10), revision: "turn")
        let reader = SessionViewReader(home: home, environment: [:]), pending = [s.id: PendingDelivery(session: s)]
        for offset in [0.0, 2.0] {
            let background = await reader.read(pending: pending, foregroundApp: "dev.bolin.agent-island", now: now.addingTimeInterval(offset))
            XCTAssertTrue(background.receipts.isEmpty)
            let restarted = await reader.read(pending: pending, foregroundApp: "com.anthropic.claudefordesktop", foregroundLaunchedAt: now, now: now.addingTimeInterval(offset))
            XCTAssertTrue(restarted.receipts.isEmpty)
        }
        XCTAssertNil(ClaudeFocus.latest(in: line + focusLine("null", date: now))?.sessionID)
        XCTAssertNil(ClaudeFocus.latest(in: line + focusLine("unexpected value", date: now))?.sessionID)
    }
    func testNativeCodexRouteKeepsExactRemoteHost() throws {
        var s = Session(agent: .codex, sessionID: "01234567-89ab-cdef-0123-456789abcdef")
        s.remote = RemoteOrigin(kind: .ssh, host: "build-host", hostID: "remote-ssh-discovered:build-host")
        let route = try XCTUnwrap(SessionNavigation.codexURL(s))
        XCTAssertEqual(URLComponents(url: route, resolvingAgainstBaseURL: false)?.queryItems, [URLQueryItem(name: "hostId", value: "remote-ssh-discovered:build-host")])
        s.remote?.hostID = nil; XCTAssertNil(SessionNavigation.codexURL(s))
        s.remote = nil; XCTAssertNotNil(SessionNavigation.codexURL(s))
    }
    func testRemoteUnreadWitnessIsNotConfusedWithLocalSameID() {
        let now = Date(); var s = Session(agent: .codex, sessionID: "same", state: .completed, updatedAt: now.addingTimeInterval(-1), revision: "turn")
        s.remote = RemoteOrigin(kind: .ssh, host: "build-host", hostID: "remote-ssh-discovered:build-host")
        var inbox = DeliveryInbox(); inbox.record(s)
        var wrong = CodexReadSnapshot(unreadByScope: ["account/local:hash": ["same"]], modifiedAt: now, publishedTurnByThread: ["same": "turn"])
        wrong.publishedTurnBySession = [s.id: "turn"]; inbox.observeCodex(wrong)
        XCTAssertTrue(inbox.pending[s.id]!.codexUnreadScopes.isEmpty)
        var correct = CodexReadSnapshot(unreadByScope: ["account/remote-ssh-discovered:build-host:hash": ["same"]], modifiedAt: now)
        correct.publishedTurnBySession = [s.id: "turn"]; inbox.observeCodex(correct)
        correct.unreadByScope = ["account/remote-ssh-discovered:build-host:hash": []]; correct.publishedTurnBySession = [:]
        inbox.observeCodex(correct)
        XCTAssertTrue(inbox.pending.isEmpty)
    }
    func testSmallBarKeepsDefaultIndicatorsAndStableWidth() {
        var config = StatusBarConfiguration.defaults; var idle = config.idle; idle.fixedWidth = 120; config.set(idle, for: .idle)
        XCTAssertEqual(config.idle.widgets, StatusBarProfile.idle.widgets)
        XCTAssertTrue(config.idle.fits); XCTAssertEqual(config.resolvedWidth(for: .idle), 120)
        for style in StatusBarStyle.allCases {
            idle.style = style; config.set(idle, for: .idle); XCTAssertEqual(config.resolvedWidth(for: .idle), 120)
        }
    }
    func testIdleFieldIsAsymmetricAndStaysSoft() {
        let field = (0..<5).flatMap { column in (0..<5).map { row in SignalPattern.cell(column: column, row: row, time: 2.5, providerCount: 0).opacity } }
        XCTAssertGreaterThan(Set(field.map { Int($0 * 1000) }).count, 15)
        XCTAssertTrue(field.allSatisfy { $0 >= 0.1 && $0 <= 0.46 })
        XCTAssertNotEqual(field[2], field[10], "The central row/column must not share a special cross intensity.")
    }
    func testMatrixStreamsUseEveryRunningProviderAndChangeOverTime() {
        let cells = (0..<5).flatMap { col in (0..<5).map { row in SignalPattern.cell(column: col, row: row, time: 2, providerCount: 3) } }
        XCTAssertEqual(Set(cells.map(\.providerIndex)), [0, 1, 2])
        let later = (0..<5).flatMap { col in (0..<5).map { row in SignalPattern.cell(column: col, row: row, time: 2.1, providerCount: 3) } }
        XCTAssertNotEqual(cells, later)
        XCTAssertNotEqual(SignalPattern.cell(column: 2, row: 2, time: 0, providerCount: 0), SignalPattern.cell(column: 2, row: 2, time: 100, providerCount: 0))
        XCTAssertTrue(cells.allSatisfy { $0.opacity >= 0.1 && $0.opacity <= 1 })
    }
}
