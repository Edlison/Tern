import XCTest
import TernCore
@testable import Tern

final class DeliveryReviewTests: XCTestCase {
    @MainActor func testBrowsingWorkspaceNeverAcknowledgesDelivery() async {
        let name = "TernTests.Review.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        let store = IslandStore(preferences: preferences)
        let delivery = Session(agent: .claude, sessionID: "fixture", summary: "Done", state: .completed, revision: "turn1")
        store.notify(delivery, playAudio: false)
        store.section = "history"; store.selectIslandTab("history")
        XCTAssertEqual(store.unreadSessionIDs, [delivery.id])
        XCTAssertTrue(store.hasCompactActivity)
        let restored = IslandStore(preferences: Preferences(defaults: defaults))
        XCTAssertEqual(restored.unreadSessionIDs, [delivery.id])
        var snapshot = SessionViewSnapshot()
        snapshot.receipts = [SessionViewReceipt(sessionKey: delivery.id, revision: "turn1", viewedAt: .now, evidence: .claudeFocusedSession)]
        restored.applySourceViews(snapshot)
        XCTAssertTrue(restored.unreadSessionIDs.isEmpty)
        XCTAssertFalse(restored.hasCompactActivity)
        XCTAssertTrue(IslandStore(preferences: Preferences(defaults: defaults)).unreadSessionIDs.isEmpty)
    }
    @MainActor func testHistoryDoesNotStretchIdleIslandAndMuteDoesNotDiscardPending() async {
        let name = "TernTests.Review.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults); preferences.muted = true
        let store = IslandStore(preferences: preferences)
        let history = Session(agent: .grok, sessionID: "old", state: .replied, revision: "reply")
        store.sessions = [history]
        XCTAssertFalse(store.hasCompactActivity); XCTAssertEqual(store.compactLabel, "")
        store.notify(history, playAudio: false)
        XCTAssertTrue(store.hasCompactActivity); XCTAssertEqual(store.unreadSessionIDs, [history.id])
        preferences.enabledAgents = []
        XCTAssertEqual(store.unreadSessionIDs, [history.id], "Disabling a source cannot dismiss existing pending deliveries.")
        store.demo(); store.endDemo()
        XCTAssertEqual(store.unreadSessionIDs, [history.id], "Leaving a demo must not clear real deliveries.")
    }
}
