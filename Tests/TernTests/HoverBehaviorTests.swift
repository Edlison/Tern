import AppKit
import XCTest
import TernCore
@testable import Tern

final class HoverBehaviorTests: XCTestCase {
    @MainActor private func makeStore() -> IslandStore {
        // Keep tests isolated from the running app's settings and notification permissions.
        let defaults = UserDefaults(suiteName: "TernTests.\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)
        preferences.muted = false
        preferences.showIsland = true
        preferences.notificationEnabled = false
        return IslandStore(preferences: preferences)
    }
    private func delivery() -> Session {
        Session(agent: .codex, sessionID: "fixture", title: "Delivery", state: .completed, revision: "turn1")
    }
    @MainActor func testDeliveryAddsCompactHintWithoutOpening() async {
        let store = makeStore()
        store.notify(delivery(), playAudio: false)
        XCTAssertFalse(store.expanded)
        XCTAssertEqual(store.unreadSessionIDs, [delivery().id])
        XCTAssertEqual(store.compactLabel, "Codex · 待检查")
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(store.expanded)
    }
    @MainActor func testHoverIsRequiredAndLeavingCollapsesEvenAfterDelivery() async {
        let store = makeStore()
        store.hover(true)
        XCTAssertFalse(store.expanded)
        try? await Task.sleep(for: .milliseconds(240))
        XCTAssertTrue(store.expanded)
        store.selectIslandTab("active")
        store.notify(delivery(), playAudio: false)
        XCTAssertTrue(store.expanded)
        XCTAssertEqual(store.islandTab, "active", "A new result must not navigate away from the view being read.")
        store.hover(false)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(store.expanded)
    }
    @MainActor func testBriefHoverAndLateDeliveryCannotReopen() async {
        let store = makeStore()
        store.hover(true); store.hover(false)
        store.notify(delivery(), playAudio: false)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(store.expanded)
    }
    @MainActor func testPreviewDoesNotOpenTheIsland() async {
        let store = makeStore()
        store.demo()
        XCTAssertTrue(store.isDemo)
        XCTAssertFalse(store.expanded)
        store.endDemo()
    }
    @MainActor func testNativePanelDoesNotConstrainTopIntoTheMenuBar() async {
        _ = NSApplication.shared
        let panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let screen = NSScreen.screens.first
        let top = screen?.frame.maxY ?? 900
        let requested = CGRect(x: 100, y: top - 474, width: 610, height: 474)
        XCTAssertEqual(panel.constrainFrameRect(requested, to: screen), requested)
        panel.setFrame(requested, display: false)
        XCTAssertEqual(panel.frame.maxY, top, accuracy: 0.001)
        panel.close()
    }
}
