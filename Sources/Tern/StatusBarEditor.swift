import AppKit
import SwiftUI
import TernCore

private enum EditorDropTarget: Hashable {
    case preview(StatusBarZone), lane(StatusBarZone), before(StatusBarWidget, StatusBarZone), trash
    var priority: Int { switch self { case .trash: 3; case .before: 2; default: 1 } }
}
private struct WidgetFramesKey: PreferenceKey {
    static var defaultValue: [EditorDropTarget: CGRect] = [:]
    static func reduce(value: inout [EditorDropTarget: CGRect], nextValue: () -> [EditorDropTarget: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
private struct WidgetDropSurface: ViewModifier {
    let target: EditorDropTarget
    let active: EditorDropTarget?
    @Environment(\.islandTheme) private var theme
    func body(content: Content) -> some View {
        content
            .background(GeometryReader { geometry in
                Color.clear.preference(key: WidgetFramesKey.self, value: [target: geometry.frame(in: .named("statusbar-editor"))])
            })
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(active == target ? theme.text : .clear, lineWidth: 2).allowsHitTesting(false))
            .background(active == target ? theme.subtle : .clear, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct StatusBarEditor: View {
    @ObservedObject var store: IslandStore
    @ObservedObject var preferences: Preferences
    @Environment(\.islandTheme) private var theme
    @State private var mode = StatusBarMode.idle
    @State private var message: String?
    @State private var draggedWidget: StatusBarWidget?
    @State private var dragPoint = CGPoint.zero
    @State private var dragTarget: EditorDropTarget?
    @State private var dropFrames: [EditorDropTarget: CGRect] = [:]
    @GestureState private var gestureID: UUID?
    @State private var activeGestureID: UUID?
    @State private var cancelledGestureID: UUID?
    private var profile: StatusBarProfile { preferences.statusBar.profile(for: mode) }
    private var previewWidth: Double { preferences.statusBar.resolvedWidth(for: mode, physicalNotchWidth: store.physicalNotchWidth) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("把常用信息，拖到手边。").font(.system(size: 23, weight: .semibold)).foregroundStyle(Palette.paper)
                    Text("分别编排静态与有任务时的状态栏。拖入、排序或移除，预览即时更新。").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                HStack(spacing: 12) {
                    Picker("编辑状态", selection: $mode) {
                        ForEach(StatusBarMode.allCases, id: \.self) { state in Text(state.title).tag(state) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                    Spacer()
                    Button("恢复此状态默认布局") { preferences.resetStatusBarProfile(for: mode); message = nil }.buttonStyle(IslandButtonStyle())
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        previewCard
                        HStack(spacing: 8) {
                            ForEach(StatusBarStyle.allCases, id: \.self) { style in styleCard(style) }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("编排组件").font(.system(size: 13, weight: .medium))
                                Spacer()
                                Text("拖到组件前可排序").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                            ForEach(StatusBarZone.allCases, id: \.self) { zone in zoneRow(zone) }
                        }
                    }.frame(maxWidth: .infinity)
                    library.frame(width: 194)
                }
            }.padding(24)
        }
        .coordinateSpace(name: "statusbar-editor")
        .onPreferenceChange(WidgetFramesKey.self) { dropFrames = $0 }
        .overlay(alignment: .topLeading) {
            if let draggedWidget {
                Label(draggedWidget.title, systemImage: draggedWidget.symbol)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.text)
                    .padding(.horizontal, 12).frame(height: 34)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.border))
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                    .position(dragPoint).allowsHitTesting(false)
            }
        }
        .onExitCommand { cancelledGestureID = activeGestureID; cancelDrag() }
        .onChange(of: gestureID) { _, value in if value == nil { cancelDrag() } }
        .onChange(of: mode) { _, _ in message = nil; cancelledGestureID = activeGestureID; cancelDrag() }
    }

    private var previewCard: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(mode == .idle ? "静态状态栏" : "有任务状态栏", systemImage: mode == .idle ? "pause.circle" : "waveform")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("示例 · 自动保存").font(.system(size: 9)).foregroundStyle(Palette.muted)
                }
                previewStage
                HStack(spacing: 9) {
                    Text("固定宽度").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    Slider(value: Binding(get: { profile.fixedWidth }, set: setWidth), in: widthRange, step: 8)
                        .accessibilityLabel("\(mode.title)状态栏固定宽度")
                    Text("\(Int(previewWidth)) pt").font(.system(size: 10, design: .monospaced)).monospacedDigit().frame(width: 58, alignment: .trailing)
                }
                Text("长文字自动省略，数量变化不会改变长度。").font(.system(size: 10)).foregroundStyle(Palette.muted)
                if store.hasNotch {
                    Text("摄像头区域保持留空，中间组件移到左侧。").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                if let message { Label(message, systemImage: "info.circle").font(.system(size: 10)).foregroundStyle(.orange) }
            }
        }
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("组件库").font(.system(size: 13, weight: .medium))
            Text("拖到左侧预览，或点击显示 / 隐藏").font(.system(size: 9)).foregroundStyle(Palette.muted)
            VStack(spacing: 7) {
                ForEach(StatusBarWidget.allCases, id: \.self) { widget in libraryTile(widget) }
            }
            HStack(spacing: 6) { Image(systemName: "trash"); Text("拖到这里移除") }
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                .modifier(WidgetDropSurface(target: .trash, active: dragTarget))
                .accessibilityLabel("移除组件区域")
        }
    }

    private var dragPreviewProfile: StatusBarProfile {
        guard let draggedWidget, let dragTarget else { return profile }
        var preview = profile
        switch dragTarget {
        case .preview(let zone), .lane(let zone): _ = preview.place(draggedWidget, in: zone)
        case .before(let next, let zone): _ = preview.place(draggedWidget, in: zone, before: next)
        case .trash: preview.remove(draggedWidget)
        }
        return preview
    }
    private func target(at point: CGPoint) -> EditorDropTarget? {
        dropFrames.filter { $0.value.contains(point) }.keys.sorted { $0.priority > $1.priority }.first
    }
    private func cancelDrag() { draggedWidget = nil; dragTarget = nil }
    private func dragGesture(for widget: StatusBarWidget) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("statusbar-editor"))
            .updating($gestureID) { _, identifier, _ in if identifier == nil { identifier = UUID() } }
            .onChanged { value in
                guard let gestureID else { return }
                activeGestureID = gestureID
                guard cancelledGestureID != gestureID else { return }
                draggedWidget = widget; dragPoint = value.location; dragTarget = target(at: value.location)
            }
            .onEnded { value in
                defer { activeGestureID = nil; cancelDrag() }
                guard let activeGestureID, cancelledGestureID != activeGestureID else { return }
                let destination = target(at: value.location)
                switch destination {
                case .preview(let zone), .lane(let zone): place(widget, in: zone)
                case .before(let next, let zone): place(widget, in: zone, before: next)
                case .trash: remove(widget)
                case nil: break
                }
            }
    }

    private var widthRange: ClosedRange<Double> {
        mode == .idle ? 120...240 : 240...360
    }
    private func setWidth(_ value: Double) {
        var candidate = profile; candidate.fixedWidth = value
        guard candidate.fits else { message = "当前组件放不下，请先移除一项或保留更宽的状态栏。"; return }
        preferences.setStatusBarProfile(candidate, for: mode); message = nil
    }
    private func place(_ widget: StatusBarWidget, in zone: StatusBarZone, before: StatusBarWidget? = nil) {
        var candidate = profile
        guard candidate.place(widget, in: zone, before: before) else {
            message = "空间不足：请移除一项，或调大这套状态栏的固定宽度。"; return
        }
        preferences.setStatusBarProfile(candidate, for: mode); message = nil
    }
    private func remove(_ widget: StatusBarWidget) {
        var candidate = profile; candidate.remove(widget)
        preferences.setStatusBarProfile(candidate, for: mode); message = nil
    }
    private func shift(_ widget: StatusBarWidget, in zone: StatusBarZone, by offset: Int) {
        var candidate = profile; var items = candidate.items(in: zone)
        guard let index = items.firstIndex(of: widget), items.indices.contains(index + offset) else { return }
        items.swapAt(index, index + offset); candidate.setItems(items, in: zone)
        preferences.setStatusBarProfile(candidate, for: mode)
    }

    private var previewStage: some View {
        GeometryReader { geometry in
            let scale = min(1, (geometry.size.width - 24) / previewWidth)
            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(Color.black.opacity(0.22))
                VStack(spacing: 0) {
                    ZStack {
                        CompactStatusBar(profile: dragPreviewProfile, data: .preview(mode), width: previewWidth,
                                         physicalNotchWidth: store.physicalNotchWidth)
                            .background(.black)
                            .clipShape(IslandSilhouette(docked: store.dockToEdge || store.hasNotch, expanded: false))
                        HStack(spacing: 0) {
                            ForEach(StatusBarZone.allCases, id: \.self) { zone in
                                Color.clear.contentShape(Rectangle()).frame(maxWidth: .infinity).frame(height: 32)
                                    .modifier(WidgetDropSurface(target: .preview(zone), active: dragTarget))
                                    .accessibilityLabel("预览\(zone.title)拖放区")
                            }
                        }.frame(width: previewWidth)
                    }.frame(width: previewWidth, height: 32)
                    HStack {
                        ForEach(StatusBarZone.allCases, id: \.self) { zone in
                            Text(zone.title).font(.system(size: 8, design: .monospaced)).foregroundStyle(Palette.muted.opacity(0.7)).frame(maxWidth: .infinity)
                        }
                    }.frame(width: previewWidth).padding(.top, 10)
                }.scaleEffect(scale)
            }
        }.frame(height: 68)
    }
    private func styleCard(_ style: StatusBarStyle) -> some View {
        var preview = profile; preview.style = style
        return Button {
            var next = profile; next.style = style
            preferences.setStatusBarProfile(next, for: mode)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    CompactStatusBar(profile: preview, data: .preview(mode), width: preview.fixedWidth)
                        .background(.black, in: Capsule())
                        .scaleEffect(min(0.58, geometry.size.width / preview.fixedWidth), anchor: .leading)
                        .frame(width: geometry.size.width, height: 34, alignment: .leading)
                }.frame(height: 30).clipped()
                HStack {
                    Text(style.title).font(.system(size: 11, weight: .medium))
                    Spacer()
                    Image(systemName: profile.style == style ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(profile.style == style ? theme.text : Palette.muted.opacity(0.4))
                }
            }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(profile.style == style ? theme.border : Palette.line))
        }.buttonStyle(.plain).accessibilityLabel("\(style.title)显示风格").accessibilityAddTraits(profile.style == style ? .isSelected : [])
    }
    private func zoneRow(_ zone: StatusBarZone) -> some View {
        HStack(spacing: 12) {
            Text(zone.title).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted).frame(width: 32)
            ScrollView(.horizontal) {
                HStack(spacing: 7) {
                    ForEach(profile.items(in: zone), id: \.self) { widget in
                        HStack(spacing: 6) {
                            Image(systemName: widget.symbol).font(.system(size: 10)).foregroundStyle(theme.text)
                            Text(widget.title).font(.system(size: 10))
                            Button { remove(widget) } label: {
                                Image(systemName: "xmark").font(.system(size: 8, weight: .medium)).foregroundStyle(Palette.muted).frame(width: 18, height: 24)
                            }.buttonStyle(.plain).accessibilityLabel("移除\(widget.title)")
                        }.padding(.leading, 9).padding(.trailing, 3).frame(height: 32)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                            .highPriorityGesture(dragGesture(for: widget))
                            .modifier(WidgetDropSurface(target: .before(widget, zone), active: dragTarget))
                            .contextMenu {
                                Button("向前移动") { shift(widget, in: zone, by: -1) }
                                Button("向后移动") { shift(widget, in: zone, by: 1) }
                                ForEach(StatusBarZone.allCases, id: \.self) { target in Button("移到\(target.title)") { place(widget, in: target) } }
                                Divider(); Button("移除") { remove(widget) }
                            }
                            .accessibilityElement(children: .contain).accessibilityLabel("\(zone.title)组件：\(widget.title)")
                    }
                    if profile.items(in: zone).isEmpty {
                        Text("拖入组件").font(.system(size: 10)).foregroundStyle(Palette.muted.opacity(0.6)).frame(height: 32)
                    }
                    Spacer(minLength: 18)
                }.padding(.vertical, 5)
            }.scrollIndicators(.hidden)
        }.padding(.horizontal, 10).frame(height: 44)
            .background(Palette.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.line))
            .modifier(WidgetDropSurface(target: .lane(zone), active: dragTarget))
            .accessibilityElement(children: .contain).accessibilityLabel("\(zone.title)编排区")
    }
    private func libraryTile(_ widget: StatusBarWidget) -> some View {
        let included = profile.widgets.contains(widget)
        return Button {
            if included { remove(widget) } else { place(widget, in: widget.suggestedZone) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: widget.symbol).font(.system(size: 15)).foregroundStyle(included ? theme.text : Palette.muted).frame(width: 22)
                Text(widget.title).font(.system(size: 11, weight: .medium))
                Spacer()
                Image(systemName: included ? "checkmark" : "plus").font(.system(size: 9)).foregroundStyle(included ? theme.text : Palette.muted)
            }.padding(.horizontal, 11).frame(height: 39)
                .background(included ? theme.accent.opacity(0.045) : Palette.surface, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(included ? theme.border.opacity(0.6) : Palette.line))
        }.buttonStyle(.plain)
            .highPriorityGesture(dragGesture(for: widget))
            .help("拖入上方状态栏，或点击显示 / 隐藏")
            .accessibilityLabel("\(widget.title)，\(included ? "已显示" : "可添加")，可拖动")
    }
}
