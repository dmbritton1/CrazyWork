import Testing
import Foundation
@testable import CrazyWork

struct WatchMessageTests {
    @Test func roundTripsEveryCase() throws {
        let messages: [WatchMessage] = [
            .metrics(heartRate: 132.5, activeEnergyKcal: 41.2),
            .progress(exerciseName: "Push-up", value: 7, target: 12,
                      setIndex: 1, setCount: 3, phase: .active),
            .haptic(.setComplete),
            .end,
            .ended(activeEnergyKcal: 87.0),
        ]
        for message in messages {
            let decoded = try WatchMessage.decode(try message.encoded())
            #expect(decoded == message)
        }
    }

    @Test func decodeRejectsGarbage() {
        #expect(throws: (any Error).self) {
            _ = try WatchMessage.decode(Data("not json".utf8))
        }
    }
}
