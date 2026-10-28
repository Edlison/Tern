import Foundation

/// Five diagonal streams cycle through active provider colors; no completion color is inferred.
public enum SignalPattern {
    public struct Cell: Equatable { public var providerIndex: Int; public var opacity: Double }
    public static func cell(column: Int, row: Int, time: Double, providerCount: Int) -> Cell {
        guard providerCount > 0 else {
            // A slow, asymmetric field of independent lights; no central row/column bias.
            let seed = Double((column * 73 + row * 151 + column * row * 19 + 37) % 257)
            let phase = seed * 0.113
            let drift = sin(time * (0.34 + seed / 1600) + phase)
            let shimmer = sin(time * 0.71 + phase * 1.73)
            return Cell(providerIndex: 0, opacity: 0.10 + 0.28 * pow((drift + 1) / 2, 2) + 0.08 * (shimmer + 1) / 2)
        }
        let progress = time * 2.2 + Double(column) * 0.65
        let head = progress.truncatingRemainder(dividingBy: 7)
        let distance = (head - Double(row) + 7).truncatingRemainder(dividingBy: 7)
        let glow = max(0, 1 - distance / 3.2)
        let band = Int(floor((progress - Double(row)) / 7))
        let index = ((band + column) % providerCount + providerCount) % providerCount
        return Cell(providerIndex: index, opacity: 0.10 + 0.9 * glow * glow)
    }
}
