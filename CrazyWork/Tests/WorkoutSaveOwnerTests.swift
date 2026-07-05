import Testing
@testable import CrazyWork

struct WorkoutSaveOwnerTests {
    @Test func watchOwnsWhenAcknowledgedWithEnergy() {
        #expect(WorkoutSaveOwner.decide(watchAcknowledgedEnd: true, watchEnergyKcal: 87.0) == .watch)
    }

    @Test func phoneOwnsWithoutAcknowledgement() {
        #expect(WorkoutSaveOwner.decide(watchAcknowledgedEnd: false, watchEnergyKcal: 87.0) == .phone)
    }

    @Test func phoneOwnsWhenWatchMeasuredNothing() {
        #expect(WorkoutSaveOwner.decide(watchAcknowledgedEnd: true, watchEnergyKcal: 0) == .phone)
        #expect(WorkoutSaveOwner.decide(watchAcknowledgedEnd: true, watchEnergyKcal: nil) == .phone)
    }
}
