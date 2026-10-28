import AppKit
import SwiftUI
import Combine
import QuartzCore
import TernCore

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // A notch overlay intentionally occupies the menu-bar area, outside visibleFrame.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// The native window is a stable canvas during morphing; only the visible island is interactive.
private final class IslandHostingView: NSHostingView<NotchView> {
    var hoverChanged: ((Bool) -> Void)?
    var visibleIslandSize = CGSize(width: 248, height: 32)
    private var pointerInside = false
    private var hoverTrackingArea: NSTrackingArea?
    private var islandBounds: NSRect {
        NSRect(x: (bounds.width - visibleIslandSize.width) / 2,
               y: isFlipped ? 0 : bounds.height - visibleIslandSize.height,
               width: visibleIslandSize.width, height: visibleIslandSize.height)
    }
    override func updateTrackingAreas() {
        if hoverTrackingArea == nil {
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
            addTrackingArea(area); hoverTrackingArea = area
        }
        super.updateTrackingAreas()
    }
    private func updateHover(at windowPoint: NSPoint) {
        let inside = islandBounds.contains(convert(windowPoint, from: nil))
        guard inside != pointerInside else { return }
        pointerInside = inside; hoverChanged?(inside)
    }
    func refreshHoverRegion() {
        // A status-width change must not manufacture a hover entrance under a stationary pointer.
        // Geometry may end an existing hover; only native pointer events may begin one.
        if pointerInside, let window { updateHover(at: window.mouseLocationOutsideOfEventStream) }
    }
    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea === hoverTrackingArea { updateHover(at: event.locationInWindow) }
        else { super.mouseEntered(with: event) }
    }
    override func mouseExited(with event: NSEvent) {
        if event.trackingArea === hoverTrackingArea {
            if pointerInside { pointerInside = false; hoverChanged?(false) }
        } else { super.mouseExited(with: event) }
    }
    override func mouseMoved(with event: NSEvent) {
        updateHover(at: event.locationInWindow)
        super.mouseMoved(with: event)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard islandBounds.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }
}

