import Testing
@testable import ChallengeCore

@Suite("MovingAverage — smooths jittery joint angles before thresholding")
struct MovingAverageTests {

    @Test("window of 1 is a passthrough")
    func passthrough() {
        var ma = MovingAverage(windowSize: 1)
        #expect(ma.add(10) == 10)
        #expect(ma.add(20) == 20)
    }

    @Test("averages over the window once full")
    func averages() {
        var ma = MovingAverage(windowSize: 3)
        #expect(ma.add(30) == 30)            // [30]
        #expect(ma.add(60) == 45)            // [30,60]
        #expect(ma.add(90) == 60)            // [30,60,90]
        #expect(ma.add(120) == 90)           // [60,90,120] — oldest dropped
    }

    @Test("window size below 1 is treated as 1")
    func clampsWindow() {
        var ma = MovingAverage(windowSize: 0)
        #expect(ma.add(42) == 42)
    }
}
