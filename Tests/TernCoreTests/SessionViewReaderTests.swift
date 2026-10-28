import XCTest
import SQLite3
@testable import TernCore

final class SessionViewReaderTests: XCTestCase {
    private func write(_ object: [String: Any], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }
    func testClaudeFocusMetadataMatchesCLISessionAndIsReadOnly() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let path = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions/account/local.json")
        let date = Date().addingTimeInterval(-2)
        try write(["sessionId": "local-one", "cliSessionId": "correct", "lastFocusedAt": date.timeIntervalSince1970 * 1000], to: path)
        let original = try Data(contentsOf: path)
        let session = Session(agent: .claude, sessionID: "correct", state: .completed, updatedAt: date.addingTimeInterval(-1), revision: "turn")
        let other = Session(agent: .claude, sessionID: "other", state: .completed, revision: "other-turn")
        let result = await SessionViewReader(home: home, environment: [:]).read(pending: [session.id: PendingDelivery(session: session), other.id: PendingDelivery(session: other)], foregroundApp: "com.anthropic.claudefordesktop")
        XCTAssertEqual(result.receipts.map(\.sessionKey), [session.id])
        XCTAssertEqual(result.receipts.first?.evidence, .claudeFocusedSession)
        XCTAssertEqual(try Data(contentsOf: path), original)
        let reader = SessionViewReader(home: home, environment: [:])
        let background = await reader.read(pending: [session.id: PendingDelivery(session: session)], foregroundApp: "dev.bolin.agent-island")
        XCTAssertEqual(background.receipts.map(\.sessionKey), [session.id], "A recorded view remains valid after switching apps.")
        try write(["sessionId": "local-other", "cliSessionId": "other", "lastFocusedAt": Date().timeIntervalSince1970 * 1000], to: path.deletingLastPathComponent().appendingPathComponent("other.json"))
        let different = await reader.read(pending: [session.id: PendingDelivery(session: session)], foregroundApp: "com.anthropic.claudefordesktop")
        XCTAssertEqual(different.receipts.map(\.sessionKey), [session.id], "A later session cannot erase an already-recorded view.")
    }
    func testCodexReaderBindsReadStateToPublishedTurn() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent(".codex")
        try write(["electron-thread-read-state-v1": ["version": 1, "unreadByIdentity": ["account": ["local:root": ["one"]]]]], to: root.appendingPathComponent(".codex-global-state.json"))
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("state_5.sqlite").path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE thread_read_receipts(thread_id TEXT PRIMARY KEY,last_published_turn TEXT); INSERT INTO thread_read_receipts VALUES('one','turn1');", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let session = Session(agent: .codex, sessionID: "one", state: .completed, updatedAt: Date().addingTimeInterval(-5), revision: "turn1")
        let reader = SessionViewReader(home: home, environment: [:])
        let pending = [session.id: PendingDelivery(session: session)]
        let snapshot = await reader.read(pending: pending)
        XCTAssertEqual(snapshot.codex?.unreadByScope, ["account/local:root": Set(["one"])])
        XCTAssertEqual(snapshot.codex?.publishedTurnByThread, ["one": "turn1"])
        await reader.expectCodexSessionView(session, requestedAt: Date().addingTimeInterval(-2))
        let unread = await reader.read(pending: pending, foregroundApp: "com.openai.codex")
        XCTAssertTrue(unread.receipts.isEmpty)
        try write(["electron-thread-read-state-v1": ["version": 1, "unreadByIdentity": ["account": ["local:root": [String]()]]]], to: root.appendingPathComponent(".codex-global-state.json"))
        let wrongApp = await reader.read(pending: pending, foregroundApp: "dev.bolin.agent-island")
        XCTAssertTrue(wrongApp.receipts.isEmpty)
        let opened = await reader.read(pending: pending, foregroundApp: "com.openai.codex")
        XCTAssertEqual(opened.receipts.first?.sessionKey, session.id)
        XCTAssertEqual(opened.receipts.first?.evidence, .codexOpenedSession)

    }
    func testGrokRequiresExplicitViewedTimestampAndUnreadFalse() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        func encode(_ key: String) -> String {
            let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
            var result = "", accumulator = 0, bits = 0
            for byte in key.utf8 {
                accumulator = (accumulator << 8) | Int(byte); bits += 8
                while bits >= 5 { bits -= 5; result.append(alphabet[(accumulator >> bits) & 31]) }
                accumulator &= (1 << bits) - 1
            }
            if bits > 0 { result.append(alphabet[(accumulator << (5 - bits)) & 31]) }
            return result
        }
        let encoded = encode("sand.client.slice.account.test.roster.last-roster")
        let selected = home.appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence/" + encode("sand.client.slice.account.test.selection.last-agent") + ".blob")
        try write(["schemaVersion": 1, "value": ["agentId": "seen"]], to: selected)
        let file = home.appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence/" + encoded + ".blob")
        let date = Date().addingTimeInterval(-1)
        try write(["schemaVersion": 4, "value": ["rows": [
            ["id": "seen", "hasUnread": false, "lastViewedAt": date.timeIntervalSince1970 * 1000],
            ["id": "unread", "hasUnread": true, "lastViewedAt": date.timeIntervalSince1970 * 1000],
            ["id": "unknown", "hasUnread": false]
        ]]], to: file)
        let pending = Dictionary(uniqueKeysWithValues: ["seen", "unread", "unknown"].map { id -> (String, PendingDelivery) in
            let session = Session(agent: .grok, sessionID: id, state: .replied, revision: "reply")
            return (session.id, PendingDelivery(session: session))
        })
        let snapshot = await SessionViewReader(home: home, environment: [:]).read(pending: pending, foregroundApp: "com.anysphere.sand")
        XCTAssertEqual(snapshot.receipts.map(\.sessionKey), ["grok:seen"])
        XCTAssertEqual(snapshot.receipts.first?.evidence, .grokViewedSession)
    }
}
