import Foundation

public enum StatusBarMode: String, Codable, CaseIterable, Sendable {
    case idle, active
    public var title: String { self == .idle ? "静态" : "有任务" }
}
public enum StatusBarZone: String, Codable, CaseIterable, Sendable {
    case left, center, right
    public var title: String { switch self { case .left: "左侧"; case .center: "中间"; case .right: "右侧" } }
}
public enum StatusBarStyle: String, Codable, CaseIterable, Sendable {
    case minimal, capsules, terminal
    public var title: String { switch self { case .minimal: "简洁"; case .capsules: "胶囊"; case .terminal: "终端" } }
}
public enum StatusBarWidget: String, Codable, CaseIterable, Sendable {
    case matrix, summary, agentLights, reviewCount, sound, runningCount, clock, waveform, sessionTitle
    public var title: String {
        switch self {
        case .matrix: "点阵"; case .summary: "状态描述"; case .agentLights: "Agent 灯"
        case .reviewCount: "待检查数"; case .sound: "声音状态"; case .runningCount: "运行数"
        case .clock: "时钟"; case .waveform: "波形"; case .sessionTitle: "会话标题"
        }
    }
    public var symbol: String {
        switch self {
        case .matrix: "circle.grid.3x3.fill"; case .summary: "text.alignleft"; case .agentLights: "ellipsis"
        case .reviewCount: "tray"; case .sound: "speaker.wave.2"; case .runningCount: "terminal"
        case .clock: "clock"; case .waveform: "waveform"; case .sessionTitle: "text.bubble"
        }
    }
    public var suggestedZone: StatusBarZone {
        switch self { case .matrix, .waveform: .left; case .summary, .sessionTitle: .center; default: .right }
    }
    public var minimumWidth: Double {
        switch self {
        case .matrix, .sound: 18; case .agentLights: 30; case .reviewCount, .runningCount: 34
        case .clock: 40; case .waveform: 26; case .summary: 56; case .sessionTitle: 64
        }
    }
    public var flexible: Bool { self == .summary || self == .sessionTitle }
}

