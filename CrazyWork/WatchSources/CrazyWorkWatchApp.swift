import SwiftUI
import HealthKit
import WatchKit

@main
struct CrazyWorkWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            Text("Start a workout on your iPhone")
                .multilineTextAlignment(.center)
        }
    }
}

/// Receives the workout configuration when the phone launches us via
/// HKHealthStore.startWatchApp. Task 3 wires this to the session controller.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        // Filled in by Task 3.
    }
}
