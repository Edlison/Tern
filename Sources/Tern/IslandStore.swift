import AppKit
import SwiftUI
import UserNotifications
import CryptoKit
import TernCore

@MainActor final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var showIsland: Bool { didSet { save() } }
    @Published var muted: Bool { didSet { save() } }
    @Published var soundEnabled: Bool { didSet { save() } }
    @Published var speechEnabled: Bool { didSet { save() } }
    @Published var notificationEnabled: Bool { didSet { save() } }
    @Published var outputUID: String { didSet { save() } }
    @Published var soundName: String { didSet { save() } }
    @Published var customSound: String { didSet { save() } }
    @Published var voiceID: String { didSet { save() } }
    @Published var volume: Double { didSet { save() } }
    @Published var speechTemplate: String { didSet { save() } }
    @Published var enabledAgents: Set<Agent> { didSet { save() } }
    @Published var theme: AccentTheme { didSet { save() } }
    @Published private(set) var statusBar: StatusBarConfiguration
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        showIsland = d.object(forKey: "showIsland") as? Bool ?? true
        muted = d.bool(forKey: "muted")
        soundEnabled = d.object(forKey: "soundEnabled") as? Bool ?? true
        speechEnabled = d.bool(forKey: "speechEnabled")
        notificationEnabled = d.bool(forKey: "notificationEnabled")
        outputUID = d.string(forKey: "outputUID") ?? ""
        soundName = d.string(forKey: "soundName") ?? "Glass"
        customSound = d.string(forKey: "customSound") ?? ""
        voiceID = d.string(forKey: "voiceID") ?? ""
        volume = d.object(forKey: "volume") as? Double ?? 0.65
        speechTemplate = d.string(forKey: "speechTemplate") ?? "{agent}，{title}，{status}。"
        enabledAgents = Set((d.stringArray(forKey: "enabledAgents") ?? Agent.allCases.map(\.rawValue)).compactMap(Agent.init(rawValue:)))
        theme = d.string(forKey: "accentTheme").flatMap(AccentTheme.init(rawValue:)) ?? .teal
        statusBar = d.data(forKey: "statusBarConfiguration.v1")
            .flatMap { try? JSONDecoder().decode(StatusBarConfiguration.self, from: $0) }?.normalized() ?? .defaults
    }
    func setStatusBarProfile(_ profile: StatusBarProfile, for mode: StatusBarMode) {
        var next = statusBar; next.set(profile, for: mode)
        statusBar = next
        save()
    }
    func resetStatusBarProfile(for mode: StatusBarMode) {
        setStatusBarProfile(mode == .idle ? .idle : .active, for: mode)
    }
    func loadDeliveryInbox() -> DeliveryInbox {
        guard let data = defaults.data(forKey: "pendingDeliveryInbox.v1") else { return DeliveryInbox() }
        return (try? JSONDecoder().decode(DeliveryInbox.self, from: data)) ?? DeliveryInbox()
    }
    func saveDeliveryInbox(_ inbox: DeliveryInbox) {
        if let data = try? JSONEncoder().encode(inbox) { defaults.set(data, forKey: "pendingDeliveryInbox.v1") }
    }
    private func save() {
        let d = defaults
        d.set(showIsland, forKey: "showIsland"); d.set(muted, forKey: "muted")
        d.set(soundEnabled, forKey: "soundEnabled"); d.set(speechEnabled, forKey: "speechEnabled")
        d.set(notificationEnabled, forKey: "notificationEnabled"); d.set(outputUID, forKey: "outputUID")
        d.set(soundName, forKey: "soundName"); d.set(customSound, forKey: "customSound")
        d.set(voiceID, forKey: "voiceID"); d.set(volume, forKey: "volume")
        d.set(speechTemplate, forKey: "speechTemplate"); d.set(enabledAgents.map(\.rawValue), forKey: "enabledAgents")
        d.set(theme.rawValue, forKey: "accentTheme")
        if let data = try? JSONEncoder().encode(statusBar) { d.set(data, forKey: "statusBarConfiguration.v1") }
    }
}

