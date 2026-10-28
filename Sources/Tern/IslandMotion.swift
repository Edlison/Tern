import AppKit
import Combine
import TernCore
import QuartzCore

/// Animation publications stay local to the notch; the session store and dashboard do not tick.
@MainActor final class IslandMotion: ObservableObject {
    @Published private(set) var sample = Sample(size: CGSize(width: 248, height: 32), fraction: 0)
    @Published private(set) var expandedSize = CGSize(width: 610, height: 400)
    @Published private(set) var mountsExpandedContent = false
    struct Sample {
        var size: CGSize
        var fraction: Double
        var reveal: IslandReveal { IslandReveal(fraction: fraction) }
    }
    func prepare(expandedSize: CGSize, expanded: Bool) {
        if self.expandedSize != expandedSize { self.expandedSize = expandedSize }
        if expanded { mountsExpandedContent = true }
    }
    func present(_ morph: IslandMorph) {
        sample = Sample(size: morph.size, fraction: morph.fraction)
        if morph.isSettled && morph.fraction == 0 { mountsExpandedContent = false }
    }
}

/// CADisplayLink retains its target. Keep the controller out of that ownership cycle.
@MainActor final class IslandDisplayLinkTarget: NSObject {
    var tick: ((CADisplayLink) -> Void)?
    @objc func displayTick(_ link: CADisplayLink) { tick?(link) }
}
