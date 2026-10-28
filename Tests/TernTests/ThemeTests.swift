import XCTest
@testable import Tern

final class ThemeTests: XCTestCase {
    @MainActor func testThemePersistsAcrossPreferenceInstances() async {
        let name = "TernTests.Theme.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.theme, .teal)
        preferences.theme = .rose
        XCTAssertEqual(Preferences(defaults: defaults).theme, .rose)
        preferences.theme = .silver
        XCTAssertEqual(Preferences(defaults: defaults).theme, .silver)
    }
    @MainActor func testUnknownSavedThemeFallsBackWithoutOverwritingOtherSettings() async {
        let name = "TernTests.Theme.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("retired-palette", forKey: "accentTheme")
        defaults.set(0.42, forKey: "volume")
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.theme, .teal)
        XCTAssertEqual(preferences.volume, 0.42)
        preferences.theme = .iris
        XCTAssertEqual(defaults.double(forKey: "volume"), 0.42)
    }
    func testEveryPaletteKeepsSmallTextReadableIncludingPressedButtons() {
        func luminance(_ hex: UInt32) -> Double {
            let channels = [16, 8, 0].map { shift -> Double in
                let c = Double((hex >> shift) & 255) / 255
                return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
            }
            return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        }
        func ratio(_ a: UInt32, _ b: UInt32) -> Double {
            let x = luminance(a), y = luminance(b)
            return (max(x, y) + 0.05) / (min(x, y) + 0.05)
        }
        for theme in AccentTheme.allCases {
            for background: UInt32 in [0x000000, 0x0B0C0D, 0x131416, 0x242424] {
                XCTAssertGreaterThanOrEqual(ratio(theme.tokens.text, background), 4.5, "\(theme) accent text")
            }
            XCTAssertGreaterThanOrEqual(ratio(theme.tokens.fill, theme.tokens.ink), 4.5, "\(theme) filled button")
            XCTAssertGreaterThanOrEqual(ratio(theme.tokens.pressed, theme.tokens.ink), 4.5, "\(theme) pressed button")
        }
    }
}
