import XCTest
@testable import TernCore

final class StatusBarLayoutTests: XCTestCase {
    func testIdleDefaultOnlyOmitsTheMiddleDescription() {
        let config = StatusBarConfiguration.defaults
        XCTAssertEqual(config.idle.left, [.matrix])
        XCTAssertTrue(config.idle.center.isEmpty)
        XCTAssertEqual(config.idle.right, [.agentLights, .reviewCount, .sound])
        XCTAssertEqual(config.active.right, config.idle.right)
        XCTAssertEqual(config.active.center, [.summary])
        XCTAssertGreaterThanOrEqual(config.resolvedWidth(for: .idle), 120)
        XCTAssertGreaterThan(config.resolvedWidth(for: .active), config.resolvedWidth(for: .idle))
    }
    func testDragMovesAndReordersWithoutDuplicates() {
        var profile = StatusBarProfile.active
        XCTAssertTrue(profile.place(.sound, in: .left, before: .matrix))
        XCTAssertEqual(profile.left, [.sound, .matrix])
        XCTAssertFalse(profile.right.contains(.sound))
        XCTAssertTrue(profile.place(.matrix, in: .left, before: .sound))
        XCTAssertEqual(profile.left, [.matrix, .sound])
        XCTAssertEqual(profile.widgets.count, Set(profile.widgets).count)
        let same = profile
        XCTAssertTrue(profile.place(.matrix, in: .left, before: .matrix))
        XCTAssertEqual(profile, same)
    }
    func testOverflowDropIsRejectedWithoutResizingOrRemovingExistingModules() {
        var profile = StatusBarProfile.idle; profile.fixedWidth = 240
        XCTAssertTrue(profile.place(.summary, in: .center))
        let original = profile
        XCTAssertFalse(profile.place(.sessionTitle, in: .center))
        XCTAssertEqual(profile, original)
        XCTAssertEqual(profile.fixedWidth, 240)
    }
    func testStylesAndModuleRemovalDoNotResizeTheBar() {
        var config = StatusBarConfiguration.defaults
        let original = config.resolvedWidth(for: .active)
        var profile = config.active
        profile.style = .terminal; profile.remove(.summary)
        config.set(profile, for: .active)
        XCTAssertEqual(config.resolvedWidth(for: .active), original)
        XCTAssertEqual(config.idle, .idle)
    }
    func testPersistedLayoutRepairsUnknownDuplicateAndInvalidFields() throws {
        let data = Data(#"{"left":["matrix","future-widget"],"center":["matrix"],"right":["agentLights","sound"],"fixedWidth":-5,"style":"future-style"}"#.utf8)
        let profile = try JSONDecoder().decode(StatusBarProfile.self, from: data).normalized(for: .idle)
        XCTAssertEqual(profile.left, [.matrix]); XCTAssertTrue(profile.center.isEmpty)
        XCTAssertEqual(profile.right, [.agentLights, .sound]); XCTAssertEqual(profile.fixedWidth, 120)
        XCTAssertEqual(profile.style, .minimal)
        XCTAssertEqual(try JSONDecoder().decode(StatusBarProfile.self, from: JSONEncoder().encode(profile)), profile)
    }
    func testNewWidthRangesClampLegacyValuesAndAllowBothModesAt240() {
        var config = StatusBarConfiguration.defaults
        var idle = config.idle; idle.fixedWidth = 336; config.set(idle, for: .idle)
        var active = config.active; active.fixedWidth = 480; config.set(active, for: .active)
        XCTAssertEqual(config.idle.fixedWidth, 240); XCTAssertEqual(config.active.fixedWidth, 360)
        active.fixedWidth = 240; config.set(active, for: .active)
        XCTAssertEqual(config.resolvedWidth(for: .idle), 240)
        XCTAssertEqual(config.resolvedWidth(for: .active), 240)
        XCTAssertGreaterThan(config.resolvedWidth(for: .idle, physicalNotchWidth: 210), 210)
        idle.fixedWidth = 120; config.set(idle, for: .idle)
        XCTAssertEqual(config.resolvedWidth(for: .idle), 120)
        XCTAssertTrue(config.idle.fits)
    }
}
