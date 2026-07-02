import SwiftUI
import SwiftData

@main
struct CrazyWorkApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
            #if DEBUG
                .modifier(DemoSeed())
            #endif
        }
        .modelContainer(for: [WorkoutSession.self, ExerciseSet.self, SavedWorkout.self])
    }
}

#if DEBUG
/// Screenshot/debug hook: launching with `-seedDemo YES` fills an empty store
/// with two weeks of plausible sessions so Stats/History render with data.
private struct DemoSeed: ViewModifier {
    @Environment(\.modelContext) private var context

    func body(content: Content) -> some View {
        content.task {
            guard UserDefaults.standard.bool(forKey: "seedDemo"),
                  (try? context.fetchCount(FetchDescriptor<WorkoutSession>())) == 0 else { return }
            let exercises = ["pushup", "squat", "plank", "lunge"]
            for daysAgo in stride(from: 13, through: 0, by: -1) where daysAgo % 5 != 3 {
                let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
                let session = WorkoutSession(startedAt: start)
                for (i, id) in exercises.prefix(daysAgo % 3 + 2).enumerated() {
                    let timed = id == "plank"
                    let set = ExerciseSet(exerciseID: id, goalUnit: timed ? "seconds" : "reps",
                                          target: timed ? 30 : 12, order: i)
                    set.completed = timed ? Double(20 + daysAgo) : Double(8 + (13 - daysAgo) % 5)
                    set.averageFormScore = 0.72 + Double((13 - daysAgo)) * 0.015
                    session.sets.append(set)
                }
                session.endedAt = start.addingTimeInterval(600)
                context.insert(session)
            }
        }
    }
}
#endif
