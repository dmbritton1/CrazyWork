import Foundation

/// Detects a completed down->up rep using two angle thresholds.
/// A rep counts when the angle drops below `downThreshold`, stays down at
/// least `minRepDuration`, then rises back above `upThreshold`.
public struct HysteresisRepDetector {
    public enum Phase: Sendable { case waitingForDown, waitingForUp }

    public let downThreshold: Double
    public let upThreshold: Double
    public let minRepDuration: TimeInterval

    public private(set) var phase: Phase = .waitingForDown
    private var downEnteredAt: TimeInterval?

    public init(downThreshold: Double, upThreshold: Double, minRepDuration: TimeInterval) {
        self.downThreshold = downThreshold
        self.upThreshold = upThreshold
        self.minRepDuration = minRepDuration
    }

    /// Returns true on the frame where a rep completes.
    public mutating func update(angle: Double, timestamp: TimeInterval) -> Bool {
        switch phase {
        case .waitingForDown:
            if angle <= downThreshold {
                phase = .waitingForUp
                downEnteredAt = timestamp
            }
            return false
        case .waitingForUp:
            if angle >= upThreshold {
                let longEnough = (timestamp - (downEnteredAt ?? timestamp)) >= minRepDuration
                phase = .waitingForDown
                downEnteredAt = nil
                return longEnough
            }
            return false
        }
    }

    public mutating func reset() {
        phase = .waitingForDown
        downEnteredAt = nil
    }
}
