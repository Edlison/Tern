import XCTest
import CoreGraphics
@testable import TernCore

final class PanelFrameTests: XCTestCase {
    func testExpansionAndCollapseKeepTopEdgeAndHorizontalCenterFixed() {
        for top: CGFloat in [900, 1800, -20] {
            let closed = CGRect(x: 596, y: top - 32, width: 248, height: 32)
            let open = CGRect(x: 415, y: top - 474, width: 610, height: 474)
            for (start, end) in [(closed, open), (open, closed)] {
                for tick in 0...60 {
                    let frame = IslandPanelFrame.interpolate(from: start, to: end, progress: Double(tick) / 60)
                    XCTAssertEqual(frame.maxY, top, accuracy: 0.000001)
                    XCTAssertEqual(frame.midX, 720, accuracy: 0.000001)
                    XCTAssertTrue((32...474).contains(frame.height))
                }
            }
        }
    }
    func testReversalAndFloatingGapDoNotIntroduceVerticalDrift() {
        let closed = CGRect(x: 596, y: 859, width: 248, height: 32)
        let open = CGRect(x: 415, y: 417, width: 610, height: 474)
        let interrupted = IslandPanelFrame.interpolate(from: closed, to: open, progress: 0.43)
        let reversed = IslandPanelFrame.interpolate(from: interrupted, to: closed, progress: 0.6)
        XCTAssertEqual(reversed.maxY, 891, accuracy: 0.000001)
        XCTAssertEqual(IslandPanelFrame.interpolate(from: interrupted, to: closed, progress: 1), closed)
    }
}
