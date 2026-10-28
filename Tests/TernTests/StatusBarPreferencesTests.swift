import XCTest
import TernCore
@testable import Tern

final class StatusBarPreferencesTests: XCTestCase {
    @MainActor func testBothProfilesPersistIndependentlyAndNeverAcknowledgeDeliveries() async {
        let name = "TernTests.Bar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        let store = IslandStore(preferences: preferences)
        let pending = Session(agent: .grok, sessionID: "fixture", state: .replied, revision: "reply1")
        store.notify(pending, playAudio: false)
        XCTAssertEqual(store.statusBarMode, .idle, "Pending deliveries remain visible in the short bar when no task is running.")
        XCTAssertEqual(CompactIslandLayout.width(mode: store.statusBarMode, configuration: preferences.statusBar), 200)
        var idle = preferences.statusBar.idle; idle.remove(.reviewCount)
        preferences.setStatusBarProfile(idle, for: .idle)
        var active = preferences.statusBar.active; active.style = .terminal; active.fixedWidth = 344
        XCTAssertTrue(active.place(.clock, in: .left))
        preferences.setStatusBarProfile(active, for: .active)
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.statusBar.idle, idle)
        XCTAssertEqual(restored.statusBar.active, active)
        XCTAssertTrue(restored.statusBar.active.right.contains(.reviewCount))
        XCTAssertEqual(IslandStore(preferences: restored).unreadSessionIDs, [pending.id])
    }
    @MainActor func testLongTitlesAndChangingCountsCannotChangeActiveWidth() async {
        let name = "TernTests.Bar.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        let store = IslandStore(preferences: preferences)
        store.sessions = [Session(agent: .codex, sessionID: "a", title: "A", state: .running)]
        let width = CompactIslandLayout.width(mode: store.statusBarMode, configuration: preferences.statusBar)
        store.sessions = (0..<120).map { Session(agent: .codex, sessionID: "\($0)", title: String(repeating: "很长的任务标题", count: 100), state: .running) }
        XCTAssertEqual(CompactIslandLayout.width(mode: store.statusBarMode, configuration: preferences.statusBar), width)
        XCTAssertEqual(CompactBarData.counter(120), "99+")
        XCTAssertEqual(CompactBarData.counter(0), "0")
        let data = CompactBarData.live(store)
        XCTAssertEqual(data.runningCount, 120)
    }
}
