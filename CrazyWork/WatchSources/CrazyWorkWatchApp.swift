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

/// Live wrist display: exercise, rep/hold count vs target, set x of y, heart
/// rate — or a rest screen between sets. Falls back to HR-only until the
/// first progress message arrives.
struct WatchWorkoutView: View {
    @State private var controller = WatchSessionController.shared

    var body: some View {
        VStack(spacing: 6) {
            if controller.isRunning {
                if let p = controller.progress {
                    progressBody(p)
                } else {
                    heartRateLabel(size: 40)
                    Text("Workout in progress")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Start a workout on your iPhone")
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private func progressBody(_ p: WorkoutProgress) -> some View {
        switch p.phase {
        case .resting:
            Text("Rest").font(.headline).foregroundStyle(.secondary)
            Text("Next: \(p.exerciseName)")
                .font(.body)
                .multilineTextAlignment(.center)
            heartRateLabel(size: 24)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            Text("Workout complete").font(.headline)
        case .active:
            Text(p.exerciseName)
                .font(.headline)
                .lineLimit(1)
            Text("\(p.value) / \(p.target)")
                .font(.system(size: 40, weight: .semibold, design: .rounded))
            Text("Set \(p.setIndex + 1) of \(p.setCount)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            heartRateLabel(size: 20)
        }
    }

    private func heartRateLabel(size: CGFloat) -> some View {
        Label {
            Text(controller.heartRate.map { "\(Int($0))" } ?? "--")
                .font(.system(size: size, weight: .semibold, design: .rounded))
        } icon: {
            Image(systemName: "heart.fill").foregroundStyle(.red)
        }
    }
}
