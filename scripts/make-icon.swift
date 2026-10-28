import AppKit
import Foundation

@main struct IconGenerator {
    static func main() throws {
        let folder = URL(fileURLWithPath: "build/AppIcon.iconset")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = size * scale, p = CGFloat(size * scale)
                guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32),
                    let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CocoaError(.fileWriteUnknown) }
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
                NSColor(calibratedRed: 0.045, green: 0.046, blue: 0.051, alpha: 1).setFill()
                NSBezierPath(roundedRect: NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88), xRadius: p * 0.20, yRadius: p * 0.20).fill()
                let context = NSGraphicsContext.current!.cgContext
                context.saveGState(); context.translateBy(x: 0, y: p); context.scaleBy(x: 1, y: -1)
                context.setFillColor(NSColor(calibratedRed: 9 / 255, green: 174 / 255, blue: 161 / 255, alpha: 1).cgColor)
                context.addPath(BrandMark.path(in: CGRect(x: p * 0.137, y: p * 0.137, width: p * 0.726, height: p * 0.726))); context.fillPath()
                context.restoreGState(); NSGraphicsContext.restoreGraphicsState()
                guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
                try data.write(to: folder.appendingPathComponent(name))
                if pixels == 512 && scale == 1 { try data.write(to: URL(fileURLWithPath: "Resources/Brand/tern-icon.png")) }
            }
        }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", folder.path, "-o", "Resources/AppIcon.icns"]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
