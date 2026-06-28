import SwiftUI
import SwiftData

/// App appearance preference, persisted via `@AppStorage` (String-backed).
enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// The Profile tab: an editable name, a quick lifetime summary, and the app's
/// settings (sound & voice, appearance).
struct ProfileView: View {
    @AppStorage("displayName") private var displayName = "Athlete"
    @AppStorage("workoutAudioEnabled") private var audioEnabled = true
    @AppStorage("appearance") private var appearance = AppearanceMode.system
    @Query private var sessions: [WorkoutSession]

    private var stats: ProgressStats {
        ProgressStats(summaries: sessions.map(\.summary))
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $displayName)
                    .font(.title3.weight(.semibold))
                HStack {
                    stat("Workouts", "\(stats.totalWorkouts)")
                    Spacer()
                    stat("Streak", "\(stats.currentStreak)d")
                }
            }
            Section("Settings") {
                Toggle("Sound & voice", isOn: $audioEnabled)
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }
        }
        .navigationTitle("Profile")
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
