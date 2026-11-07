import CoreGraphics
import Foundation

public enum PathSampler {
    /// Flattens a path into a polyline (all subpaths concatenated).
    public static func polyline(of path: CGPath, segmentsPerCurve: Int = 16) -> [CGPoint] {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        var start = CGPoint.zero
        path.applyWithBlock { pointer in
            let e = pointer.pointee
            switch e.type {
            case .moveToPoint:
                current = e.points[0]
                start = current
                points.append(current)
            case .addLineToPoint:
                current = e.points[0]
                points.append(current)
            case .addQuadCurveToPoint:
                let c = e.points[0], end = e.points[1]
                for i in 1...segmentsPerCurve {
                    let t = CGFloat(i) / CGFloat(segmentsPerCurve)
                    let mt = 1 - t
                    points.append(CGPoint(x: mt * mt * current.x + 2 * mt * t * c.x + t * t * end.x,
                                          y: mt * mt * current.y + 2 * mt * t * c.y + t * t * end.y))
                }
                current = end
            case .addCurveToPoint:
                let c1 = e.points[0], c2 = e.points[1], end = e.points[2]
                for i in 1...segmentsPerCurve {
                    let t = CGFloat(i) / CGFloat(segmentsPerCurve)
                    let mt = 1 - t
                    let a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t, d = t * t * t
                    points.append(CGPoint(x: a * current.x + b * c1.x + c * c2.x + d * end.x,
                                          y: a * current.y + b * c1.y + c * c2.y + d * end.y))
                }
                current = end
            case .closeSubpath:
                if current != start { points.append(start) }
                current = start
            @unknown default:
                break
            }
        }
        return points
    }

    /// `count` points evenly spaced by arc length along the outline.
    public static func points(of path: CGPath, count: Int) -> [CGPoint] {
        let poly = polyline(of: path)
        guard poly.count > 1, count > 0 else { return poly }
        var lengths: [CGFloat] = [0]
        for i in 1..<poly.count {
            lengths.append(lengths[i - 1] + hypot(poly[i].x - poly[i - 1].x, poly[i].y - poly[i - 1].y))
        }
        let total = lengths.last ?? 0
        guard total > 0 else { return Array(repeating: poly[0], count: count) }
        var result: [CGPoint] = []
        result.reserveCapacity(count)
        var seg = 1
        for i in 0..<count {
            let target = total * CGFloat(i) / CGFloat(count)
            while seg < poly.count - 1 && lengths[seg] < target { seg += 1 }
            let l0 = lengths[seg - 1], l1 = lengths[seg]
            let t = l1 > l0 ? (target - l0) / (l1 - l0) : 0
            let p0 = poly[seg - 1], p1 = poly[seg]
            result.append(CGPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t))
        }
        return result
    }

    /// Polygon area (shoelace), positive for counter-clockwise outlines.
    public static func signedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 2 else { return 0 }
        var sum: CGFloat = 0
        for i in 0..<points.count {
            let a = points[i], b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    public static func polygonPath(_ points: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }
}

/// Shapes for the "crumple into a paper ball" animation. All frames have the same number of
/// points, so Core Animation can interpolate between them smoothly.
public enum Crumple {
    public static let pointCount = 96

    /// The note outline as an evenly sampled, counter-clockwise polygon starting at the point with
    /// the smallest angle from the center (so it lines up with the ball and does not twist).
    public static func outline(of path: CGPath) -> [CGPoint] {
        var pts = PathSampler.points(of: path, count: pointCount)
        if PathSampler.signedArea(pts) < 0 { pts.reverse() }
        let box = path.boundingBoxOfPath
        let c = CGPoint(x: box.midX, y: box.midY)
        let startIndex = pts.indices.min { angle(pts[$0], c) < angle(pts[$1], c) } ?? 0
        return Array(pts[startIndex...] + pts[..<startIndex])
    }

    static func angle(_ p: CGPoint, _ c: CGPoint) -> CGFloat {
        let a = atan2(p.y - c.y, p.x - c.x)
        return a < 0 ? a + 2 * .pi : a
    }

    /// An irregular, crinkled ball outline around `center`.
    public static func ball(center: CGPoint, radius: CGFloat, seed: UInt64) -> [CGPoint] {
        var rng = SplitMix64(seed: seed)
        return (0..<pointCount).map { i in
            let a = 2 * CGFloat.pi * CGFloat(i) / CGFloat(pointCount)
            let jitter: CGFloat = (i % 3 == 0) ? CGFloat(rng.nextUnit()) * 0.28 : CGFloat(rng.nextUnit()) * 0.1
            let r = radius * (0.86 + jitter)
            return CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
        }
    }

    /// Intermediate frame between outline and ball; `t` in 0...1. Mid-way frames get extra
    /// wrinkles so the morph looks like crumpling, not like a smooth scale.
    public static func frame(from a: [CGPoint], to b: [CGPoint], t: CGFloat, seed: UInt64) -> [CGPoint] {
        precondition(a.count == b.count)
        var rng = SplitMix64(seed: seed &+ UInt64(t * 1000))
        let wrinkle = sin(t * .pi) * 0.12
        let cx = b.reduce(0) { $0 + $1.x } / CGFloat(b.count)
        let cy = b.reduce(0) { $0 + $1.y } / CGFloat(b.count)
        return zip(a, b).map { p, q in
            let x = p.x + (q.x - p.x) * t
            let y = p.y + (q.y - p.y) * t
            let n = 1 - wrinkle * CGFloat(rng.nextUnit())
            return CGPoint(x: cx + (x - cx) * n, y: cy + (y - cy) * n)
        }
    }
}

/// Small deterministic RNG so animations and tests are reproducible.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform value in 0..<1.
    public mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
