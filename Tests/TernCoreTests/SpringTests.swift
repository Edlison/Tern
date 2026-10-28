import XCTest
import CoreGraphics
@testable import TernCore

final class SpringTests: XCTestCase {
    private let closed = CGSize(width: 248, height: 32)
    private let opened = CGSize(width: 610, height: 474)
    func testSameMotionAt60And120Hz() {
        var sixty = IslandMorph(size: closed), oneTwenty = IslandMorph(size: closed)
        sixty.retarget(size: opened, expanded: true); oneTwenty.retarget(size: opened, expanded: true)
        for _ in 0..<24 { sixty.advance(by: 1.0 / 60) }
        for _ in 0..<48 { oneTwenty.advance(by: 1.0 / 120) }
        XCTAssertEqual(sixty.size.width, oneTwenty.size.width, accuracy: 0.000001)
        XCTAssertEqual(sixty.size.height, oneTwenty.size.height, accuracy: 0.000001)
        XCTAssertEqual(sixty.fraction, oneTwenty.fraction, accuracy: 0.000001)
    }
    func testReversingHoverPreservesPositionAndVelocity() {
        var motion = IslandMorph(size: closed)
        motion.retarget(size: opened, expanded: true)
        for _ in 0..<8 { motion.advance(by: 1.0 / 120) }
        let size = motion.size, speed = motion.width.velocity, fraction = motion.fraction
        motion.retarget(size: closed, expanded: false)
        XCTAssertEqual(motion.size, size)
        XCTAssertEqual(motion.width.velocity, speed)
        XCTAssertEqual(motion.fraction, fraction)
        for _ in 0..<120 { motion.advance(by: 1.0 / 120) }
        XCTAssertTrue(motion.isSettled)
        motion.finish()
        XCTAssertEqual(motion.size, closed); XCTAssertEqual(motion.fraction, 0)
    }
    func testDroppedFrameAndJitterDoNotChangeTrajectory() {
        var single = IslandSpring(0), fragmented = IslandSpring(0)
        single.retarget(1); fragmented.retarget(1)
        single.advance(by: 0.4, frequency: 23)
        for dt in [0.007, 0.011, 0.042, 0.08, 0.26] { fragmented.advance(by: dt, frequency: 23) }
        XCTAssertEqual(single.value, fragmented.value, accuracy: 0.000001)
        XCTAssertEqual(single.velocity, fragmented.velocity, accuracy: 0.000001)
    }
    func testRapidHoverReversalsStayFiniteAndEventuallySettle() {
        var motion = IslandMorph(size: closed)
        for index in 0..<80 {
            let open = index % 2 == 0
            motion.retarget(size: open ? opened : closed, expanded: open)
            motion.advance(by: 0.03)
            XCTAssertTrue(motion.size.width.isFinite && motion.size.height.isFinite)
            XCTAssertGreaterThan(motion.size.height, 0)
        }
        motion.retarget(size: opened, expanded: true)
        motion.advance(by: 2)
        XCTAssertTrue(motion.isSettled)
        motion.finish(); XCTAssertEqual(motion.size, opened)
    }
    func testBlurAndFlipRevealHasCleanEndpoints() {
        let closed = IslandReveal(fraction: 0), middle = IslandReveal(fraction: 0.5), open = IslandReveal(fraction: 1)
        XCTAssertEqual(closed.bodyOpacity, 0); XCTAssertEqual(closed.compactOpacity, 1)
        XCTAssertGreaterThan(middle.bodyBlur, 0); XCTAssertGreaterThan(middle.bodyOpacity, 0)
        XCTAssertLessThan(middle.bodyOpacity, 1); XCTAssertLessThan(middle.tiltDegrees, 0)
        XCTAssertEqual(open.bodyBlur, 0); XCTAssertEqual(open.bodyOpacity, 1)
        XCTAssertEqual(open.bodyScale, 1); XCTAssertEqual(open.tiltDegrees, 0)
        XCTAssertEqual(open.compactOpacity, 0)
    }
}