@MainActor final class IslandStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var health: [String: String] = [:]
    @Published private(set) var expanded = false
    @Published var latestAlert: Session?
    @Published var toast: String?
    @Published var isDemo = false
    @Published var section = "active"
    @Published var compactWidth: CGFloat = 310
    @Published var topInset: CGFloat = 36
    @Published var hasNotch = false
    @Published var physicalNotchWidth: CGFloat = 0
    @Published var islandTab = "active"
    @Published var islandAgent: Agent?
    @Published private(set) var deliveryInbox: DeliveryInbox
    @Published private(set) var demoInbox = DeliveryInbox()
    @Published var viewHealth: [String: String] = [:]
    @Published private(set) var claudeDesktopSessionIDs: Set<String> = []
    @Published private(set) var claudeDesktopRoutes: [String: String] = [:]
    @Published var dockToEdge: Bool {
        didSet { UserDefaults.standard.set(dockToEdge, forKey: "dockToEdge") }
    }
    let preferences: Preferences
    let audio = AudioService()
    var openDashboard: (() -> Void)?
    private let monitor = SessionMonitor()
    private let viewReader = SessionViewReader()
    private let liveSince = Date()
    private var task: Task<Void, Never>?
    private var demoTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    private var pointerInside = false
    private var ledger = AlertLedger(seen: Set(UserDefaults.standard.stringArray(forKey: "seenAlerts") ?? []))
    var visibleSessions: [Session] { sessions.filter { preferences.enabledAgents.contains($0.agent) } }
    var running: [Session] { visibleSessions.filter { $0.state == .running } }
    var pendingSessions: [Session] {
        let inbox = isDemo ? demoInbox : deliveryInbox
        return inbox.pending.values.map(\.session).sorted { $0.updatedAt > $1.updatedAt }
    }
    var unreadSessionIDs: Set<String> { Set(pendingSessions.map(\.id)) }
    var hasCompactActivity: Bool { !running.isEmpty || !pendingSessions.isEmpty }
    var statusBarMode: StatusBarMode { running.isEmpty ? .idle : .active }
    var workspaceSessions: [Session] {
        var values = Dictionary(uniqueKeysWithValues: visibleSessions.map { ($0.id, $0) })
        for pending in pendingSessions where values[pending.id] == nil { values[pending.id] = pending }
        return Array(values.values)
    }
    var activeSessions: [Session] {
        SessionPresentation.ordered(workspaceSessions.filter { $0.state == .running || unreadSessionIDs.contains($0.id) }, prioritizeActivity: true)
    }
    var historySessions: [Session] {
        SessionPresentation.ordered(workspaceSessions.filter { $0.state != .running && !unreadSessionIDs.contains($0.id) }, prioritizeActivity: false)
    }
    var runningAgents: [Agent] { Agent.allCases.filter { agent in running.contains { $0.agent == agent } } }
    init(preferences: Preferences? = nil) {
        let prefs = preferences ?? Preferences()
        self.preferences = prefs
        deliveryInbox = prefs.loadDeliveryInbox()
        dockToEdge = UserDefaults.standard.object(forKey: "dockToEdge") as? Bool ?? true
    }
    var unreadAlert: Session? {
        if let alert = latestAlert, unreadSessionIDs.contains(alert.id) { return alert }
        return pendingSessions.first
    }
    var compactLabel: String {
        if pendingSessions.count > 1 { return "\(pendingSessions.count) 项待检查" }
        if let alert = unreadAlert { return "\(alert.agent.name) · 待检查" }
        return running.isEmpty ? "" : "\(running.count) 个 Agent 正在工作"
    }
    var focused: Session? { unreadAlert ?? running.first ?? historySessions.first }
    var islandSessions: [Session] {
        (islandTab == "history" ? historySessions : activeSessions).filter { islandAgent == nil || $0.agent == islandAgent }
    }
    var islandBodyHeight: CGFloat {
        let rowCount = min(islandSessions.count, 5)
        return rowCount == 0 ? 202 : 94 + CGFloat(rowCount) * 54
    }
    func selectIslandTab(_ tab: String) { islandTab = tab }
    func selectIslandAgent(_ agent: Agent?) { islandAgent = agent }
    func start() {
        audio.refreshDevices()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let (values, status) = await monitor.poll()
                health = status
                if !isDemo {
                    sessions = values
                    var enriched = deliveryInbox
                    enriched.refreshContent(from: values)
                    if enriched != deliveryInbox { deliveryInbox = enriched; preferences.saveDeliveryInbox(enriched) }
                    var alerts: [Session] = []
                    for s in values.reversed() {
                        if ledger.accept(s, liveSince: liveSince, recoverUnread: true), preferences.enabledAgents.contains(s.agent) { alerts.append(s) }
                    }
                    UserDefaults.standard.set(Array(ledger.keys).sorted().suffix(1000).map { $0 }, forKey: "seenAlerts")
                    // Avoid overlapping speech when several agents finish in one polling batch.
                    for s in alerts { notify(s, playAudio: s.id == alerts.last?.id, quietly: s.updatedAt < liveSince) }
                    let foreground = NSWorkspace.shared.frontmostApplication
                    let views = await viewReader.read(pending: deliveryInbox.pending, foregroundApp: foreground?.bundleIdentifier, sessions: values, foregroundLaunchedAt: foreground?.launchDate)
                    applySourceViews(views)
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    func notify(_ session: Session, playAudio: Bool = true, quietly: Bool = false) {
        latestAlert = session
        if session.isDemo { demoInbox.record(session) }
        else {
            deliveryInbox.record(session)
            preferences.saveDeliveryInbox(deliveryInbox)
        }
        // Prepare what the next hover will show without opening or disrupting a view in use.
        if !expanded {
            islandTab = "active"
            islandAgent = nil
        }
        guard !preferences.muted, !quietly else { return }
        if playAudio { audio.announce(session, preferences: preferences) }
        if preferences.notificationEnabled && !session.isDemo {
            let content = UNMutableNotificationContent()
            content.title = "\(session.agent.name) · \(session.state.label)"
            content.subtitle = session.displayTitle
            content.body = session.excerpt
            content.userInfo = ["session": session.id]
            // Audio is routed by AudioService; don't double-play the notification sound.
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: session.alertKey, content: content, trigger: nil)) { _ in }
        }
    }
    func applySourceViews(_ snapshot: SessionViewSnapshot) {
        viewHealth = snapshot.health
        claudeDesktopSessionIDs = snapshot.claudeDesktopSessionIDs
        claudeDesktopRoutes = snapshot.claudeDesktopRoutes
        var next = deliveryInbox
        if let codex = snapshot.codex { next.observeCodex(codex) }
        for receipt in snapshot.receipts { next.acknowledge(receipt) }
        if next != deliveryInbox {
            deliveryInbox = next
            preferences.saveDeliveryInbox(next)
        }
    }
    private func expandFromHover() {
        guard pointerInside, preferences.showIsland else { return }
        hoverTask?.cancel()
        collapseTask?.cancel()
        // AppKit owns the size animation; a second SwiftUI layout animation moves the header.
        expanded = true
    }
    func collapse() {
        hoverTask?.cancel()
        collapseTask?.cancel()
        expanded = false
    }
    func hover(_ value: Bool) {
        pointerInside = value
        hoverTask?.cancel(); collapseTask?.cancel()
        if value && !expanded {
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }; self?.expandFromHover()
            }
        }
        else if !value {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled, self?.pointerInside == false else { return }; self?.collapse()
            }
        }
    }
    func jump(_ session: Session) {
        collapse()
        guard !session.isDemo else { toast = "这是动效演示；真实会话支持跳转。"; return }
        if let url = SessionNavigation.codexURL(session) {
            if NSWorkspace.shared.open(url) {
                if let delivery = deliveryInbox.pending[session.id]?.session {
                    Task { await viewReader.expectCodexSessionView(delivery) }
                }
            } else { toast = "无法打开 Codex，待检查提示已保留。" }
            return
        }
        if let remote = session.remote {
            if let destination = remote.url, let url = URL(string: destination),
               url.scheme == "https", ["claude.ai", "chatgpt.com", "chat.openai.com"].contains(url.host ?? "") {
                if session.agent == .claude, session.sessionID.range(of: #"^session_[A-Za-z0-9]+$"#, options: .regularExpression) != nil, let native = URL(string: "claude://claude.ai/epitaxy/\(session.sessionID)"),
                   NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") != nil {
                    if !NSWorkspace.shared.open(native) { NSWorkspace.shared.open(url) }
                } else if !NSWorkspace.shared.open(url) { toast = "无法打开远程会话，待检查提示已保留。" }
                return
            }
            if remote.kind == .ssh, let command = SessionNavigation.resumeCommand(session) {
                openTerminalSession(command, session: session)
                return
            }
            toast = "暂时无法定位远程会话，待检查提示已保留。"; return
        }
        if session.agent == .claude, UUID(uuidString: session.sessionID) != nil {
            let address: String
            if let desktopID = claudeDesktopRoutes[session.sessionID], desktopID.range(of: #"^local_[A-Za-z0-9-]+$"#, options: .regularExpression) != nil {
                address = "claude://claude.ai/epitaxy/\(desktopID)"
            } else { address = "claude://resume?session=\(session.sessionID)" }
            if let url = URL(string: address), !NSWorkspace.shared.open(url) { toast = "未能打开 Claude 会话，待检查提示已保留。" }
            return
        }
        if session.agent == .grok, session.sessionID.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil,
           let url = URL(string: "grokbot://app/v1/agent?id=\(session.sessionID)") {
            if !NSWorkspace.shared.open(url) { toast = "没有找到 Grok Bot，请先打开一次 Grok Bot App。" }
        }
    }
    private func openTerminalSession(_ command: String, session: Session) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            toast = "没有找到终端，无法打开这条 SSH 会话。"; return
        }
        do {
            let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Tern/Resume")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let digest = SHA256.hash(data: Data(session.id.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
            let script = folder.appendingPathComponent(digest + ".command")
            // Fixed executable and shell-quoted host/path/ID; no generated agent prompt is sent.
            try ("#!/bin/zsh\nexec " + command + "\n").write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open([script], withApplicationAt: terminal, configuration: .init()) { _, error in
                if error != nil { Task { @MainActor in self.toast = "终端未能打开 SSH 会话，提示已保留。" } }
            }
        } catch { toast = "无法准备 SSH 会话入口：\(error.localizedDescription)" }
    }
    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge]) { granted, _ in
            Task { @MainActor in self.preferences.notificationEnabled = granted; self.toast = granted ? "系统通知已开启" : "请在系统设置 → 通知中允许 Tern。" }
        }
    }
    func demo() {
        demoTask?.cancel(); isDemo = true; latestAlert = nil; demoInbox = DeliveryInbox()
        islandTab = "active"; islandAgent = nil
        sessions = [
            Session(agent: .codex, sessionID: "demo-codex", title: "完成支付页面重构", directory: "~/Projects/Commerce", summary: "正在检查组件状态与测试结果…", state: .running, revision: "demo-1", isDemo: true),
            Session(agent: .claude, sessionID: "demo-claude", title: "审查 API 的错误处理", directory: "~/Projects/Backend", summary: "正在检查边界条件与超时路径…", state: .running, revision: "demo-2", isDemo: true),
            Session(agent: .grok, sessionID: "demo-grok", title: "整理这周的研究资料", summary: "演示摘要：资料已整理为三个主题，并附上来源与待确认问题。", state: .replied, revision: "demo-3", source: "演示数据", isDemo: true),
            Session(agent: .claude, sessionID: "demo-review", title: "确认数据库迁移方案", directory: "~/Projects/Backend", summary: "演示：需要你确认迁移顺序。请返回原会话查看详情。", state: .waiting, revision: "demo-4", isDemo: true)
        ]
        for session in sessions where session.state.shouldAlert { demoInbox.record(session) }
        demoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, !Task.isCancelled, isDemo else { return }
            sessions[0].state = .completed
            sessions[0].summary = "支付页面重构完成。\n\n• 统一表单校验与加载状态\n• 补充 8 个边界测试，全部通过\n• 交付：CheckoutView.swift、PaymentService.swift\n\n以上为动效演示数据。"
            sessions[0].updatedAt = .now
            notify(sessions[0], playAudio: false)
        }
    }
    func endDemo() { demoTask?.cancel(); isDemo = false; sessions = []; latestAlert = nil; demoInbox = DeliveryInbox(); islandTab = "active"; islandAgent = nil; collapse() }
}
