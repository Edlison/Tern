import XCTest
@testable import TernCore

final class PresentationTests: XCTestCase {
    func testAttentionAndRunningComeBeforeNewerHistoricalReplies() {
        let now = Date()
        let done = Session(agent: .codex, sessionID: "done", state: .completed, updatedAt: now)
        let running = Session(agent: .claude, sessionID: "running", state: .running, updatedAt: now.addingTimeInterval(-60))
        let waiting = Session(agent: .grok, sessionID: "waiting", state: .waiting, updatedAt: now.addingTimeInterval(-120))
        XCTAssertEqual(SessionPresentation.ordered([done, running, waiting], prioritizeActivity: true).map(\.sessionID), ["waiting", "running", "done"])
        XCTAssertEqual(SessionPresentation.ordered([done, running, waiting], prioritizeActivity: false).map(\.sessionID), ["done", "running", "waiting"])
    }
    func testStableOrderForSameTimestamp() {
        let now = Date()
        let a = Session(agent: .codex, sessionID: "a", state: .running, updatedAt: now)
        let b = Session(agent: .codex, sessionID: "b", state: .running, updatedAt: now)
        XCTAssertEqual(SessionPresentation.ordered([b, a], prioritizeActivity: true).map(\.sessionID), ["a", "b"])
    }
    func testCompactLabelsAndTimeBoundaries() {
        let now = Date()
        XCTAssertEqual(SessionPresentation.projectName(Session(agent: .grok, sessionID: "a")), "Grok Bot")
        XCTAssertEqual(SessionPresentation.projectName(Session(agent: .codex, sessionID: "b", directory: "/workspace/Project")), "Project")
        XCTAssertEqual(SessionPresentation.relativeTime(now.addingTimeInterval(30), now: now), "刚刚")
        XCTAssertEqual(SessionPresentation.relativeTime(now.addingTimeInterval(-3600), now: now), "1h")
    }
}
