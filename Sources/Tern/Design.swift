import SwiftUI
import TernCore

enum Palette {
    static let background = Color(red: 0.045, green: 0.046, blue: 0.051)
    static let surface = Color(red: 0.075, green: 0.077, blue: 0.084)
    static let line = Color.white.opacity(0.075)
    static let green = Color(red: 0.48, green: 0.81, blue: 0.58)
    static let paper = Color(red: 0.94, green: 0.93, blue: 0.88)
    static let muted = Color(red: 0.53, green: 0.54, blue: 0.57)
    static let blue = Color(red: 0.43, green: 0.65, blue: 1)
}
extension Agent {
    var abbreviation: String { switch self { case .codex: "CX"; case .claude: "CC"; case .grok: "GB" } }
    var tintHex: UInt32 { switch self { case .codex: 0x7A96F9; case .claude: 0xD97757; case .grok: 0xFFFFFF } }
    var tint: Color { Color(rgbHex: tintHex) }
}
extension SessionState {
    var tint: Color { switch self { case .running: Color(red: 0.57, green: 0.76, blue: 1); case .completed, .replied: Palette.muted; case .waiting: .orange; case .failed: .red; default: Palette.muted } }
    var symbol: String { switch self { case .running: "circle.dotted"; case .completed: "checkmark.circle.fill"; case .replied: "bubble.left.fill"; case .waiting: "hand.raised.fill"; case .failed: "exclamationmark.circle.fill"; case .interrupted: "stop.circle"; case .unknown: "questionmark.circle" } }
}

struct AgentMark: View {
    let agent: Agent
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: agent.symbol).font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(agent.tint).frame(width: size, height: size)
            .background(agent.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.29))
            .overlay(RoundedRectangle(cornerRadius: size * 0.29).strokeBorder(agent.tint.opacity(0.13)))
    }
}
struct StatusPill: View {
    let state: SessionState
    var body: some View {
        HStack(spacing: 5) { Circle().fill(state.tint).frame(width: 5, height: 5); Text(state.label).font(.system(size: 10, weight: .medium)) }
            .foregroundStyle(state.tint).padding(.horizontal, 9).padding(.vertical, 5)
            .background(state.tint.opacity(0.09), in: Capsule())
    }
}
struct Waveform: View {
    var color: Color = Palette.muted
    var active = true
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120, paused: !active || reduceMotion)) { context in
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule().fill(color).frame(width: 3, height: active ? 5 + 13 * abs(sin(context.date.timeIntervalSinceReferenceDate * 3.2 + Double(i) * 0.8)) : 4)
                }
            }.frame(width: 27, height: 22)
        }.accessibilityLabel(active ? "正在运行" : "空闲")
    }
}
struct IslandButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.islandTheme) private var theme
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(prominent ? theme.ink : hovered ? theme.text : Color.white.opacity(0.85))
            .background(prominent ? (configuration.isPressed ? theme.pressed : hovered ? theme.accent : Palette.paper) : Color.white.opacity(configuration.isPressed ? 0.12 : 0.065), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(hovered && !prominent ? theme.border : .clear))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovered = $0 }
    }
}
struct PanelCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line)) }
}

struct AgentBadge: View {
    let agent: Agent
    var compact = false
    var body: some View {
        Text(compact ? agent.abbreviation : agent.name)
            .font(.system(size: 9, weight: .medium, design: compact ? .monospaced : .default))
            .foregroundStyle(agent.tint)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(agent.tint.opacity(0.085), in: RoundedRectangle(cornerRadius: 4))
            .fixedSize().accessibilityLabel(agent.name)
    }
}

struct TinyIconButton: View {
    let icon: String
    let label: String
    var active = false
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.islandTheme) private var theme
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .medium))
                .foregroundStyle(active || hovered ? theme.text : Color.white.opacity(0.44))
                .frame(width: 27, height: 25)
                .background(active ? theme.subtle : Color.white.opacity(hovered ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).help(label).accessibilityLabel(label).onHover { hovered = $0 }
    }
}

/// Small provider-colored streams, rendered on the display animation timeline.
struct SignalGlyph: View {
    var state: SessionState = .running
    var size: CGFloat = 18
    var tint: Color?
    var agents: [Agent] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var active: Bool { !agents.isEmpty || state == .running }
    private var colors: [Color] { agents.isEmpty ? [tint ?? Palette.muted] : agents.map(\.tint) }
    var body: some View {
        TimelineView(.animation(minimumInterval: active ? 1.0 / 120 : 1.0 / 30, paused: reduceMotion)) { time in
            Canvas { context, canvas in
                let cell = canvas.width / 9
                let phase = reduceMotion ? 2.5 : time.date.timeIntervalSinceReferenceDate
                for column in 0..<5 {
                    for row in 0..<5 {
                        let sample = SignalPattern.cell(column: column, row: row, time: phase, providerCount: active ? colors.count : 0)
                        let rect = CGRect(x: CGFloat(column) * cell * 2, y: CGFloat(row) * cell * 2, width: cell, height: cell)
                        context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.22), with: .color(colors[sample.providerIndex].opacity(sample.opacity)))
                    }
                }
            }
        }.frame(width: size, height: size).accessibilityLabel(active ? agents.map(\.name).joined(separator: "、") + "运行中" : "空闲点阵")
    }
}
