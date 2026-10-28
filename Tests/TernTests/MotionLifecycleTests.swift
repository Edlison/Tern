import AppKit
import XCTest
import TernCore
@testable import Tern

final class MotionLifecycleTests: XCTestCase {
    @MainActor func testExpandedContentSurvivesUntilClosingAnimationFinishes() async {
        let model = IslandMotion()
        let open = CGSize(width: 610, height: 474)
        var morph = IslandMorph(size: open, expanded: true)
        model.prepare(expandedSize: open, expanded: true)
        model.present(morph)
        XCTAssertTrue(model.mountsExpandedContent)
        morph.retarget(size: CGSize(width: 248, height: 32), expanded: false)
        model.prepare(expandedSize: open, expanded: false)
        morph.advance(by: 0.07); model.present(morph)
        XCTAssertTrue(model.mountsExpandedContent, "The closing content must blur out, not disappear instantly.")
        XCTAssertGreaterThan(model.sample.reveal.bodyBlur, 0)
        morph.finish(); model.present(morph)
        XCTAssertFalse(model.mountsExpandedContent)
    }
    @MainActor func testImmediateReducedMotionStateContainsNoResidualBlur() async {
        let model = IslandMotion()
        let open = CGSize(width: 610, height: 474)
        model.prepare(expandedSize: open, expanded: true)
        var morph = IslandMorph(size: CGSize(width: 248, height: 32))
        morph.retarget(size: open, expanded: true); morph.finish(); model.present(morph)
        XCTAssertEqual(model.sample.reveal.bodyBlur, 0)
        XCTAssertEqual(model.sample.reveal.bodyOpacity, 1)
        XCTAssertEqual(model.sample.size, open)
    }
}
