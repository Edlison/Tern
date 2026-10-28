import CoreGraphics

/// An original folded-wing mark, shared by the app and icon generator.
public enum BrandMark {
    public static func path(in rect: CGRect) -> CGPath {
        let p = CGMutablePath()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: point(0.08, 0.27))
        p.addLine(to: point(0.48, 0.43))
        p.addLine(to: point(0.91, 0.18))
        p.addLine(to: point(0.66, 0.62))
        p.addLine(to: point(0.45, 0.79))
        p.addLine(to: point(0.50, 0.54))
        p.addLine(to: point(0.30, 0.59))
        p.closeSubpath()
        return p
    }
}
