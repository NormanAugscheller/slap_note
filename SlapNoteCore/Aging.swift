import CoreGraphics
import Foundation

public struct AgingPolicy: Equatable, Sendable {
    public var enabled: Bool
    /// Days without a touch before the corner starts curling (1...60).
    public var thresholdDays: Int
    /// Days over which the curl grows from 0 to its maximum after the threshold.
    public var rampDays: Double

    public static let dayRange = 1...60

    public init(enabled: Bool = true, thresholdDays: Int = 7, rampDays: Double = 7) {
        self.enabled = enabled
        self.thresholdDays = min(max(thresholdDays, Self.dayRange.lowerBound), Self.dayRange.upperBound)
        self.rampDays = max(rampDays, 0.01)
    }
}

public enum Aging {
    /// Curl amount 0...1 (1 = maximum curl) for a note last touched at `lastTouched`.
    public static func curl(lastTouched: Date, now: Date, policy: AgingPolicy) -> Double {
        guard policy.enabled else { return 0 }
        let days = now.timeIntervalSince(lastTouched) / 86_400
        let t = (days - Double(policy.thresholdDays)) / policy.rampDays
        guard t > 0 else { return 0 }
        let x = min(t, 1)
        // Smoothstep: starts gently, approaches the maximum gently.
        return x * x * (3 - 2 * x)
    }
}

/// Geometry of the folded ("dog-ear") corner at the bottom-right of a note.
public struct CurlGeometry {
    /// Paper that is still flat.
    public var remaining: CGPath
    /// The folded-over flap (reflection of the cut-off corner across the fold line).
    public var flap: CGPath?
    /// Two points on the fold line, for drawing the crease shadow.
    public var foldLine: (CGPoint, CGPoint)?

    /// Largest fold depth relative to the shorter note side.
    public static let maxFoldFraction: CGFloat = 0.24

    /// Builds the curl for `shapePath` (filling `rect`, y axis up). The fold runs at 45° across the
    /// bottom-right corner and starts at the outline, so it also works for circles and hearts.
    public static func make(shapePath: CGPath, rect: CGRect, curl: Double) -> CurlGeometry {
        let amount = CGFloat(min(max(curl, 0), 1))
        guard amount > 0.001 else { return CurlGeometry(remaining: shapePath, flap: nil, foldLine: nil) }
        // Unit vector pointing from the bottom-right corner toward the note's top-left.
        let u = CGPoint(x: -1 / CGFloat(2).squareRoot(), y: 1 / CGFloat(2).squareRoot())
        let corner = CGPoint(x: rect.maxX, y: rect.minY)
        // How far the outline sits from the corner along u (0 for square shapes).
        let samples = PathSampler.points(of: shapePath, count: 160)
        let support = samples.map { ($0.x - corner.x) * u.x + ($0.y - corner.y) * u.y }.min() ?? 0
        let depth = amount * min(rect.width, rect.height) * maxFoldFraction
        let offset = max(support, 0) + depth
        let lineCenter = CGPoint(x: corner.x + u.x * offset, y: corner.y + u.y * offset)
        let tangent = CGPoint(x: u.y, y: -u.x)
        let big = (rect.width + rect.height) * 2
        // Half-plane on the corner side of the fold line.
        let half = CGMutablePath()
        let a = CGPoint(x: lineCenter.x + tangent.x * big, y: lineCenter.y + tangent.y * big)
        let b = CGPoint(x: lineCenter.x - tangent.x * big, y: lineCenter.y - tangent.y * big)
        half.move(to: a)
        half.addLine(to: b)
        half.addLine(to: CGPoint(x: b.x - u.x * big, y: b.y - u.y * big))
        half.addLine(to: CGPoint(x: a.x - u.x * big, y: a.y - u.y * big))
        half.closeSubpath()

        let remaining = shapePath.subtracting(half)
        let cut = shapePath.intersection(half)
        // Reflection across the fold line: p' = p - 2((p - L)·u)u. For u = (-1, 1)/√2 the linear
        // part swaps x and y.
        let k = 2 * (lineCenter.x * u.x + lineCenter.y * u.y)
        var reflect = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: k * u.x, ty: k * u.y)
        let flap = cut.copy(using: &reflect)
        let lineHits = samples.filter { abs(($0.x - lineCenter.x) * u.x + ($0.y - lineCenter.y) * u.y) < 2 }
        let ends: (CGPoint, CGPoint)?
        if let first = lineHits.min(by: { $0.x < $1.x }), let last = lineHits.max(by: { $0.x < $1.x }) {
            ends = (first, last)
        } else {
            ends = nil
        }
        return CurlGeometry(remaining: remaining, flap: flap, foldLine: ends)
    }

    /// Reflects a point across the fold line defined by `lineCenter` and unit normal `u`.
    public static func reflect(_ p: CGPoint, lineCenter: CGPoint, normal u: CGPoint) -> CGPoint {
        let d = (p.x - lineCenter.x) * u.x + (p.y - lineCenter.y) * u.y
        return CGPoint(x: p.x - 2 * d * u.x, y: p.y - 2 * d * u.y)
    }
}
