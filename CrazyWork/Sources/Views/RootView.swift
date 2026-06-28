import SwiftUI

/// App root: tabs for building/running a workout, browsing premade plans, and
/// viewing history. Owns the editable workout draft (`entries` + `restSeconds`)
/// shared by the first two tabs.
struct RootView: View {
    @State private var entries: [WorkoutEntry] = []
    @State private var restSeconds: Int = 30
    @State private var selection: Tab = .path
    @AppStorage("appearance") private var appearance = AppearanceMode.system

    private enum Tab { case path, workout, plans, stats, history, profile }

    init() { ThemeAppearance.configure() }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { PathView() }
                .tabItem { Label("Today", systemImage: "flag.checkered") }
                .tag(Tab.path)

            BuildWorkoutView(entries: $entries, restSeconds: $restSeconds)
                .tabItem { Label("Workout", systemImage: "figure.strengthtraining.traditional") }
                .tag(Tab.workout)

            PremadePlansView { plan in
                entries = plan.entries
                restSeconds = plan.restSeconds
                selection = .workout
            }
            .tabItem { Label("Plans", systemImage: "list.bullet.rectangle") }
            .tag(Tab.plans)

            NavigationStack { StatsView() }
                .tabItem { Label("Stats", systemImage: "chart.xyaxis.line") }
                .tag(Tab.stats)

            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)

            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .tint(Palette.onDark)
        .preferredColorScheme(appearance.colorScheme)
    }
}
