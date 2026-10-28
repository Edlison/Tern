import SwiftUI
import AppKit
import TernCore

enum AccentTheme: String, CaseIterable, Identifiable {
    case teal, rose, iris, blue, amber, silver
    var id: String { rawValue }
    // The first two palettes use design-sh's accent families; the others follow the same roles.
    var tokens: ThemeTokens {
        switch self {
        case .teal: ThemeTokens(fill: 0x09AEA1, text: 0x19BCAE, pressed: 0x07978C)
        case .rose: ThemeTokens(fill: 0xD45BB6, text: 0xE27CC8, pressed: 0xBF4AA2)
        case .iris: ThemeTokens(fill: 0x9B8CFF, text: 0xB5A9FF, pressed: 0x8374E5)
        case .blue: ThemeTokens(fill: 0x6A9FE8, text: 0x91BBF5, pressed: 0x5489CF)
        case .amber: ThemeTokens(fill: 0xD9AB55, text: 0xEBC680, pressed: 0xBD9142)
        case .silver: ThemeTokens(fill: 0xB5BBC5, text: 0xD2D7DF, pressed: 0x989FAA)
        }
    }
    var accent: Color { Color(rgbHex: tokens.fill) }
    var text: Color { Color(rgbHex: tokens.text) }
    var pressed: Color { Color(rgbHex: tokens.pressed) }
    var ink: Color { Color(rgbHex: tokens.ink) }
    var subtle: Color { accent.opacity(0.10) }
    var border: Color { accent.opacity(0.50) }
}

struct ThemeTokens {
    let fill: UInt32
    let text: UInt32
    let pressed: UInt32
    // Black keeps small labels above 4.5:1 even on the darkest pressed accent.
    let ink: UInt32 = 0x000000
}

@MainActor enum AppBrandIcon {
    static func image(theme: AccentTheme) -> NSImage {
        let image = NSImage(size: NSSize(width: 256, height: 256))
        image.lockFocus()
        NSColor(Palette.background).setFill()
        NSBezierPath(roundedRect: NSRect(x: 15, y: 15, width: 226, height: 226), xRadius: 51, yRadius: 51).fill()
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.translateBy(x: 0, y: 256); context.scaleBy(x: 1, y: -1)
            context.setFillColor(NSColor(theme.accent).cgColor)
            context.addPath(BrandMark.path(in: CGRect(x: 35, y: 35, width: 186, height: 186))); context.fillPath()
            context.restoreGState()
        }
        image.unlockFocus()
        return image
    }
}

extension Color {
    init(rgbHex: UInt32) {
        self.init(.sRGB, red: Double((rgbHex >> 16) & 255) / 255,
                  green: Double((rgbHex >> 8) & 255) / 255, blue: Double(rgbHex & 255) / 255, opacity: 1)
    }
}

private struct IslandThemeKey: EnvironmentKey {
    static let defaultValue = AccentTheme.teal
}
extension EnvironmentValues {
    var islandTheme: AccentTheme {
        get { self[IslandThemeKey.self] }
        set { self[IslandThemeKey.self] = newValue }
    }
}

struct ThemeSwatches: View {
    @Binding var selection: AccentTheme
    @FocusState private var focused: AccentTheme?
    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(AccentTheme.allCases.enumerated()), id: \.element.id) { index, theme in
                Button { selection = theme; focused = theme } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(theme.accent)
                        if selection == theme {
                            Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.ink)
                        }
                    }.frame(width: 46, height: 32).padding(5)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(selection == theme ? 0.04 : 0)))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(focused == theme ? Palette.paper : selection == theme ? theme.text : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focused, equals: theme)
                    .accessibilityLabel("主题方案 \(index + 1)")
                    .accessibilityValue(selection == theme ? "已选择" : "未选择")
                    .accessibilityAddTraits(selection == theme ? .isSelected : [])
            }
        }
        .onChange(of: selection) { _, value in focused = value }
        .onMoveCommand { direction in
            guard let focused, let index = AccentTheme.allCases.firstIndex(of: focused) else { return }
            let step: Int
            switch direction { case .left, .up: step = -1; case .right, .down: step = 1; default: return }
            let values = AccentTheme.allCases
            let next = values[(index + step + values.count) % values.count]
            selection = next; self.focused = next
        }
        .accessibilityRepresentation {
            Picker("主题配色", selection: $selection) {
                ForEach(Array(AccentTheme.allCases.enumerated()), id: \.element.id) { index, theme in
                    Text("主题方案 \(index + 1)").tag(theme)
                }
            }.pickerStyle(.radioGroup)
        }
    }
}

struct TernMark: Shape {
    func path(in rect: CGRect) -> Path { Path(BrandMark.path(in: rect)) }
}
