import SwiftUI
import TernCore

struct CompactBarData {
    var runningCount: Int
    var reviewCount: Int
    var agentRunning: [Agent: Int]
    var reviewAgents: Set<Agent>
    var enabledAgents: Set<Agent>
    var muted: Bool
    var summary: String
    var sessionTitle: String
    var state: SessionState
    var focusedAgent: Agent?
    var isPreview = false

    @MainActor static func live(_ store: IslandStore) -> Self {
        Self(runningCount: store.running.count, reviewCount: store.pendingSessions.count,
             agentRunning: Dictionary(grouping: store.running, by: \.agent).mapValues(\.count),
             reviewAgents: Set(store.pendingSessions.map(\.agent)), enabledAgents: store.preferences.enabledAgents,
             muted: store.preferences.muted, summary: store.compactLabel,
             sessionTitle: store.focused?.displayTitle ?? "暂无任务",
             state: store.unreadAlert?.state ?? (store.running.isEmpty ? .unknown : .running),
             focusedAgent: store.focused?.agent)
    }
    static func preview(_ mode: StatusBarMode) -> Self {
        Self(runningCount: mode == .idle ? 0 : 3, reviewCount: mode == .idle ? 1 : 0,
             agentRunning: mode == .idle ? [:] : [.codex: 2, .claude: 1],
             reviewAgents: mode == .idle ? [.grok] : [], enabledAgents: Set(Agent.allCases), muted: false,
             summary: mode == .idle ? "1 项待检查" : "3 个任务执行中", sessionTitle: mode == .idle ? "资料整理已完成" : "重构支付页面并检查异步状态处理",
             state: mode == .idle ? .completed : .running, focusedAgent: mode == .idle ? .grok : .codex, isPreview: true)
    }
    static func counter(_ value: Int) -> String { value > 99 ? "99+" : String(max(0, value)) }
}

/// Shared by the real notch and the editor. All modules have bounded, data-independent slots.
struct CompactStatusBar: View {
    let profile: StatusBarProfile
    let data: CompactBarData
    let width: CGFloat
    var physicalNotchWidth: CGFloat = 0
    var height: CGFloat = 32
    @Environment(\.islandTheme) private var theme

