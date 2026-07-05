import SwiftUI
import HealthKit
import WatchKit

@main
struct CrazyWorkWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            WatchWorkoutView()
        }
    }
}

/// Receives the workout configuration when the phone launches us via
/// HKHealthStore.startWatchApp.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await WatchSessionController.shared.begin(with: workoutConfiguration)
        }
    }
}

/// Phase 1 screen: "in progress" plus live heart rate. Phase 4 replaces this
/// with full workout progress.
struct WatchWorkoutView: View {
    @State private var controller = WatchSessionController.shared

    var body: some View {
        VStack(spacing: 8) {
            if controller.isRunning {
                Label {
                    Text(controller.heartRate.map { "\(Int($0))" } ?? "--")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                } icon: {
                    Image(systemName: "heart.fill").foregroundStyle(.red)
                }
                Text("Workout in progress")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Start a workout on your iPhone")
                    .multilineTextAlignment(.center)
            }
        }
    }
}
