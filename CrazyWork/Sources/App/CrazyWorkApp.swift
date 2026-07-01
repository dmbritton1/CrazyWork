import SwiftUI
import SwiftData

@main
struct CrazyWorkApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .modelContainer(for: [WorkoutSession.self, ExerciseSet.self, SavedWorkout.self])
    }
}
