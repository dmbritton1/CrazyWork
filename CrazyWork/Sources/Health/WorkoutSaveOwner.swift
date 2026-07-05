/// Exactly one device writes the HKWorkout. The watch owns the save only
/// when its session ended cleanly (acknowledged `.end`) AND it actually
/// measured energy; anything else falls back to the phone's estimate path.
enum WorkoutSaveOwner: Equatable {
    case watch, phone

    static func decide(watchAcknowledgedEnd: Bool, watchEnergyKcal: Double?) -> WorkoutSaveOwner {
        watchAcknowledgedEnd && (watchEnergyKcal ?? 0) > 0 ? .watch : .phone
    }
}
