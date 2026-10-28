import XCTest
import TernCore
@testable import Tern

final class WorkspaceTests: XCTestCase {
    @MainActor func testCurrentAndHistoryPartitionMovesViewedDeliveryWithoutAffectingRunning() {
        let name = "TernTests.Workspace.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = Preferences(defaults: defaults); prefs.muted = true
        let store = IslandStore(preferences: prefs)
        let running = Session(agent: .codex, sessionID: "run", state: .running)
        let review = Session(agent: .claude, sessionID: "review", state: .completed, updatedAt: Date().addingTimeInterval(-2), revision: "t1")
        let history = Session(agent: .grok, sessionID: "old", state: .replied)
        store.sessions = [running, review, history]; store.notify(review, quietly: true)
        XCTAssertEqual(Set(store.activeSessions.map(\.id)), [running.id, review.id]); XCTAssertEqual(store.historySessions.map(\.id), [history.id])
        XCTAssertEqual(store.runningAgents, [.codex]); XCTAssertEqual(CompactBarData.live(store).agentRunning, [.codex: 1])
        var snapshot = SessionViewSnapshot(); snapshot.receipts = [SessionViewReceipt(sessionKey: review.id, revision: "t1", viewedAt: .now, evidence: .claudeVisibleSession)]
        store.applySourceViews(snapshot)
        XCTAssertEqual(store.activeSessions.map(\.id), [running.id]); XCTAssertEqual(Set(store.historySessions.map(\.id)), [review.id, history.id])
        XCTAssertFalse(store.unreadSessionIDs.contains(review.id)); XCTAssertTrue(CompactBarData.live(store).reviewAgents.isEmpty)
        store.selectIslandTab("history"); XCTAssertEqual(Set(store.islandSessions.map(\.id)), [review.id, history.id])
    }
}
