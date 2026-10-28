import SwiftUI
import TernCore

struct DashboardView: View {
    @ObservedObject var store: IslandStore
    @ObservedObject var preferences: Preferences
    @State private var filter: Agent?
    @State private var search = ""
    private var theme: AccentTheme { preferences.theme }
    private var filtered: [Session] {
        let list = store.section == "history" ? store.historySessions : store.activeSessions
        return SessionPresentation.ordered(list, prioritizeActivity: store.section != "history").filter { (filter == nil || $0.agent == filter) && (search.isEmpty || ($0.displayTitle + $0.summary).localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 180)
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(spacing: 0) {
                topbar
                Rectangle().fill(Palette.line).frame(height: 1)
                if store.section == "audio" { AudioSettingsView(preferences: preferences, audio: store.audio) }
                else if store.section == "connections" { connections }
                else if store.section == "appearance" { AppearanceView(store: store, preferences: preferences) }
                else if store.section == "barLayout" { StatusBarEditor(store: store, preferences: preferences) }
                else { overview }
                if let toast = store.toast {
                    HStack { Image(systemName: "info.circle"); Text(toast); Spacer(); Button { store.toast = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                        .font(.system(size: 12)).padding(13).background(theme.subtle)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Palette.background).foregroundStyle(.white).preferredColorScheme(.dark)
            .environment(\.islandTheme, theme).tint(theme.accent)
            .frame(minWidth: 860, minHeight: 620)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                TernMark().fill(theme.accent).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tern").font(.system(size: 13, weight: .semibold))
                    Text("QUIETLY IN THE LOOP").font(.system(size: 7, weight: .medium, design: .monospaced)).tracking(1.3).foregroundStyle(Palette.muted)
                }
            }.padding(.bottom, 28)
            Text("WORKSPACE").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.6).foregroundStyle(Palette.muted).padding(.leading, 10).padding(.bottom, 12)
            nav("active", "当前会话", "bolt.horizontal")
            nav("history", "历史会话", "clock.arrow.circlepath")
            Spacer().frame(height: 25)
            Text("PREFERENCES").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.6).foregroundStyle(Palette.muted).padding(.leading, 10).padding(.bottom, 12)
            nav("appearance", "外观与刘海", "capsule")
            nav("barLayout", "状态栏布局", "slider.horizontal.3")
            nav("audio", "声音与播报", "homepod")
            nav("connections", "接入与通知", "point.3.connected.trianglepath.dotted")
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                HStack { Image(systemName: preferences.muted ? "bell.slash" : "antenna.radiowaves.left.and.right").foregroundStyle(Palette.muted); Text(preferences.muted ? "安静模式" : "正在为你留意").font(.system(size: 11, weight: .medium)) }
                Text("Codex · Claude · Grok").font(.system(size: 9)).foregroundStyle(Palette.muted)
                Button { preferences.muted.toggle() } label: { Label(preferences.muted ? "恢复提醒" : "暂停提醒", systemImage: preferences.muted ? "bell" : "bell.slash") }.buttonStyle(IslandButtonStyle())
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            HStack { Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev") · TERN"); Spacer(); Image(systemName: "lock.shield") }.font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(Palette.muted.opacity(0.65)).padding(.top, 18)
        }.padding(.horizontal, 15).padding(.top, 34).padding(.bottom, 20).background(Color.black.opacity(0.16))
    }
    private func nav(_ id: String, _ name: String, _ icon: String) -> some View {
        Button { store.section = id } label: {
            HStack(spacing: 11) { Image(systemName: icon).font(.system(size: 13)).frame(width: 18); Text(name).font(.system(size: 12, weight: store.section == id ? .semibold : .regular)); Spacer(); if id == "active" || id == "history" { Text("\(id == "active" ? store.activeSessions.count : store.historySessions.count)").font(.system(size: 10)).foregroundStyle(Palette.muted) } }
                .foregroundStyle(store.section == id ? theme.text : Color.white.opacity(0.55)).padding(.horizontal, 11).padding(.vertical, 11)
                .background(store.section == id ? theme.subtle : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).padding(.bottom, 4)
    }
    private var topbar: some View {
        HStack {
            Text((["active": "当前会话", "appearance": "外观与刘海", "barLayout": "状态栏布局", "history": "历史会话", "audio": "声音与 HomePod", "connections": "接入与通知"][store.section] ?? "")).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            Spacer()
            if store.isDemo {
                Text("演示模式").font(.system(size: 10)).foregroundStyle(.orange)
                Button("返回实时") { store.endDemo() }.buttonStyle(IslandButtonStyle())
            } else {
                Label("LIVE", systemImage: "antenna.radiowaves.left.and.right").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.muted)
                Button { store.demo() } label: { Label("预览动效", systemImage: "play.circle") }.buttonStyle(IslandButtonStyle()).padding(.leading, 10)
            }
        }.padding(.horizontal, 28).frame(height: 52)
    }
    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack(spacing: 13) {
                    SignalGlyph(state: store.running.isEmpty ? .unknown : .running, size: 24, agents: store.runningAgents)
                        .frame(width: 44, height: 44).background(.black, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.section == "history" ? "历史会话" : "当前会话").font(.system(size: 23, weight: .semibold))
                        Text(store.section == "history" ? "已结束的会话，点击返回原应用。" : "正在执行的任务，以及还没查看的结果。")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    if store.section != "history", !store.pendingSessions.isEmpty {
                        Label("\(store.pendingSessions.count) 待检查", systemImage: "circle.fill")
                            .font(.system(size: 10)).foregroundStyle(Palette.green)
                    }
                }.padding(.vertical, 5)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("点击会话，直接返回 Agent").font(.system(size: 15, weight: .semibold))
                        Spacer()
                        HStack(spacing: 5) { Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted); TextField("搜索会话", text: $search).textFieldStyle(.plain).frame(width: 112) }.font(.system(size: 11)).padding(8).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                    }
                    HStack(spacing: 7) {
                        filterButton(nil, "全部")
                        ForEach(Agent.allCases, id: \.self) { filterButton($0, $0.name) }
                        Spacer()
                        Text("最近 7 天").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                    if filtered.isEmpty { emptyState }
                    else {
                        VStack(spacing: 0) {
                            ForEach(Array(filtered.prefix(50).enumerated()), id: \.element.id) { index, session in
                                sessionRow(session)
                                if index < min(filtered.count, 50) - 1 { Rectangle().fill(Palette.line).frame(height: 1).padding(.leading, 66) }
                            }
                        }.background(Palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield").foregroundStyle(Palette.muted)
                    Text("摘要保留在你的 Mac 上 · 仅在出现新结果时提醒").foregroundStyle(Palette.muted)
                    Spacer()
                }.font(.system(size: 10)).padding(.top, 2)
            }.padding(28)
        }
    }
    private func filterButton(_ agent: Agent?, _ title: String) -> some View {
        Button { filter = agent } label: { Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(filter == agent ? theme.text : Palette.muted).padding(.horizontal, 12).padding(.vertical, 7).background(filter == agent ? theme.subtle : .clear, in: Capsule()) }.buttonStyle(.plain)
    }
    private func sessionRow(_ s: Session) -> some View {
        Button { store.jump(s) } label: {
            HStack(alignment: .center, spacing: 13) {
                Group {
                    if store.unreadSessionIDs.contains(s.id) { Circle().fill(Palette.green).frame(width: 6, height: 6).accessibilityLabel("待检查") }
                    else if s.state == .running { SignalGlyph(state: .running, size: 13, agents: [s.agent]) }
                    else { Image(systemName: s.state.symbol).font(.system(size: 11)).foregroundStyle(Palette.muted) }
                }.frame(width: 18)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(s.displayTitle).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.paper).lineLimit(1)
                        Spacer()
                        AgentBadge(agent: s.agent)
                        Text(SessionPresentation.relativeTime(s.updatedAt)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted).frame(width: 30, alignment: .trailing)
                    }
                    Text(s.excerpt.isEmpty ? "等待交付内容…" : s.excerpt).font(.system(size: 10.5)).foregroundStyle(Palette.muted).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(SessionPresentation.projectName(s)).foregroundStyle(Palette.muted.opacity(0.7))
                        Text("·").foregroundStyle(Palette.muted)
                        Text(store.unreadSessionIDs.contains(s.id) ? "待检查" : s.state.label).foregroundStyle(store.unreadSessionIDs.contains(s.id) ? Palette.green : s.state.tint)
                        if s.isDemo { Text("· 演示").foregroundStyle(.orange) }
                    }.font(.system(size: 9))
                }
                Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 15).padding(.vertical, 13).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray").font(.system(size: 29, weight: .ultraLight)).foregroundStyle(theme.text)
            Text(search.isEmpty ? (store.section == "history" ? "还没有历史会话" : "当前没有待处理的会话") : "没有匹配的会话").font(.system(size: 15, weight: .medium))
            Text(store.section == "history" ? "不再运行、没有待检查提示的会话会收在这里。" : "Agent 开始执行或有未查看结果时，会出现在这里。").font(.system(size: 12)).lineSpacing(4).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
            Button("预览一次交付") { store.demo() }.buttonStyle(IslandButtonStyle())
        }.frame(maxWidth: .infinity).padding(.vertical, 40).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
    }
    private var connections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("在后台，保持连接。").font(.system(size: 25, weight: .semibold))
                Text("自动发现本地记录和 Agent 已配置的 SSH 主机；云端来源分别显示连接状态。").font(.system(size: 12)).foregroundStyle(Palette.muted)
                ForEach(Agent.allCases, id: \.self) { agent in
                    PanelCard {
                        VStack(alignment: .leading, spacing: 13) {
                            HStack(spacing: 12) { AgentMark(agent: agent); VStack(alignment: .leading, spacing: 5) { Text(agent.name).font(.system(size: 14, weight: .medium)); Text(store.health[agent.rawValue] ?? "正在检查…").font(.system(size: 11)).foregroundStyle(Palette.muted) }; Spacer(); Toggle("监听 \(agent.name)", isOn: Binding(get: { preferences.enabledAgents.contains(agent) }, set: { if $0 { preferences.enabledAgents.insert(agent) } else { preferences.enabledAgents.remove(agent) } })).labelsHidden().toggleStyle(.switch).tint(theme.accent) }
                            Text(agent == .codex ? "识别开始、完成与中断事件；点击后返回原来的 Codex 会话。" : agent == .claude ? "读取 Claude Code 会话记录；桌面会话可打开 Claude，终端会话提供恢复命令。" : "观察 Grok Bot 的桌面缓存。支持回复摘要与打开 App；缓存格式变化时可能需要适配。")
                                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                            Text(store.viewHealth[agent.rawValue] ?? "正在检查原应用的查看回执…")
                                .font(.system(size: 10)).foregroundStyle(theme.text)
                        }
                    }
                }
                PanelCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("远程会话").font(.system(size: 14, weight: .medium))
                        ForEach(store.health.keys.filter { !Agent.allCases.map(\.rawValue).contains($0) }.sorted(), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(key == "claude-remote" ? "Claude 云端 / Remote Control" : key == "codex-cloud" ? "Codex 云端" : key.replacingOccurrences(of: "ssh:", with: "SSH · "))
                                    .font(.system(size: 11, weight: .medium))
                                Text(store.health[key] ?? "正在连接…").font(.system(size: 11)).foregroundStyle(Palette.muted).textSelection(.enabled)
                            }
                        }
                        Text("SSH 每 15 秒同步，不安装远程程序。Claude 云端和 Grok 依赖原 App 写入缓存；原 App 关闭或缓存停止更新时无法保证实时提醒。")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                    }
                }
                PanelCard {
                    VStack(spacing: 19) {
                        Toggle("在屏幕顶部显示刘海", isOn: $preferences.showIsland)
                        HStack { VStack(alignment: .leading, spacing: 5) { Text("macOS 系统通知"); Text(preferences.notificationEnabled ? "已开启。专注模式可能会暂时隐藏通知。" : "点击开启时，由系统请求通知权限。").font(.system(size: 10)).foregroundStyle(Palette.muted) }; Spacer(); Button(preferences.notificationEnabled ? "关闭" : "开启通知") { if preferences.notificationEnabled { preferences.notificationEnabled = false } else { store.requestNotifications() } }.buttonStyle(IslandButtonStyle()) }
                    }.font(.system(size: 12)).toggleStyle(.switch).tint(theme.accent)
                }
                Text("睡眠期间无法监听；唤醒后同步新结果。超过 30 分钟没有活动的运行记录显示为“状态待确认”。").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
                Text("待检查提示以原 App 的具体会话回执为准。打开其他会话、预览 Island 摘要或仅发起跳转都不会直接清除。没有可靠回执时保留提示；终端版 Claude 暂无自动查看确认。").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
            }.padding(28)
        }
    }
}