@MainActor final class IslandPanelController {
    let panel: NSPanel
    private let store: IslandStore
    private let motion = IslandMotion()
    private weak var hostingView: IslandHostingView?
    private var subscriptions = Set<AnyCancellable>()
    private var positioningScheduled = false
    private var morph: IslandMorph?
    private var targetFrame: NSRect?
    private var targetExpanded = false
    private var displayLink: CADisplayLink?
    private let displayTarget = IslandDisplayLinkTarget()
    private var lastTimestamp: CFTimeInterval?
    private var screen: NSScreen? { NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first }
    init(store: IslandStore) {
        self.store = store
        panel = FloatingPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.title = "Tern · 刘海"
        let hosting = IslandHostingView(rootView: NotchView(store: store, preferences: store.preferences, motion: motion))
        hosting.hoverChanged = { [weak store] inside in store?.hover(inside) }
        hosting.sizingOptions = []
        panel.contentView = hosting; hostingView = hosting
        displayTarget.tick = { [weak self] link in self?.animate(link) }
        store.objectWillChange.sink { [weak self] _ in self?.schedulePosition() }.store(in: &subscriptions)
        store.preferences.objectWillChange.sink { [weak self] _ in self?.schedulePosition() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in
            self?.stopDisplayLink(); self?.position(animated: false)
        }.store(in: &subscriptions)
        position(animated: false)
    }
    private func schedulePosition() {
        guard !positioningScheduled else { return }
        positioningScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            positioningScheduled = false; position(animated: true)
        }
    }
    private func position(animated: Bool) {
        guard let screen else { return }
        let notch = screen.safeAreaInsets.top > 0
        let physicalNotchWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            physicalNotchWidth = max(0, right.minX - left.maxX)
        } else { physicalNotchWidth = 0 }
        let width = min(screen.frame.width - 40, CompactIslandLayout.width(mode: store.statusBarMode, physicalNotchWidth: physicalNotchWidth, configuration: store.preferences.statusBar))
        if store.physicalNotchWidth != physicalNotchWidth { store.physicalNotchWidth = physicalNotchWidth }
        let inset = notch ? max(34, screen.safeAreaInsets.top) : 32
        if store.hasNotch != notch { store.hasNotch = notch }
        if store.compactWidth != width { store.compactWidth = width }
        if store.topInset != inset { store.topInset = inset }
        let expandedSize = CGSize(width: min(max(610, width), screen.frame.width - 40), height: min(inset + store.islandBodyHeight, min(520, screen.frame.height * 0.72)))
        let size = store.expanded ? expandedSize : CGSize(width: width, height: inset)
        let top = screen.frame.maxY - ((notch || store.dockToEdge) ? 0 : 9)
        let frame = NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
        motion.prepare(expandedSize: expandedSize, expanded: store.expanded)
        resize(to: frame, animated: animated && store.preferences.showIsland)
        if store.preferences.showIsland {
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible { panel.orderOut(nil) }
    }
    private func resize(to frame: NSRect, animated: Bool) {
        guard targetFrame != frame || targetExpanded != store.expanded || !animated else { return }
        targetFrame = frame; targetExpanded = store.expanded
        if morph == nil { morph = IslandMorph(size: frame.size, expanded: store.expanded) }
        morph?.retarget(size: frame.size, expanded: store.expanded)
        guard animated, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            stopDisplayLink(); morph?.finish()
            panel.setFrame(frame, display: true)
            present(); return
        }
        // Reserve a fixed canvas once. Text keeps its final layout while the clipping surface morphs.
        let canvas = CGSize(width: max(panel.frame.width, frame.width, motion.expandedSize.width),
                            height: max(panel.frame.height, frame.height, motion.expandedSize.height))
        let canvasFrame = CGRect(x: frame.midX - canvas.width / 2, y: frame.maxY - canvas.height, width: canvas.width, height: canvas.height)
        if panel.frame != canvasFrame { panel.setFrame(canvasFrame, display: true) }
        guard displayLink == nil else { return } // Retarget the current springs without resetting velocity.
        let link = panel.displayLink(target: displayTarget, selector: #selector(IslandDisplayLinkTarget.displayTick(_:)))
        let maximum = Float(max(30, panel.screen?.maximumFramesPerSecond ?? 60))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
        lastTimestamp = CACurrentMediaTime()
        displayLink = link
        link.add(to: .main, forMode: .common)
    }
    private func animate(_ link: CADisplayLink) {
        let now = link.targetTimestamp > 0 ? link.targetTimestamp : CACurrentMediaTime()
        let delta = max(0, now - (lastTimestamp ?? now))
        lastTimestamp = now
        morph?.advance(by: delta)
        if morph?.isSettled == true {
            morph?.finish(); present()
            if let targetFrame { panel.setFrame(targetFrame, display: true) }
            stopDisplayLink()
            hostingView?.refreshHoverRegion()
        } else { present() }
    }
    private func present() {
        guard let morph else { return }
        var transaction = Transaction(animation: nil); transaction.disablesAnimations = true
        withTransaction(transaction) { motion.present(morph) }
        hostingView?.visibleIslandSize = morph.size
        hostingView?.refreshHoverRegion()
    }
    private func stopDisplayLink() {
        displayLink?.invalidate(); displayLink = nil; lastTimestamp = nil
    }
}

/// A screen-edge surface with inward shoulders; a capsule when detached.
struct IslandSilhouette: Shape {
    var docked: Bool
    var fraction: Double
    init(docked: Bool, expanded: Bool) { self.docked = docked; fraction = expanded ? 1 : 0 }
    init(docked: Bool, fraction: Double) { self.docked = docked; self.fraction = fraction }
    func path(in rect: CGRect) -> Path {
        let blend = CGFloat(min(1, max(0, fraction)))
        guard docked else { return Path(roundedRect: rect, cornerRadius: 16 + 6 * blend) }
        let shoulder: CGFloat = 8 + 6 * blend
        let bottom = min(15 + 11 * blend, rect.height / 2)
        let w = rect.width, h = rect.height
        var p = Path(); p.move(to: .zero); p.addLine(to: CGPoint(x: w, y: 0))
        p.addCurve(to: CGPoint(x: w - shoulder, y: shoulder), control1: CGPoint(x: w - shoulder, y: 0), control2: CGPoint(x: w - shoulder, y: shoulder * 0.4))
        p.addLine(to: CGPoint(x: w - shoulder, y: h - bottom))
        p.addQuadCurve(to: CGPoint(x: w - shoulder - bottom, y: h), control: CGPoint(x: w - shoulder, y: h))
        p.addLine(to: CGPoint(x: shoulder + bottom, y: h))
        p.addQuadCurve(to: CGPoint(x: shoulder, y: h - bottom), control: CGPoint(x: shoulder, y: h))
        p.addLine(to: CGPoint(x: shoulder, y: shoulder))
        p.addCurve(to: .zero, control1: CGPoint(x: shoulder, y: shoulder * 0.4), control2: CGPoint(x: shoulder, y: 0))
        p.closeSubpath(); return p
    }
}

