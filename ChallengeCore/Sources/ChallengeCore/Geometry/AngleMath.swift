import Foundation

public enum AngleMath {
    /// Angle in degrees (0...180) at `vertex` between the rays to `a` and `b`.
    /// Returns 0 if either ray has zero length.
    public static func angle(at vertex: Point2D, from a: Point2D, to b: Point2D) -> Double {
        let v1 = Point2D(x: a.x - vertex.x, y: a.y - vertex.y)
        let v2 = Point2D(x: b.x - vertex.x, y: b.y - vertex.y)
        let mag1 = (v1.x * v1.x + v1.y * v1.y).squareRoot()
        let mag2 = (v2.x * v2.x + v2.y * v2.y).squareRoot()
        guard mag1 > 0, mag2 > 0 else { return 0 }
        let dot = v1.x * v2.x + v1.y * v2.y
        let cosine = min(1, max(-1, dot / (mag1 * mag2)))
        return acos(cosine) * 180 / .pi
    }
}
