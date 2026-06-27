import Foundation

public enum Geometry {
    /// Interior angle in degrees at vertex `b` formed by points `a`-`b`-`c`.
    ///
    /// Returns a value in `0...180`. If either segment has zero length (a joint
    /// collapsed onto the vertex), there is no bend to measure, so we return
    /// `180` — treated as "straight" so a missing/garbage joint never fabricates
    /// a rep.
    public static func angle(_ a: Point2D, _ b: Point2D, _ c: Point2D) -> Double {
        let ux = a.x - b.x, uy = a.y - b.y
        let vx = c.x - b.x, vy = c.y - b.y

        let uLen = (ux * ux + uy * uy).squareRoot()
        let vLen = (vx * vx + vy * vy).squareRoot()
        guard uLen > 0, vLen > 0 else { return 180 }

        let cosine = (ux * vx + uy * vy) / (uLen * vLen)
        // Clamp to guard against floating-point drift outside [-1, 1].
        let clamped = min(1, max(-1, cosine))
        return acos(clamped) * 180 / .pi
    }
}