struct NotchView: View {
    @ObservedObject var store: IslandStore
    @ObservedObject var preferences: Preferences
    private var theme: AccentTheme { preferences.theme }
    private var docked: Bool { store.hasNotch || store.dockToEdge }
    private var state: SessionState { store.unreadAlert?.state ?? (store.running.isEmpty ? .unknown : .running) }
    @ObservedObject var motion: IslandMotion
    var body: some View {
        let sample = motion.sample
        let reveal = sample.reveal
        let shape = IslandSilhouette(docked: docked, fraction: sample.fraction)
        ZStack(alignment: .top) {
            if sample.fraction < 1 {
                CompactStatusBar(profile: preferences.statusBar.profile(for: store.statusBarMode),
                                 data: .live(store), width: sample.size.width,
                                 physicalNotchWidth: store.physicalNotchWidth, height: store.topInset)
                    .blur(radius: reveal.compactBlur)
                    .opacity(reveal.compactOpacity)
                    .allowsHitTesting(!store.expanded)
                    .accessibilityHidden(store.expanded)
            }
            if motion.mountsExpandedContent {
                VStack(spacing: 0) {
                    header(expanded: true)
                        .blur(radius: 4 * (1 - sample.fraction))
                        .opacity(reveal.bodyOpacity)
                    expandedBody
                        .frame(width: motion.expandedSize.width, height: max(1, motion.expandedSize.height - store.topInset))
                        .compositingGroup()
                        .blur(radius: reveal.bodyBlur)
                        .opacity(reveal.bodyOpacity)
                        .scaleEffect(x: 0.985 + 0.015 * sample.fraction, y: reveal.bodyScale, anchor: .top)
                        .rotation3DEffect(.degrees(reveal.tiltDegrees), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.18)
                }
                .frame(width: motion.expandedSize.width, height: motion.expandedSize.height, alignment: .top)
                .allowsHitTesting(store.expanded && sample.fraction > 0.8)
                .accessibilityHidden(!store.expanded)
            }
        }
        .frame(width: sample.size.width, height: sample.size.height, alignment: .top)
        .background(Color.black).clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.055 + 0.035 * sample.fraction), lineWidth: 0.7).allowsHitTesting(false))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .environment(\.islandTheme, theme).tint(theme.accent)
        .onExitCommand { store.collapse() }
    }
    private func header(expanded: Bool) -> some View {
        HStack(spacing: expanded || store.hasCompactActivity ? 9 : 0) {
            SignalGlyph(state: store.running.isEmpty ? .unknown : .running, size: 15, agents: store.runningAgents)
                .accessibilityLabel(store.hasCompactActivity ? state.label : "空闲")
            if !store.hasNotch && (expanded || store.hasCompactActivity) {
                Text(expanded ? "TERN" : store.compactLabel)
                    .font(.system(size: expanded ? 9 : 10.5, weight: .medium, design: .monospaced))
                    .tracking(expanded ? 1.4 : 0).foregroundStyle(Palette.paper.opacity(0.78)).lineLimit(1)
            }
            Spacer(minLength: store.hasNotch ? 150 : 0)
            if expanded {
                if store.isDemo { Text("DEMO").font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(.orange) }
                TinyIconButton(icon: preferences.muted ? "speaker.slash" : "speaker.wave.2", label: preferences.muted ? "恢复声音" : "静音", active: preferences.muted) { preferences.muted.toggle() }
                TinyIconButton(icon: "gearshape", label: "打开设置") { store.section = "appearance"; store.openDashboard?() }
                TinyIconButton(icon: "chevron.up", label: "收起刘海") { store.collapse() }
            }
        }.padding(.horizontal, expanded ? 30 : 21).frame(height: store.topInset)
            .contentShape(Rectangle())
            .help(expanded ? "移开鼠标后收起" : "悬停查看会话与交付")
    }
    private var expandedBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 19) {
                tab("active", "当前", count: store.activeSessions.count)
                tab("history", "历史", count: store.historySessions.count)
                Spacer()
                Text("\(store.running.count) 进行中").font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 30).frame(height: 35)
            Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 26)
            HStack(spacing: 5) {
                filter(nil, name: "全部")
                ForEach(Agent.allCases, id: \.self) { agent in filter(agent, name: agent.name) }
                Spacer()
                if !store.unreadSessionIDs.isEmpty {
                    Text("在原 App 查看后清除").font(.system(size: 9)).foregroundStyle(Palette.muted)
                }
            }.padding(.horizontal, 26).frame(height: 33)
            if store.islandSessions.isEmpty { empty }
            else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(store.islandSessions) { session in
                            IslandSessionRow(session: session, unread: store.unreadSessionIDs.contains(session.id), jump: { store.jump(session) })
                        }
                    }.padding(.horizontal, 25).padding(.vertical, 2)
                }.scrollIndicators(.hidden)
            }
            HStack(spacing: 6) {
                Image(systemName: preferences.muted ? "bell.slash" : "antenna.radiowaves.left.and.right").font(.system(size: 8)).foregroundStyle(Palette.muted)
                Text(preferences.muted ? "提醒已暂停" : "本地监听").font(.system(size: 9)).foregroundStyle(Palette.muted)
                Spacer()
                if store.isDemo { Button("退出演示") { store.endDemo() }.buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(.orange) }
                Button { store.openDashboard?() } label: { HStack(spacing: 5) { Text("任务中心"); Image(systemName: "arrow.up.right") } }.buttonStyle(.plain).font(.system(size: 9)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 31).frame(height: 28)
        }
    }
    private func tab(_ value: String, _ title: String, count: Int) -> some View {
        Button { store.selectIslandTab(value) } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text("\(count)").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(Palette.muted)
                if value == "active", !store.unreadSessionIDs.isEmpty { Circle().fill(Palette.green).frame(width: 4, height: 4) }
            }.foregroundStyle(store.islandTab == value ? theme.text : Palette.muted)
                .frame(height: 35).overlay(alignment: .bottom) { Capsule().fill(store.islandTab == value ? theme.accent : .clear).frame(height: 2) }
        }.buttonStyle(.plain)
    }
    private func filter(_ agent: Agent?, name: String) -> some View {
        Button { store.selectIslandAgent(agent) } label: {
            Text(name).font(.system(size: 9, weight: .medium))
                .foregroundStyle(store.islandAgent == agent ? theme.text : Palette.muted)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(store.islandAgent == agent ? theme.subtle : .clear, in: RoundedRectangle(cornerRadius: 5))
        }.buttonStyle(.plain)
    }
    private var empty: some View {
        VStack(spacing: 9) {
            Image(systemName: "tray").font(.system(size: 21, weight: .light)).foregroundStyle(Palette.muted)
            Text(store.islandTab == "history" ? "还没有历史会话" : "当前没有待处理的会话").font(.system(size: 12, weight: .medium))
            Text("新的进展，会出现在这里。").font(.system(size: 10)).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct IslandSessionRow: View {
    let session: Session
    let unread: Bool
    let jump: () -> Void
    @State private var hovered = false
    @Environment(\.islandTheme) private var theme
    var body: some View {
        Button(action: jump) {
            HStack(spacing: 10) {
                Group {
                    if unread { Circle().fill(Palette.green).frame(width: 6, height: 6) }
                    else if session.state == .running { SignalGlyph(state: .running, size: 12, agents: [session.agent]) }
                    else { Image(systemName: session.state.symbol).font(.system(size: 10)).foregroundStyle(Palette.muted) }
                }.frame(width: 14)
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.displayTitle).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.paper).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(SessionPresentation.projectName(session)).lineLimit(1)
                        Text("·")
                        Text(unread ? "待检查" : session.state.label).foregroundStyle(unread ? Palette.green : session.state.tint)
                    }.font(.system(size: 9.5)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 2)
                AgentBadge(agent: session.agent)
                TimelineView(.periodic(from: .now, by: 30)) { time in
                    Text(SessionPresentation.relativeTime(session.updatedAt, now: time.date)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted).frame(width: 29, alignment: .trailing)
                }
                Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(Palette.muted)
            }.padding(.horizontal, 11).frame(height: 50).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("\(session.displayTitle)，\(session.agent.name)，\(unread ? "待检查" : session.state.label)，打开原会话")
            .background(Color.white.opacity(hovered ? 0.05 : 0.013), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(hovered ? theme.border : Color.white.opacity(0.055), lineWidth: 0.7))
            .onHover { hovered = $0 }
    }
}
