import AppKit
import SwiftUI
import UserNotifications
import Combine
import TernCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let store = IslandStore()
    private var island: IslandPanelController?
    private var dashboard: NSWindow?
    private var statusItem: NSStatusItem?
    private var themeObserver: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        store.openDashboard = { [weak self] in self?.showDashboard() }
        installMenu()
        themeObserver = store.preferences.$theme.removeDuplicates().sink { theme in
            NSApp.applicationIconImage = AppBrandIcon.image(theme: theme)
        }
        island = IslandPanelController(store: store)
        store.start()
        if CommandLine.arguments.contains("--demo") { store.demo() }
        if !CommandLine.arguments.contains("--background") { showDashboard() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showDashboard(); return true }
    @objc func showDashboard() {
        if dashboard == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Tern"
            window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
            window.backgroundColor = NSColor(Palette.background)
            window.contentView = NSHostingView(rootView: DashboardView(store: store, preferences: store.preferences))
            window.isReleasedWhenClosed = false
            window.center(); dashboard = window
        }
        dashboard?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func installMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.inset.filled", accessibilityDescription: "Tern")
        let menu = NSMenu()
        func add(_ title: String, _ selector: Selector, key: String = "") {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key); entry.target = self; menu.addItem(entry)
        }
        add("打开任务中心", #selector(showDashboard), key: "o")
        add("收起刘海", #selector(collapseIsland), key: "i")
        add("静音 / 恢复提醒", #selector(toggleMute), key: "m")
        menu.addItem(.separator())
        add("预览交付动效", #selector(demo))
        add("声音与 HomePod…", #selector(showAudio), key: ",")
        menu.addItem(.separator())
        add("退出 Tern", #selector(quit), key: "q")
        item.menu = menu; statusItem = item
        let main = NSMenu(), app = NSMenuItem(); app.submenu = menu.copy() as? NSMenu; main.addItem(app)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] { editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        edit.submenu = editMenu; main.addItem(edit); NSApp.mainMenu = main
    }
    @objc private func collapseIsland() { store.collapse() }
    @objc private func toggleMute() { store.preferences.muted.toggle() }
    @objc private func demo() { store.demo() }
    @objc private func showAudio() { store.section = "audio"; showDashboard() }
    @objc private func quit() { NSApp.terminate(nil) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .list]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["session"] as? String
        Task { @MainActor in
            if let s = self.store.sessions.first(where: { $0.id == id }) { self.store.jump(s) }
            else { self.showDashboard() }
            completionHandler()
        }
    }
}

@main struct TernApplication {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--inspect") {
            let semaphore = DispatchSemaphore(value: 0)
            Task.detached {
                let (sessions, health) = await SessionMonitor().poll(waitForRemote: true)
                let payload: [String: Any] = ["health": health, "sessions": sessions.count, "sources": Dictionary(grouping: sessions, by: { $0.source }).mapValues(\.count), "remoteUnread": sessions.filter { $0.remote != nil && $0.sourceUnread == true && $0.state.shouldAlert }.count, "states": Dictionary(grouping: sessions, by: { $0.state.rawValue }).mapValues(\.count), "providers": Dictionary(grouping: sessions, by: { $0.agent.rawValue }).mapValues(\.count)]
                if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
                semaphore.signal()
            }
            semaphore.wait(); return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
