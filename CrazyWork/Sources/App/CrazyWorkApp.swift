import SwiftUI
import SwiftData

@main
struct CrazyWorkApp: App {
    var body: some Scene {
        WindowGroup {
            BuildWorkoutView()
        }
        .modelContainer(for: [WorkoutSession.self, ExerciseSet.self])
    }
}
