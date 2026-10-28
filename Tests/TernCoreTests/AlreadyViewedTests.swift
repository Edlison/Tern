import XCTest
@testable import TernCore

final class AlreadyViewedTests: XCTestCase {
    func testClaudeBridgeReceiptUsesMappedLocalIDAndSurvivesSwitchingAway() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions/account")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date(), viewed = now.addingTimeInterval(-5)
        let row: [String: Any] = ["sessionId": "local_desktop", "cliSessionId": "cli", "bridgeSessionIds": ["session_bridge"], "lastFocusedAt": viewed.timeIntervalSince1970 * 1000]
        try JSONSerialization.data(withJSONObject: row).write(to: folder.appendingPathComponent("local.json"))
        var old = Session(agent: .claude, sessionID: "session_bridge", state: .completed, updatedAt: viewed.addingTimeInterval(-30), revision: "turn1")
        old.remote = RemoteOrigin(kind: .remoteControl, host: "org")
        let reader = SessionViewReader(home: home, environment: [:])
        let snapshot = await reader.read(pending: [old.id: PendingDelivery(session: old)], foregroundApp: "dev.bolin.agent-island")
        XCTAssertEqual(snapshot.receipts.map(\.sessionKey), [old.id])
        var inbox = DeliveryInbox(); inbox.record(old)
        XCTAssertTrue(inbox.acknowledge(snapshot.receipts[0], now: now))
        var newer = old; newer.revision = "turn2"; newer.updatedAt = now
        let unseen = await reader.read(pending: [newer.id: PendingDelivery(session: newer)], foregroundApp: "dev.bolin.agent-island")
        XCTAssertTrue(unseen.receipts.isEmpty, "Old focus cannot acknowledge a later delivery.")
        var unrelated = old; unrelated.sessionID = "session_other"
        let different = await reader.read(pending: [unrelated.id: PendingDelivery(session: unrelated)], foregroundApp: "com.anthropic.claudefordesktop")
        XCTAssertTrue(different.receipts.isEmpty)
        var sshCopy = old; sshCopy.sessionID = "cli"; sshCopy.remote = RemoteOrigin(kind: .ssh, host: "build-host")
        let wrongHost = await reader.read(pending: [sshCopy.id: PendingDelivery(session: sshCopy)], foregroundApp: "com.anthropic.claudefordesktop")
        XCTAssertTrue(wrongHost.receipts.isEmpty, "Local focus must not acknowledge an unrelated SSH copy.")
    }
    func testKnownRemoteDesktopThreadAlreadyReadBeforeFirstPollCanClearExactTurn() {
        let now = Date()
        var s = Session(agent: .codex, sessionID: "same", state: .completed, updatedAt: now.addingTimeInterval(-10), revision: "turn")
        s.remote = RemoteOrigin(kind: .ssh, host: "build-host", hostID: "remote-ssh-discovered:build-host")
        var snapshot = CodexReadSnapshot(unreadByScope: ["account/remote-ssh-discovered:build-host:hash": []], modifiedAt: now)
        snapshot.knownUIThreadIDs = [s.sessionID]; snapshot.publishedTurnBySession = [s.id: "turn"]
        var inbox = DeliveryInbox(); inbox.record(s); inbox.observeCodex(snapshot, now: now)
        XCTAssertTrue(inbox.pending.isEmpty)
        XCTAssertFalse(inbox.record(s), "The same observed delivery must not return.")
    }
    func testMissingUnreadIDDoesNotClearUnknownCLIWrongHostWrongTurnOrStaleState() {
        let now = Date()
        var s = Session(agent: .codex, sessionID: "same", state: .completed, updatedAt: now.addingTimeInterval(-10), revision: "turn")
        s.remote = RemoteOrigin(kind: .ssh, host: "build-host", hostID: "remote-ssh-discovered:build-host")
        var valid = CodexReadSnapshot(unreadByScope: ["account/remote-ssh-discovered:build-host:hash": []], modifiedAt: now)
        valid.knownUIThreadIDs = [s.sessionID]; valid.publishedTurnBySession = [s.id: "turn"]
        for kind in 0..<5 {
            var snapshot = valid
            switch kind {
            case 0: snapshot.knownUIThreadIDs = []
            case 1: snapshot.unreadByScope = ["account/local:hash": []]
            case 2: snapshot.publishedTurnBySession = [s.id: "old-turn"]
            case 3: snapshot.modifiedAt = now.addingTimeInterval(-20)
            default: snapshot.unreadByScope["account/remote-control:other"] = [s.sessionID]
            }
            var inbox = DeliveryInbox(); inbox.record(s); inbox.observeCodex(snapshot, now: now)
            XCTAssertEqual(inbox.pending.count, 1, "Invalid proof variant \(kind)")
        }
    }
}