public struct StatusBarProfile: Codable, Equatable, Sendable {
    public var left: [StatusBarWidget]
    public var center: [StatusBarWidget]
    public var right: [StatusBarWidget]
    public var fixedWidth: Double
    public var style: StatusBarStyle
    public init(left: [StatusBarWidget], center: [StatusBarWidget], right: [StatusBarWidget], fixedWidth: Double, style: StatusBarStyle) {
        self.left = left; self.center = center; self.right = right; self.fixedWidth = fixedWidth; self.style = style
    }
    public static let idle = Self(left: [.matrix], center: [], right: [.agentLights, .reviewCount, .sound], fixedWidth: 200, style: .minimal)
    public static let active = Self(left: [.matrix], center: [.summary], right: [.agentLights, .reviewCount, .sound], fixedWidth: 300, style: .capsules)
    public var widgets: [StatusBarWidget] { left + center + right }
    public func items(in zone: StatusBarZone) -> [StatusBarWidget] {
        switch zone { case .left: left; case .center: center; case .right: right }
    }
    public mutating func setItems(_ items: [StatusBarWidget], in zone: StatusBarZone) {
        switch zone { case .left: left = items; case .center: center = items; case .right: right = items }
    }
    public mutating func remove(_ widget: StatusBarWidget) {
        left.removeAll { $0 == widget }; center.removeAll { $0 == widget }; right.removeAll { $0 == widget }
    }
    /// A drag is a move, including between zones; failed drops leave the profile untouched.
    @discardableResult public mutating func place(_ widget: StatusBarWidget, in zone: StatusBarZone, before: StatusBarWidget? = nil) -> Bool {
        if before == widget { return true }
        var next = self; next.remove(widget)
        var items = next.items(in: zone)
        let index = before.flatMap { items.firstIndex(of: $0) } ?? items.count
        items.insert(widget, at: index); next.setItems(items, in: zone)
        guard next.fits else { return false }
        self = next; return true
    }
    public static func minimumWidth(of widgets: [StatusBarWidget]) -> Double {
        widgets.reduce(0) { $0 + $1.minimumWidth } + Double(max(0, widgets.count - 1)) * 6
    }
    public var dense: Bool { fixedWidth < 180 }
    public var widgetSpacing: Double { dense ? 3 : 6 }
    public var laneSpacing: Double { dense ? 4 : 8 }
    public var horizontalPadding: Double { dense ? 12 : 20 }
    public func width(of widget: StatusBarWidget) -> Double {
        guard dense else { return widget.minimumWidth }
        switch widget {
        case .matrix: return 14; case .sound: return 12; case .agentLights: return 24
        case .reviewCount, .runningCount: return 26; case .clock: return 34; case .waveform: return 20
        case .summary: return 40; case .sessionTitle: return 48
        }
    }
    public func contentWidth(of widgets: [StatusBarWidget]) -> Double {
        widgets.reduce(0) { $0 + width(of: $1) } + Double(max(0, widgets.count - 1)) * widgetSpacing
    }
    public var minimumContentWidth: Double {
        contentWidth(of: left) + contentWidth(of: center) + contentWidth(of: right) + 2 * horizontalPadding + 2 * laneSpacing
    }
    public var fits: Bool { minimumContentWidth <= fixedWidth }
    public func normalized(for mode: StatusBarMode) -> Self {
        var result = self; var seen: Set<StatusBarWidget> = []
        for zone in StatusBarZone.allCases {
            result.setItems(items(in: zone).filter { seen.insert($0).inserted }, in: zone)
        }
        let minimum = mode == .idle ? 120.0 : 240.0
        let maximum = mode == .idle ? 240.0 : 360.0
        result.fixedWidth = fixedWidth.isFinite ? min(maximum, max(minimum, fixedWidth)) : (mode == .idle ? 200 : 300)
        // Repair invalid saved layouts without ever consulting live text or counts.
        while !result.fits, let last = result.widgets.last { result.remove(last) }
        return result
    }
    public func requiredWingWidth() -> Double {
        let leftContent = Self.minimumWidth(of: left) + Self.minimumWidth(of: center) + (left.isEmpty || center.isEmpty ? 0 : 8)
        return 2 * (max(leftContent, Self.minimumWidth(of: right)) + 24)
    }
    private enum CodingKeys: String, CodingKey { case left, center, right, fixedWidth, style }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        left = (try c.decodeIfPresent([String].self, forKey: .left) ?? []).compactMap(StatusBarWidget.init(rawValue:))
        center = (try c.decodeIfPresent([String].self, forKey: .center) ?? []).compactMap(StatusBarWidget.init(rawValue:))
        right = (try c.decodeIfPresent([String].self, forKey: .right) ?? []).compactMap(StatusBarWidget.init(rawValue:))
        fixedWidth = try c.decodeIfPresent(Double.self, forKey: .fixedWidth) ?? 200
        style = (try c.decodeIfPresent(String.self, forKey: .style)).flatMap(StatusBarStyle.init(rawValue:)) ?? .minimal
    }
}

public struct StatusBarConfiguration: Codable, Equatable, Sendable {
    public var idle: StatusBarProfile
    public var active: StatusBarProfile
    public init(idle: StatusBarProfile = .idle, active: StatusBarProfile = .active) { self.idle = idle; self.active = active }
    public static let defaults = Self()
    public func profile(for mode: StatusBarMode) -> StatusBarProfile { mode == .idle ? idle : active }
    public mutating func set(_ profile: StatusBarProfile, for mode: StatusBarMode) {
        if mode == .idle { idle = profile } else { active = profile }
        self = normalized()
    }
    public func normalized() -> Self {
        var result = self
        result.idle = idle.normalized(for: .idle); result.active = active.normalized(for: .active)
        return result
    }
    /// Width depends only on saved configuration and the physical display, never on strings/counts.
    public func resolvedWidth(for mode: StatusBarMode, physicalNotchWidth: Double = 0) -> Double {
        let config = normalized()
        let gap = max(0, physicalNotchWidth)
        let idleWidth = gap > 0 ? max(config.idle.fixedWidth, config.idle.requiredWingWidth()) : config.idle.fixedWidth
        let activeWidth = gap > 0 ? max(config.active.fixedWidth, config.active.requiredWingWidth()) : config.active.fixedWidth
        return gap + (mode == .idle ? idleWidth : activeWidth)
    }
}
