import Foundation
import CoreGraphics

/// Exact critically damped spring integration, independent of the display's frame interval.
public struct IslandSpring: Sendable {
    public private(set) var value: Double
    public private(set) var velocity: Double = 0
    public private(set) var target: Double
    public init(_ value: Double) { self.value = value; target = value }
    public mutating func retarget(_ target: Double) { self.target = target }
    public mutating func advance(by delta: Double, frequency: Double) {
        guard delta > 0, delta.isFinite else { return }
        let displacement = value - target
        let coefficient = velocity + frequency * displacement
        let decay = exp(-frequency * delta)
        value = target + (displacement + coefficient * delta) * decay
        velocity = (velocity - frequency * coefficient * delta) * decay
    }
    public func isSettled(tolerance: Double) -> Bool {
        abs(value - target) < tolerance && abs(velocity) < tolerance * 12
    }
    public mutating func finish() { value = target; velocity = 0 }
}

public struct IslandMorph: Sendable {
    public private(set) var width: IslandSpring
    public private(set) var height: IslandSpring
    public private(set) var openness: IslandSpring
    public init(size: CGSize, expanded: Bool = false) {
        width = IslandSpring(size.width); height = IslandSpring(size.height)
        openness = IslandSpring(expanded ? 1 : 0)
    }
    public var size: CGSize { CGSize(width: max(1, width.value), height: max(1, height.value)) }
    public var fraction: Double { min(1, max(0, openness.value)) }
    public var isSettled: Bool { width.isSettled(tolerance: 0.15) && height.isSettled(tolerance: 0.15) && openness.isSettled(tolerance: 0.001) }
    public mutating func retarget(size: CGSize, expanded: Bool) {
        width.retarget(size.width); height.retarget(size.height); openness.retarget(expanded ? 1 : 0)
    }
    public mutating func advance(by delta: Double) {
        let frequency = openness.target == 1 ? 23.0 : 28.0
        width.advance(by: delta, frequency: frequency)
        height.advance(by: delta, frequency: frequency)
        openness.advance(by: delta, frequency: frequency)
    }
    public mutating func finish() { width.finish(); height.finish(); openness.finish() }
}

public struct IslandReveal: Equatable, Sendable {
    public var bodyOpacity: Double
    public var bodyBlur: Double
    public var bodyScale: Double
    public var tiltDegrees: Double
    public var compactOpacity: Double
    public var compactBlur: Double
    public init(fraction: Double) {
        let p = min(1, max(0, fraction))
        func smooth(_ t: Double) -> Double { let x = min(1, max(0, t)); return x * x * (3 - 2 * x) }
        bodyOpacity = smooth((p - 0.16) / 0.7)
        bodyBlur = 9 * pow(1 - p, 1.35)
        bodyScale = 0.965 + 0.035 * p
        tiltDegrees = -5 * (1 - p)
        compactOpacity = 1 - smooth(p / 0.38)
        compactBlur = 5 * p
    }
}
