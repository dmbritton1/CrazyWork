import SwiftUI

/// App root: tabs for the daily path, browsing/building plans, stats, history,
/// and profile. The workout builder is reached from the Plans tab's + button.
struct RootView: View {
    @State private var selection: Tab = .path
    @AppStorage("appearance") private var appearance = AppearanceMode.system

    private enum Tab: String { case path, plans, stats, history, profile }

    init() {
        ThemeAppearance.configure()
        // Screenshot/debug hook: `-startTab stats` (a launch argument lands in
        // UserDefaults) opens that tab first. No effect in normal launches.
        if let name = UserDefaults.standard.string(forKey: "startTab"), let tab = Tab(rawValue: name) {
            _selection = State(initialValue: tab)
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { PathView() }
                .tabItem { Label("Today", systemImage: "flag.checkered") }
                .tag(Tab.path)

            PremadePlansView()
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
