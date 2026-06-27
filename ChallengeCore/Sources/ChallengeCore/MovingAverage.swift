/// Simple fixed-window moving average. Raw Vision joints jitter frame-to-frame,
/// so the rep counter smooths the rep angle through this before thresholding.
///
/// A value type with a tiny ring buffer — deterministic and trivial to replay
/// in tests. Swap in a One-Euro filter later behind the same `add` interface if
/// latency-vs-smoothness needs tuning.
public struct MovingAverage: Sendable {
    private let windowSize: Int
    private var samples: [Double] = []

    public init(windowSize: Int) {
        self.windowSize = max(1, windowSize)
    }

    /// Adds a sample and returns the current average over the window.
    public mutating func add(_ value: Double) -> Double {
        samples.append(value)
        if samples.count > windowSize {
            samples.removeFirst(samples.count - windowSize)
        }
        return samples.reduce(0, +) / Double(samples.count)
    }
}
