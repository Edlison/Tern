import XCTest
@testable import TernCore

final class RemoteTests: XCTestCase {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    func cache(rows: [[String: Any]], fetched: Date? = nil, statuses: [String] = ["active", "paused"]) -> [String: Any] {
        ["clientState": ["queries": [["queryKey": ["sessions_api_list_sessions", ["orgUuid": "org", "statuses": statuses]], "state": ["dataUpdatedAt": (fetched ?? date).timeIntervalSince1970 * 1000, "data": ["pages": [["data": rows, "has_more": false]]]]]]]]
    }
    func row(_ status: String = "completed", unread: Bool = true) -> [String: Any] {
        ["id": "session_test", "title": "Remote", "updated_at": date.timeIntervalSince1970, "created_at": date.addingTimeInterval(-60).timeIntervalSince1970, "status_bucket": status, "environment_kind": "bridge", "unread": unread, "worker_status": "idle"]
    }
    func remote(_ status: String = "completed") -> Session { ClaudeRemoteCache.parse(cache(rows: [row(status)]), sourcePath: "fixture")!.sessions[0] }
    func testClaudeRemoteStatusAndUnreadAreParsedWithoutLocalTranscript() {
        let s = remote(); XCTAssertEqual(s.state, .completed); XCTAssertEqual(s.sourceUnread, true)
        XCTAssertEqual(s.remote?.kind, .remoteControl); XCTAssertEqual(s.remote?.url, "https://claude.ai/code/session_test")
        XCTAssertEqual(remote("blocked").state, .waiting); XCTAssertEqual(remote("review_ready").state, .completed)
        var working = row(); working["worker_status"] = "running"
        XCTAssertEqual(ClaudeRemoteCache.parse(cache(rows: [working]), sourcePath: "")?.sessions[0].state, .running)
        XCTAssertEqual(remote("unrecognized").state, .unknown)
        var cloud = row(); cloud["environment_kind"] = "cloud"
        XCTAssertEqual(ClaudeRemoteCache.parse(cache(rows: [cloud]), sourcePath: "")?.sessions[0].remote?.kind, .cloud)
        XCTAssertNil(ClaudeRemoteCache.parse(cache(rows: [row()], statuses: ["archived"]), sourcePath: ""))
    }
    func testIdentitySeparatesHostsAndDecodesLegacyInbox() throws {
        let local = Session(agent: .codex, sessionID: "same")
        var one = local; one.remote = RemoteOrigin(kind: .ssh, host: "one")
        var two = local; two.remote = RemoteOrigin(kind: .ssh, host: "two")
        XCTAssertEqual(Set([local.id, one.id, two.id]).count, 3)
        let bytes = try JSONEncoder().encode(local)
        XCTAssertNil(try JSONDecoder().decode(Session.self, from: bytes).remote)
        var inbox = DeliveryInbox(); var legacy = local; legacy.state = .completed; legacy.revision = "t1"
        inbox.record(legacy)
        XCTAssertEqual(try JSONDecoder().decode(DeliveryInbox.self, from: JSONEncoder().encode(inbox)), inbox)
    }
    func testExplicitBridgeMappingMergesLatestLogWithoutFuzzyTitleMatch() {
        let cloud = remote()
        var log = Session(agent: .claude, sessionID: "cli", title: "different", summary: "actual delivery", state: .completed, updatedAt: date.addingTimeInterval(30), revision: "message2", source: "SSH · build-host")
        log.remote = RemoteOrigin(kind: .ssh, host: "build-host"); log.bridgeSessionID = cloud.sessionID
        let merged = SessionReconciler.merge([cloud, log]); XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, cloud.id); XCTAssertEqual(merged[0].summary, "actual delivery")
        XCTAssertEqual(merged[0].revision, "message2"); XCTAssertEqual(merged[0].observedAt, cloud.observedAt)
        log.bridgeSessionID = nil; log.title = cloud.title
        XCTAssertEqual(SessionReconciler.merge([cloud, log]).count, 2)
    }
    func testLaterCloudMetadataKeepsLogExcerptAndEnrichesPendingWithoutAcknowledgment() {
        let cloud = remote()
        var log = Session(agent: .claude, sessionID: "cli", summary: "delivered files", state: .completed, updatedAt: date.addingTimeInterval(-5), revision: "message1")
        log.bridgeSessionID = cloud.sessionID
        let merged = SessionReconciler.merge([cloud, log])[0]
        XCTAssertTrue(merged.summary.contains("delivered files")); XCTAssertEqual(merged.revision, cloud.revision)
        var inbox = DeliveryInbox(); inbox.record(cloud); inbox.refreshContent(from: [merged])
        XCTAssertEqual(inbox.pending.count, 1); XCTAssertTrue(inbox.acknowledged.isEmpty)
        XCTAssertEqual(inbox.pending[merged.id]?.session.summary, merged.summary)
    }
    func testHistoricalUnreadRecoveryIsDeduplicatedAndNotAppliedToReadHistory() {
        var ledger = AlertLedger(); let s = remote()
        XCTAssertTrue(ledger.accept(s, liveSince: date.addingTimeInterval(10), recoverUnread: true))
        XCTAssertFalse(ledger.accept(s, liveSince: date, recoverUnread: true))
        var read = s; read.revision = "older-read"; read.sourceUnread = false
        XCTAssertFalse(ledger.accept(read, liveSince: date.addingTimeInterval(10), recoverUnread: true))
    }
    func testRemoteReadRequiresNewerFetchSameRevisionAndForegroundSource() {
        var s = remote(); var inbox = DeliveryInbox(); inbox.record(s)
        var tracker = RemoteReadTracker()
        XCTAssertTrue(tracker.observe(sessions: [s], pending: inbox.pending, foregroundApp: nil).isEmpty)
        s.sourceUnread = false
        XCTAssertTrue(tracker.observe(sessions: [s], pending: inbox.pending, foregroundApp: "com.anthropic.claudefordesktop").isEmpty)
        s.sourceUnread = true
        _ = tracker.observe(sessions: [s], pending: inbox.pending, foregroundApp: nil)
        s.sourceUnread = false; s.observedAt = date.addingTimeInterval(5)
        let receipts = tracker.observe(sessions: [s], pending: inbox.pending, foregroundApp: "com.anthropic.claudefordesktop")
        XCTAssertEqual(receipts.count, 1); XCTAssertTrue(inbox.acknowledge(receipts[0], now: date.addingTimeInterval(10)))
        inbox.record(s); var newer = s; newer.revision = "new-turn"; newer.updatedAt = date.addingTimeInterval(30); inbox.record(newer)
        XCTAssertTrue(tracker.observe(sessions: [s], pending: inbox.pending, foregroundApp: "com.anthropic.claudefordesktop").isEmpty)
    }
    func testRemoteCodexCannotUseLocalReadReceiptWithSameID() {
        var s = Session(agent: .codex, sessionID: "same", state: .completed, updatedAt: date, revision: "turn")
        s.remote = RemoteOrigin(kind: .ssh, host: "build-host"); var inbox = DeliveryInbox(); inbox.record(s)
        inbox.observeCodex(CodexReadSnapshot(unreadByScope: ["local": ["same"]], modifiedAt: date, publishedTurnByThread: ["same":"turn"], sourceAppIsForeground: true), now: date)
        inbox.observeCodex(CodexReadSnapshot(unreadByScope: ["local": []], modifiedAt: date.addingTimeInterval(1), publishedTurnByThread: ["same":"turn"], sourceAppIsForeground: true), now: date.addingTimeInterval(1))
        XCTAssertEqual(inbox.pending.count, 1)
    }
    func testGrokNewRosterDeliveryWinsOverOldTranscriptAndUnknownDoesNotFinish() {
        let old: [String: Any] = ["entries": [["kind": "message", "role": "assistant", "content": "old", "id": "old", "timestampMs": date.addingTimeInterval(-10).timeIntervalSince1970 * 1000]]]
        var row: [String: Any] = ["lastActivityAt": date.timeIntervalSince1970 * 1000, "hasUnread": true, "lastMessageId": "new", "lastEntry": ["kind": "text", "text": "new delivery", "sessionPreview": ["kind": "message_text", "text": "new delivery"]]]
        let s = GrokSnapshot.parse(id: "bot", row: row, transcript: old, sourcePath: "")
        XCTAssertEqual(s.revision, "new"); XCTAssertEqual(s.summary, "new delivery"); XCTAssertEqual(s.state, .replied)
        XCTAssertEqual(GrokSnapshot.parse(id: "bot", row: row, transcript: nil, sourcePath: "").state, .replied)
        row["hasUnread"] = false
        XCTAssertEqual(GrokSnapshot.parse(id: "bot", row: row, transcript: old, sourcePath: "").state, .unknown)
        XCTAssertEqual(GrokSnapshot.parse(id: "bot", row: row, transcript: nil, sourcePath: "").state, .unknown)
    }
    func testSSHDiscoveryOnlyUsesAgentConfiguredAliasesAndQuotesResume() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: dir) }
        try JSONSerialization.data(withJSONObject: ["codex-managed-remote-connections": [["alias":"build-host"],["alias":"-oProxyCommand=bad"],["alias":"build-host"],["alias":"host;bad"]]]).write(to: dir.appendingPathComponent(".codex-global-state.json"))
        XCTAssertEqual(RemoteDiscovery.sshAliases(codexHome: dir), ["build-host"])
        var s = Session(agent: .claude, sessionID: "id'$(echo x)", directory: "/my folder/'x")
        s.remote = RemoteOrigin(kind: .ssh, host: "build-host")
        let command = SessionNavigation.resumeCommand(s)!
        XCTAssertTrue(command.hasPrefix("ssh -t -- 'build-host' 'cd -- ")); XCTAssertTrue(command.contains("'\\''"))
        s.remote?.host = "-bad"; XCTAssertNil(SessionNavigation.resumeCommand(s))
    }
    func testCodexCloudRecognizesOnlyExplicitStatusesAndSafeURLs() throws {
        let rows: [[String: Any]] = [
            ["id":"one", "status":"ready", "updated_at":date.timeIntervalSince1970, "url":"https://chatgpt.com/codex/tasks/one"],
            ["id":"two", "status":"surprise", "updated_at":date.timeIntervalSince1970, "url":"https://evil.example/task"]]
        let list = try CodexCloud.parse(JSONSerialization.data(withJSONObject: ["tasks":rows, "cursor":"next"]))
        XCTAssertEqual(list.sessions.map(\.state), [.completed, .unknown]); XCTAssertTrue(list.hasMore)
        XCTAssertNotNil(list.sessions[0].remote?.url); XCTAssertNil(list.sessions[1].remote?.url)
        XCTAssertThrowsError(try CodexCloud.parse(Data("{}".utf8)))
    }
    func testSSHProbeRetainsLatestStartAcrossLongTaskAndIncrementalCompletion() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else { throw XCTSkip("Python unavailable") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = folder.appendingPathComponent("test.jsonl")
        let stamp = Date().timeIntervalSince1970
        func event(_ name: String, turn: String) -> [String: Any] { ["timestamp":stamp, "type":"event_msg", "payload":["type":name, "turn_id":turn]] }
        var rows: [[String: Any]] = [["type":"session_meta", "payload":["id":"remote-id", "cwd":"/project"]], event("task_started", turn:"old"), event("task_complete", turn:"old"), event("task_started", turn:"new")]
        rows += (0..<160).map { _ in ["timestamp":stamp, "type":"response_item", "payload":["type":"message", "role":"assistant", "content":[["type":"output_text", "text":"progress"]]]] }
        func save() throws { try rows.reduce(into: Data()) { data,row in data += try JSONSerialization.data(withJSONObject: row); data.append(10) }.write(to:file) }
        try save()
        let resource = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/TernCore/Resources/remote-sessions.py")
        let base = try String(contentsOf: resource)
        let jsonPath = String(decoding: try JSONSerialization.data(withJSONObject: root.path, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
        func probe(_ previous: [String:String]) throws -> [String:Any] {
            let prefix = "import os\nos.environ['CODEX_HOME']=\(jsonPath)\nos.environ['CLAUDE_CONFIG_DIR']=\(jsonPath)\n"
            let script = prefix + base.replacingOccurrences(of:"__PREVIOUS__", with:try JSONSerialization.data(withJSONObject:previous).base64EncodedString())
            let result = try ReadOnlyCommand.run("/usr/bin/python3", ["-"], input:Data(script.utf8))
            XCTAssertEqual(result.status,0)
            let files = try XCTUnwrap((JSONSerialization.jsonObject(with:result.data) as? [String:Any])?["files"] as? [[String:Any]])
            return try XCTUnwrap(files.first)
        }
        let first = try probe([:]); var parser = TranscriptParser(agent:.codex, fallbackID:"fallback")
        for row in first["lines"] as! [[String:Any]] { parser.consume(try JSONSerialization.data(withJSONObject:row)) }
        XCTAssertEqual(parser.session.state,.running); XCTAssertEqual(parser.session.revision,"new")
        let previous = [file.path:first["version"] as! String]
        XCTAssertNil(try probe(previous)["lines"])
        rows.append(event("task_complete",turn:"new")); try save()
        let second = try probe(previous); var completed = TranscriptParser(agent:.codex, fallbackID:"fallback")
        for row in second["lines"] as! [[String:Any]] { completed.consume(try JSONSerialization.data(withJSONObject:row)) }
        XCTAssertEqual(completed.session.state,.completed); XCTAssertEqual(completed.session.revision,"new")
    }
    func testReadOnlyProcessHasBoundedOutputAndTimeout() throws {
        XCTAssertThrowsError(try ReadOnlyCommand.run("/bin/sleep", ["2"], timeout: 0.1))
        XCTAssertThrowsError(try ReadOnlyCommand.run("/usr/bin/printf", [String(repeating: "a", count: 2000)], limit: 100))
        XCTAssertEqual(String(decoding: try ReadOnlyCommand.run("/usr/bin/printf", ["ok"]).data, as: UTF8.self), "ok")
    }
}

final class BrowserCacheDecoderTests: XCTestCase {
    func vi(_ n: Int) -> [UInt8] { var n = n, result: [UInt8] = []; repeat { let b = n & 127; n >>= 7; result.append(UInt8(b | (n > 0 ? 128 : 0))) } while n > 0; return result }
    func encode(_ value: Any) -> [UInt8] {
        if let s = value as? String { let bytes = Array(s.utf8); return [83] + vi(bytes.count) + bytes }
        if let d = value as? [String: Any] { return [111] + d.keys.sorted().flatMap { encode($0) + encode(d[$0]!) } + [123] + vi(d.count) }
        if let a = value as? [Any] { return [65] + vi(a.count) + a.flatMap(encode) + [36, 0] + vi(a.count) }
        if let n = value as? Int { return [85] + vi(n) }
        return [48]
    }
    func testCompressedBlinkStructuredCloneWithUnicodeAndArrays() throws {
        let raw: [UInt8] = [255,21,254] + Array(repeating: 0, count: 12) + [255,16] + encode(["clientState": ["queries": ["中文", "x"]], "count": 2])
        let size = raw.count - 1
        let snappy = vi(raw.count) + [240, UInt8(size & 255)] + raw
        let decoded = try BrowserCacheDecoder.decode(Data([255,17,2] + snappy))
        XCTAssertEqual(decoded["count"] as? Int, 2)
        XCTAssertEqual((decoded["clientState"] as? [String: Any])?["queries"] as? [String], ["中文", "x"])
    }
    func testReferencesLatin1UTF16AndNumericObjectKeys() throws {
        let string: [UInt8] = [34,1,233]
        let raw: [UInt8] = [255,16,111] + encode("a") + [111] + encode("b") + string + [123,1] + encode("copy") + [94,1] + encode("wide") + [99,2,45,78] + [123,3]
        let root = try BrowserCacheDecoder.decode(Data(raw))
        XCTAssertEqual((root["copy"] as? [String: Any])?["b"] as? String, "é"); XCTAssertEqual(root["wide"] as? String, "中")
    }
    func testBadOffsetsTruncationAndUnknownVersionsFailClosed() {
        XCTAssertThrowsError(try BrowserCacheDecoder.snappy([5,1,0]))
        XCTAssertThrowsError(try BrowserCacheDecoder.decode(Data([255,99,111,123,0])))
        XCTAssertThrowsError(try BrowserCacheDecoder.decode(Data([255,16,111,83,100,65])))
        XCTAssertThrowsError(try BrowserCacheDecoder.decode(Data([255,16,111,94,10])))
        XCTAssertThrowsError(try BrowserCacheDecoder.snappy(vi(100_000_000)))
    }
}
