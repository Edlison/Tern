import XCTest
@testable import TernCore

final class SessionTests: XCTestCase {
    private func data(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }
    func testCodexOnlyExplicitCompletionEndsTurn() {
        var p = TranscriptParser(agent: .codex, fallbackID: "fallback")
        p.consume(data(["type": "session_meta", "payload": ["id": "abc", "cwd": "/project"]]))
        p.consume(data(["type": "event_msg", "timestamp": "2026-10-26T12:00:00Z", "payload": ["type": "task_started", "turn_id": "turn1"]]))
        p.consume(data(["type": "response_item", "payload": ["type": "message", "role": "assistant", "content": [["type": "output_text", "text": "Still checking"]]]]))
        XCTAssertEqual(p.session.state, .running)
        p.consume(data(["type": "event_msg", "timestamp": "2026-10-26T12:01:00Z", "payload": ["type": "task_complete", "turn_id": "turn1", "last_agent_message": "Delivered files"]]))
        XCTAssertEqual(p.session.state, .completed); XCTAssertEqual(p.session.summary, "Delivered files")
        XCTAssertEqual(p.session.sessionID, "abc"); XCTAssertEqual(p.session.directory, "/project")
    }
    func testInterruptedDoesNotNotifyAsCompleted() {
        var p = TranscriptParser(agent: .codex, fallbackID: "a")
        p.consume(data(["type": "event_msg", "payload": ["type": "turn_aborted"]]))
        XCTAssertEqual(p.session.state, .interrupted); XCTAssertFalse(p.session.state.shouldAlert)
    }
    func testClaudeToolUseAndToolResultDoNotComplete() {
        var p = TranscriptParser(agent: .claude, fallbackID: "a")
        p.consume(data(["type": "assistant", "sessionId": "a", "message": ["id": "m", "stop_reason": "tool_use", "content": [["type": "text", "text": "Checking"]]]]))
        p.consume(data(["type": "user", "message": ["content": [["type": "tool_result", "content": "done"]]]]))
        XCTAssertEqual(p.session.state, .running)
        p.consume(data(["type": "assistant", "message": ["id": "m2", "stop_reason": "end_turn", "content": [["type": "text", "text": "Tests passed"]]]]))
        XCTAssertEqual(p.session.state, .completed); XCTAssertEqual(p.session.summary, "Tests passed")
    }
    func testClaudeSidechainIgnored() {
        var p = TranscriptParser(agent: .claude, fallbackID: "main")
        p.consume(data(["type": "assistant", "isSidechain": true, "sessionId": "child", "message": ["stop_reason": "end_turn"]]))
        XCTAssertEqual(p.session.sessionID, "main"); XCTAssertEqual(p.session.state, .unknown)
    }
    func testClaudeTokenLimitIsFailure() {
        var p = TranscriptParser(agent: .claude, fallbackID: "a")
        p.consume(data(["type": "assistant", "message": ["stop_reason": "max_tokens"]]))
        XCTAssertEqual(p.session.state, .failed)
    }
    func testPartialUTF8AndMalformedJSON() {
        var b = LineBuffer(); var p = TranscriptParser(agent: .codex, fallbackID: "a")
        let row = data(["type": "event_msg", "payload": ["type": "task_complete", "last_agent_message": "完成"]])
        XCTAssertTrue(b.append(Data(row.prefix(row.count - 3))).isEmpty)
        let lines = b.append(Data(row.suffix(3)) + Data([10]))
        XCTAssertEqual(lines.count, 1); p.consume(lines[0]); p.consume(Data("bad json".utf8))
        XCTAssertEqual(p.session.summary, "完成")
    }
    func testOversizedPartialLineIsDroppedThroughNewline() {
        var b = LineBuffer()
        XCTAssertTrue(b.append(Data(repeating: 65, count: 9 * 1024 * 1024)).isEmpty)
        XCTAssertEqual(b.append(Data("tail\nvalid\n".utf8)), [Data("valid".utf8)])
    }
    func testLedgerSuppressesHistoryAndDuplicateButAllowsNewTurns() {
        var ledger = AlertLedger(); let start = Date()
        var s = Session(agent: .codex, sessionID: "a", state: .completed, updatedAt: start.addingTimeInterval(-1), revision: "old")
        XCTAssertFalse(ledger.accept(s, liveSince: start))
        s.updatedAt = start.addingTimeInterval(1); s.revision = "new"
        XCTAssertTrue(ledger.accept(s, liveSince: start)); XCTAssertFalse(ledger.accept(s, liveSince: start))
        var restored = AlertLedger(seen: ledger.keys)
        XCTAssertFalse(restored.accept(s, liveSince: start)); s.revision = "next"
        XCTAssertTrue(restored.accept(s, liveSince: start))
    }
    func testGrokReplyIsNotAuthoritativeTaskCompletion() {
        let transcript: [String: Any] = ["entries": [["kind": "message", "id": "m", "role": "assistant", "content": "A reply", "isStreaming": false, "timestampMs": 1_800_000_000_000]]]
        let session = GrokSnapshot.parse(id: "a", row: ["title": "Task"], transcript: transcript, sourcePath: "cache")
        XCTAssertEqual(session.state, .replied); XCTAssertNotEqual(session.state, .completed)
        XCTAssertEqual(session.summary, "A reply")
    }
    func testGrokToolAndAutomationEventsCannotFinishTurn() {
        let transcript: [String: Any] = ["entries": [["kind": "message", "id": "m", "role": "assistant", "content": "Working", "isStreaming": true], ["kind": "event", "event": ["type": "automation-changed"]]]]
        XCTAssertEqual(GrokSnapshot.parse(id: "a", row: [:], transcript: transcript, sourcePath: "").state, .running)
    }
    func testNoTaskStatusFromGrokRosterAlone() {
        let s = GrokSnapshot.parse(id: "a", row: ["lastEntry": ["text": "Done"]], transcript: nil, sourcePath: "")
        XCTAssertEqual(s.state, .unknown); XCTAssertFalse(s.state.shouldAlert)
    }
    func testGrokDeliveredMessageAndEmptyTitleFallback() {
        let transcript: [String: Any] = ["entries": [
            ["kind": "message", "role": "user", "content": "Please work", "id": "u"],
            ["kind": "send-message", "id": "delivery", "message": ["type": "text", "content": "Delivered reply"], "timestampMs": 1_800_000_000_000]
        ]]
        let s = GrokSnapshot.parse(id: "a", row: ["title": "", "name": "My Bot", "path": "/private/store.db"], transcript: transcript, sourcePath: "")
        XCTAssertEqual(s.displayTitle, "My Bot"); XCTAssertEqual(s.directory, "")
        XCTAssertEqual(s.state, .replied); XCTAssertEqual(s.summary, "Delivered reply")
        XCTAssertEqual(s.revision, "delivery")
    }
    func testTitleSkipsInjectedEnvironmentAndSummaryRetainsMeaning() {
        XCTAssertNil(TextSummary.promptTitle("<environment_context>secret</environment_context>"))
        XCTAssertEqual(TextSummary.excerpt("## Done\n**Tests** passed: [report](/report.md)"), "Done Tests passed: report")
        XCTAssertEqual(GrokSnapshot.decodedKey("mzxw6.blob"), "foo")
    }
}
