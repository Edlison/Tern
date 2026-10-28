import XCTest
@testable import TernCore

final class MonitorTests: XCTestCase {
    private func fixtureHome() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex/sessions"), withIntermediateDirectories: true)
        return root
    }
    private func line(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) + Data([10]) }
    func testDiskTailPartialAppendAndTruncation() async throws {
        let root = try fixtureHome(); defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent(".codex/sessions/test.jsonl")
        let now = ISO8601DateFormatter().string(from: .now)
        let started = try line(["timestamp": now, "type": "event_msg", "payload": ["type": "task_started", "turn_id": "t1"]])
        try started.write(to: path)
        let monitor = SessionMonitor(home: root, environment: [:])
        var result = await monitor.poll(); XCTAssertEqual(result.0.first?.state, .running)
        let finished = try line(["timestamp": now, "type": "event_msg", "payload": ["type": "task_complete", "turn_id": "t1", "last_agent_message": "Delivered"]])
        let handle = try FileHandle(forWritingTo: path)
        try handle.seekToEnd(); try handle.write(contentsOf: finished.dropLast())
        result = await monitor.poll(); XCTAssertEqual(result.0.first?.state, .running)
        try handle.write(contentsOf: Data([10])); try handle.close()
        result = await monitor.poll(); XCTAssertEqual(result.0.first?.state, .completed)
        XCTAssertEqual(result.0.first?.summary, "Delivered")
        try started.write(to: path, options: .atomic)
        result = await monitor.poll(); XCTAssertEqual(result.0.first?.state, .running)
        XCTAssertEqual(result.0.first?.summary, "")
    }
    func testGrokActualEnvelopeVersionsAndAccountPairing() async throws {
        let root = try fixtureHome(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let time = Date().timeIntervalSince1970 * 1000
        func encode(_ value: String) -> String {
            let alphabet = Array("abcdefghijklmnopqrstuvwxyz234567")
            var bits = 0, accumulator = 0; var out = ""
            for byte in value.utf8 {
                accumulator = accumulator << 8 | Int(byte); bits += 8
                while bits >= 5 { bits -= 5; out.append(alphabet[(accumulator >> bits) & 31]) }
                accumulator &= (1 << bits) - 1
            }
            if bits > 0 { out.append(alphabet[(accumulator << (5 - bits)) & 31]) }
            return out + ".blob"
        }
        let prefix = "sand.client.slice.account.test."
        let roster: [String: Any] = ["schemaVersion": 4, "value": ["rows": [["id": "bot1", "title": "Sample", "lastActivityAt": time]]]]
        let transcript: [String: Any] = ["schemaVersion": 1, "value": ["entries": [["kind": "message", "role": "assistant", "content": "Result", "id": "message1", "timestampMs": time, "isStreaming": false]]]]
        try JSONSerialization.data(withJSONObject: roster).write(to: folder.appendingPathComponent(encode(prefix + "roster.last-roster")))
        try JSONSerialization.data(withJSONObject: transcript).write(to: folder.appendingPathComponent(encode(prefix + "transcript.replicas.bot1")))
        let result = await SessionMonitor(home: root, environment: [:]).poll()
        XCTAssertEqual(result.0.count, 1); XCTAssertEqual(result.0.first?.agent, .grok)
        XCTAssertEqual(result.0.first?.summary, "Result"); XCTAssertEqual(result.0.first?.state, .replied)
        XCTAssertEqual(result.1["grok"], "桌面缓存已连接 · 实验性")
    }
    func testStaleRunningBecomesUnknownNotCompleted() async throws {
        let root = try fixtureHome(); defer { try? FileManager.default.removeItem(at: root) }
        let old = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-3600))
        try line(["timestamp": old, "type": "event_msg", "payload": ["type": "task_started", "turn_id": "t1"]]).write(to: root.appendingPathComponent(".codex/sessions/test.jsonl"))
        let result = await SessionMonitor(home: root, environment: [:]).poll()
        XCTAssertEqual(result.0.first?.state, .unknown)
    }
}
