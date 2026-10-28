import XCTest
@testable import TernCore

final class DeliveryInboxTests: XCTestCase {
    private let completed = Date(timeIntervalSince1970: 1_790_000_000)
    private func session(_ agent: Agent = .codex, revision: String = "turn1") -> Session {
        Session(agent: agent, sessionID: "a", summary: "Delivery", state: .completed, updatedAt: completed, revision: revision)
    }
    func testOnlyMatchingSourceSessionAndNewEnoughReceiptCanClear() {
        let s = session(.claude); var inbox = DeliveryInbox(); inbox.record(s)
        for receipt in [
            SessionViewReceipt(sessionKey: "claude:other", revision: "turn1", viewedAt: completed.addingTimeInterval(1), evidence: .claudeFocusedSession),
            SessionViewReceipt(sessionKey: s.id, revision: "old-turn", viewedAt: completed.addingTimeInterval(1), evidence: .claudeFocusedSession),
            SessionViewReceipt(sessionKey: s.id, revision: "turn1", viewedAt: completed.addingTimeInterval(-1), evidence: .claudeFocusedSession),
            SessionViewReceipt(sessionKey: s.id, revision: "turn1", viewedAt: completed.addingTimeInterval(1), evidence: .grokViewedSession)
        ] { XCTAssertFalse(inbox.acknowledge(receipt)); XCTAssertEqual(inbox.pending.count, 1) }
        XCTAssertTrue(inbox.acknowledge(SessionViewReceipt(sessionKey: s.id, revision: "turn1", viewedAt: completed.addingTimeInterval(1), evidence: .claudeFocusedSession)))
        XCTAssertTrue(inbox.pending.isEmpty)
        XCTAssertFalse(inbox.record(s), "Polling the same delivery again must not resurrect it.")
    }
    func testOldReceiptCannotClearNewDeliveryInSameSession() {
        var inbox = DeliveryInbox(); inbox.record(session(.grok))
        var next = session(.grok, revision: "turn2"); next.updatedAt = completed.addingTimeInterval(30)
        inbox.record(next)
        XCTAssertFalse(inbox.acknowledge(SessionViewReceipt(sessionKey: next.id, revision: "turn1", viewedAt: completed.addingTimeInterval(60), evidence: .grokViewedSession)))
        XCTAssertEqual(inbox.pending[next.id]?.session.revision, "turn2")
    }
    func testCodexAbsenceOrAccountSwitchIsNotAView() {
        var inbox = DeliveryInbox(); inbox.record(session())
        let date = completed.addingTimeInterval(1)
        inbox.observeCodex(CodexReadSnapshot(unreadByScope: ["account/local": []], modifiedAt: date, publishedTurnByThread: ["a": "turn1"], sourceAppIsForeground: true))
        XCTAssertEqual(inbox.pending.count, 1)
        inbox.observeCodex(CodexReadSnapshot(unreadByScope: ["account/local": ["a"]], modifiedAt: date))
        inbox.observeCodex(CodexReadSnapshot(unreadByScope: ["different-account/local": []], modifiedAt: date, publishedTurnByThread: ["a": "turn1"], sourceAppIsForeground: true))
        XCTAssertEqual(inbox.pending.count, 1)
    }
    func testCodexReadTransitionMustMatchPublishedDeliveryTurn() {
        var inbox = DeliveryInbox(); inbox.record(session())
        let date = completed.addingTimeInterval(1)
        inbox.observeCodex(CodexReadSnapshot(unreadByScope: ["account/local": ["a"]], modifiedAt: date))
        inbox.observeCodex(CodexReadSnapshot(unreadByScope: ["account/local": []], modifiedAt: date, publishedTurnByThread: ["a": "old-turn"], sourceAppIsForeground: true))
        XCTAssertEqual(inbox.pending.count, 1)
        inbox.observeCodex(CodexReadSnapshot(unreadByScope: ["account/local": []], modifiedAt: date, publishedTurnByThread: ["a": "turn1"], sourceAppIsForeground: true))
        XCTAssertTrue(inbox.pending.isEmpty)
    }
    func testPendingAndUnreadWitnessSurviveRestart() throws {
        var inbox = DeliveryInbox(); inbox.record(session())
        inbox.observeCodex(CodexReadSnapshot(unreadByScope: ["account/local": ["a"]], modifiedAt: completed.addingTimeInterval(1)))
        var restored = try JSONDecoder().decode(DeliveryInbox.self, from: JSONEncoder().encode(inbox))
        XCTAssertEqual(restored, inbox)
        restored.observeCodex(CodexReadSnapshot(unreadByScope: ["account/local": []], modifiedAt: completed.addingTimeInterval(2), publishedTurnByThread: ["a": "turn1"], sourceAppIsForeground: true))
        XCTAssertTrue(restored.pending.isEmpty)
    }
    func testStaleMetadataCannotWitnessCurrentDelivery() {
        var inbox = DeliveryInbox(); inbox.record(session())
        inbox.observeCodex(CodexReadSnapshot(unreadByScope: ["account/local": ["a"]], modifiedAt: completed.addingTimeInterval(-1)))
        XCTAssertEqual(inbox.pending["codex:a"]?.codexUnreadScopes, [])
    }
    func testReadTransitionAfterUserSwitchesAwayStillAcknowledgesExactDelivery() {
        var inbox = DeliveryInbox(); inbox.record(session())
        let date = completed.addingTimeInterval(1)
        inbox.observeCodex(CodexReadSnapshot(unreadByScope: ["account/local": ["a"]], modifiedAt: date, publishedTurnByThread: ["a": "turn1"]))
        inbox.observeCodex(CodexReadSnapshot(unreadByScope: ["account/local": []], modifiedAt: date.addingTimeInterval(2)))
        XCTAssertTrue(inbox.pending.isEmpty, "The published turn was witnessed before the source removed its unread receipt.")
    }
    func testCodexReadScopesKeepLocalAndRemoteIdentitiesSeparate() {
        XCTAssertNil(CodexReadSnapshot.parse([:], modifiedAt: completed))
        let snapshot = CodexReadSnapshot.parse(["electron-thread-read-state-v1": ["version": 1, "unreadByIdentity": ["account": ["local:root": ["a"], "remote:host": ["b"]]]]], modifiedAt: completed)
        XCTAssertEqual(snapshot?.unreadByScope, ["account/local:root": Set(["a"]), "account/remote:host": Set(["b"])])
    }
    func testIdleWidthShrinksAndNeverCoversPhysicalNotch() {
        XCTAssertEqual(CompactIslandLayout.width(mode: .idle), 200)
        XCTAssertEqual(CompactIslandLayout.width(mode: .active), 300)
        XCTAssertEqual(CompactIslandLayout.width(mode: .idle, physicalNotchWidth: 210), 446)
        XCTAssertGreaterThan(CompactIslandLayout.width(mode: .active, physicalNotchWidth: 210), 446)
    }
}
