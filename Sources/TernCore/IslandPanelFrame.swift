import Foundation
import CoreGraphics

public enum IslandPanelFrame {
    /// Width and height change together. The destination's top edge and center never interpolate.
    public static func interpolate(from: CGRect, to: CGRect, progress: Double) -> CGRect {
        let t = CGFloat(min(1, max(0, progress)))
        let width = from.width + (to.width - from.width) * t
        let height = from.height + (to.height - from.height) * t
        return CGRect(x: to.midX - width / 2, y: to.maxY - height, width: width, height: height)
    }
}