    var body: some View {
        Group {
            if physicalNotchWidth > 0 {
                let wing = max(0, (width - physicalNotchWidth) / 2)
                HStack(spacing: 0) {
                    lane(profile.left + profile.center, width: max(0, wing - 24), alignment: .leading)
                        .padding(.leading, 18).padding(.trailing, 6).frame(width: wing)
                    Color.clear.frame(width: physicalNotchWidth)
                    lane(profile.right, width: max(0, wing - 24), alignment: .trailing)
                        .padding(.leading, 6).padding(.trailing, 18).frame(width: wing)
                }
            } else {
                let plan = laneWidths
                HStack(spacing: profile.laneSpacing) {
                    lane(profile.left, width: plan.0, alignment: .leading)
                    lane(profile.center, width: plan.1, alignment: .center)
                    lane(profile.right, width: plan.2, alignment: .trailing)
                }.padding(.horizontal, profile.horizontalPadding)
            }
        }.frame(width: max(1, width), height: height).clipped()
    }
    private var laneWidths: (CGFloat, CGFloat, CGFloat) {
        var left = profile.contentWidth(of: profile.left)
        var center = profile.contentWidth(of: profile.center)
        var right = profile.contentWidth(of: profile.right)
        let extra = max(0, width - 2 * profile.horizontalPadding - 2 * profile.laneSpacing - left - center - right)
        if profile.center.contains(where: \.flexible) { center += extra }
        else {
            let outerFlex = [profile.left.contains(where: \.flexible), profile.right.contains(where: \.flexible)].filter { $0 }.count
            if outerFlex > 0 {
                if profile.left.contains(where: \.flexible) { left += extra / Double(outerFlex) }
                if profile.right.contains(where: \.flexible) { right += extra / Double(outerFlex) }
            } else { center += extra }
        }
        return (left, center, right)
    }
    private func lane(_ widgets: [StatusBarWidget], width: CGFloat, alignment: Alignment) -> some View {
        let minimum = profile.contentWidth(of: widgets)
        let flexibleCount = widgets.filter(\.flexible).count
        let extra = flexibleCount == 0 ? 0 : max(0, width - minimum) / Double(flexibleCount)
        return HStack(spacing: profile.widgetSpacing) {
            ForEach(widgets, id: \.self) { widget in
                module(widget)
                    .frame(width: profile.width(of: widget) + (widget.flexible ? extra : 0), height: 23)
                    .background(moduleBackground(widget), in: RoundedRectangle(cornerRadius: 5))
                    .clipped()
            }
        }.frame(width: max(0, width), alignment: alignment).clipped()
    }
    private func moduleBackground(_ widget: StatusBarWidget) -> Color {
        guard profile.style == .capsules, ![.matrix, .agentLights, .waveform].contains(widget) else { return .clear }
        return widget.flexible ? theme.accent.opacity(0.11) : Color.white.opacity(0.065)
    }
    @ViewBuilder private func module(_ widget: StatusBarWidget) -> some View {
        switch widget {
        case .matrix:
            SignalGlyph(state: data.runningCount > 0 ? .running : .unknown, size: profile.dense ? 14 : 15,
                        agents: Agent.allCases.filter { (data.agentRunning[$0] ?? 0) > 0 })
                .accessibilityLabel(data.runningCount > 0 ? "运行中的 Agent 点阵" : "空闲点阵")
        case .summary:
            let value = profile.style == .terminal
                ? (data.runningCount > 0 || data.reviewCount > 0 ? "RUN \(CompactBarData.counter(data.runningCount)) · CHECK \(CompactBarData.counter(data.reviewCount))" : "IDLE")
                : (data.summary.isEmpty ? "空闲" : data.summary)
            label(value).foregroundStyle(profile.style == .capsules ? theme.text : Palette.paper.opacity(0.85))
                .help(value)
        case .sessionTitle:
            label(data.sessionTitle).foregroundStyle(Palette.paper.opacity(0.75)).help(data.sessionTitle)
        case .agentLights:
            HStack(spacing: profile.dense ? 3 : 4) {
                ForEach(Agent.allCases, id: \.self) { agent in
                    RoundedRectangle(cornerRadius: profile.style == .terminal ? 0.5 : 3)
                        .fill(agent.tint.opacity(!data.enabledAgents.contains(agent) ? 0.16 : (data.agentRunning[agent] ?? 0) > 0 || data.reviewAgents.contains(agent) ? 1 : 0.4))
                        .frame(width: 6, height: profile.style == .capsules ? 9 : 6)
                        .help("\(agent.name) · \(data.agentRunning[agent] ?? 0) 个运行中")
                }
            }.accessibilityLabel("Codex、Claude Code、Grok Bot 指示灯")
        case .reviewCount:
            counter(data.reviewCount, icon: "tray", color: data.reviewCount > 0 ? Palette.green : Palette.muted)
                .accessibilityLabel("\(data.reviewCount) 项待检查")
        case .sound:
            Image(systemName: data.muted ? "speaker.slash" : "speaker.wave.2")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                .accessibilityLabel(data.muted ? "提醒已静音" : "提醒声音开启")
        case .runningCount:
            counter(data.runningCount, icon: "terminal", color: data.runningCount > 0 ? Palette.blue : Palette.muted)
                .accessibilityLabel("\(data.runningCount) 个运行中")
        case .clock:
            if data.isPreview { label("12:34").foregroundStyle(Palette.muted) }
            else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(context.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .font(.system(size: 10, weight: .medium, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
        case .waveform:
            Waveform(color: data.focusedAgent?.tint ?? theme.text, active: data.runningCount > 0)
        }
    }
    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium, design: profile.style == .terminal ? .monospaced : .default))
            .monospacedDigit().lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func counter(_ value: Int, icon: String, color: Color) -> some View {
        HStack(spacing: profile.dense ? 2 : 3) {
            Image(systemName: icon).font(.system(size: profile.dense ? 7 : 9))
            Text(CompactBarData.counter(value)).font(.system(size: profile.dense ? 8 : 10, weight: .medium, design: .monospaced))
                .monospacedDigit().lineLimit(1).frame(width: profile.dense ? 16 : 19, alignment: .trailing)
        }.foregroundStyle(color)
    }
}
