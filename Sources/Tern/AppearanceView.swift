import SwiftUI
import TernCore

struct AppearanceView: View {
    @ObservedObject var store: IslandStore
    @ObservedObject var preferences: Preferences
    @Environment(\.islandTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("留在视线里，融进屏幕中。").font(.system(size: 23, weight: .semibold)).foregroundStyle(Palette.paper)
                    Text("选择你喜欢的刘海形态。变化会立即应用到屏幕顶部。").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Button { store.section = "barLayout" } label: {
                    Label("拖拽编排状态栏", systemImage: "slider.horizontal.3")
                }.buttonStyle(IslandButtonStyle())
                PanelCard {
                    VStack(alignment: .leading, spacing: 15) {
                        HStack {
                            Text("主题").font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text("即时生效 · 自动保存").font(.system(size: 10)).foregroundStyle(Palette.muted)
                        }
                        ThemeSwatches(selection: $preferences.theme)
                        Divider().overlay(Palette.line)
                        HStack(spacing: 18) {
                            ForEach(Agent.allCases, id: \.self) { agent in
                                HStack(spacing: 7) {
                                    AgentMark(agent: agent, size: 24)
                                    Text(agent.name).font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                            }
                            Spacer()
                        }
                    }
                }
                HStack(spacing: 13) {
                    styleCard(docked: true, title: "贴顶刘海", subtitle: "与屏幕边缘自然衔接")
                    styleCard(docked: false, title: "浮动胶囊", subtitle: "轻巧悬浮，留一点呼吸")
                }
                if store.hasNotch {
                    Label("当前显示器有物理刘海，会自动采用贴顶布局。", systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                PanelCard {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("显示刘海")
                            Spacer()
                            Toggle("显示刘海", isOn: $preferences.showIsland).labelsHidden()
                        }
                        Divider().overlay(Palette.line)
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("仅悬停时展开")
                                Text("交付时只更新刘海提示，移开鼠标后自动收起。").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                            Spacer(); Image(systemName: "cursorarrow").foregroundStyle(Palette.muted)
                        }
                    }.font(.system(size: 12)).toggleStyle(.switch).tint(theme.accent)
                }
                VStack(alignment: .leading, spacing: 13) {
                    Text("一个小窗口，刚好够用。").font(.system(size: 13, weight: .medium))
                    instruction("cursorarrow", "悬停展开", "短暂停留后展开；移开鼠标会自动收起。")
                    instruction("capsule", "按状态伸缩", "静态保留点阵与提示灯；有任务时切换为另一套固定宽度。")
                    instruction("rectangle.stack", "多会话同屏", "分为当前和历史会话，点击一行直接返回原 Agent。")
                    instruction("checkmark.circle", "交付轻提醒", "在原 Agent 打开对应会话确认后，待检查提示才会清除。")
                    instruction("command", "快捷收起", "App 激活时，⌘I 或 Esc 收起。展开只由悬停触发。")
                }.padding(.horizontal, 2)
                HStack {
                    Button { store.demo() } label: { Label("预览交付提示", systemImage: "play") }.buttonStyle(IslandButtonStyle(prominent: true))
                    Spacer()
                    Text("遵循 macOS 减少动态效果设置").font(.system(size: 9)).foregroundStyle(Palette.muted)
                }
            }.padding(28)
        }
    }
    private func styleCard(docked: Bool, title: String, subtitle: String) -> some View {
        Button { store.dockToEdge = docked } label: {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .top) {
                    theme.accent.opacity(0.07).background(Palette.surface)
                    RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.025)).frame(width: 140, height: 60).offset(x: 35, y: 38)
                    HStack(spacing: 8) {
                        SignalGlyph(state: .running, size: 12, tint: theme.text)
                        Text("Tern").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(Palette.paper)
                        HStack(spacing: 2) { ForEach(Agent.allCases, id: \.self) { agent in RoundedRectangle(cornerRadius: 1).fill(agent.tint).frame(width: 4, height: 4) } }
                    }.frame(width: 177, height: 29).background(.black)
                        .clipShape(IslandSilhouette(docked: docked, expanded: false)).offset(y: docked ? 0 : 12)
                }.frame(height: 103).clipShape(RoundedRectangle(cornerRadius: 9))
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.paper)
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    Image(systemName: store.dockToEdge == docked ? "checkmark.circle.fill" : "circle").font(.system(size: 15)).foregroundStyle(store.dockToEdge == docked ? theme.text : Palette.muted.opacity(0.35))
                }
            }.padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(store.dockToEdge == docked ? theme.border : Palette.line))
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(store.dockToEdge == docked ? .isSelected : [])
    }
    private func instruction(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Palette.muted).frame(width: 17)
            Text(title).font(.system(size: 11, weight: .medium)).frame(width: 80, alignment: .leading)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }
}
