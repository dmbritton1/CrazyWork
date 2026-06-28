import SwiftUI
import SwiftData
import UIKit
import ChallengeCore

/// The live workout: real camera preview, an aligned skeleton overlay, a rep
/// HUD, form cues, rest between sets, and a saved summary at the end.
struct LiveWorkoutView: View {
    let plan: [PlannedSet]
    let restSeconds: Int
    let onComplete: (() -> Void)?
    @Environment(\.modelContext) private var modelContext
    @State private var coordinator: SessionCoordinator
    @State private var pipeline = PosePipeline()
    @State private var latestFrame: PoseFrame?
    @State private var latestImageSize: CGSize = .zero
    @State private var cameraDenied = false
    @State private var saved = false
    @State private var audioPlayer = WorkoutAudioPlayer()
    @AppStorage("workoutAudioEnabled") private var audioEnabled = true
    @AppStorage("healthSyncEnabled") private var healthSyncEnabled = false

    init(plan: [PlannedSet], restSeconds: Int, onComplete: (() -> Void)? = nil) {
        self.plan = plan
        self.restSeconds = restSeconds
        self.onComplete = onComplete
        _coordinator = State(initialValue: SessionCoordinator(plan: plan))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if coordinator.phase == .finished {
                SummaryView(results: coordinator.results)
            } else {
                if cameraDenied {
                    deniedView
                } else {
                    CameraPreview(previewLayer: pipeline.previewLayer).ignoresSafeArea()
                    SkeletonOverlay(frame: latestFrame, imageSize: latestImageSize).ignoresSafeArea()
                }

                VStack {
                    switch coordinator.phase {
                    case .active:
                        hud
                        cueBanner
                        Spacer()
                    case .resting:
                        Spacer()
                        RestCountdownView(seconds: restSeconds, nextExercise: exerciseName) {
                            coordinator.beginNextSet()
                        }
                        .id(coordinator.currentSetIndex)
                        Spacer()
                    case .idle, .finished:
                        ProgressView().tint(.white)
                    }
                }
                .padding()
            }
        }
        .statusBarHidden()
        .task { await run() }
        .onDisappear {
            pipeline.stop()
            UIApplication.shared.isIdleTimerDisabled = false // let the screen sleep again
            audioPlayer.end()
        }
        .onChange(of: audioEnabled) { _, enabled in audioPlayer.muted = !enabled }
    }

    // MARK: - HUD

    private var hud: some View {
        VStack(spacing: 8) {
            Button {
                audioEnabled.toggle()
            } label: {
                Image(systemName: audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(audioEnabled ? "Mute audio" : "Unmute audio")

            VStack(spacing: 2) {
                Text(progressText)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text("Set \(coordinator.currentSetIndex + 1) of \(plan.count) · \(exerciseName)")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    /// "7 / 12" for reps, "0:18 / 0:30" for a timed hold.
    private var progressText: String {
        switch coordinator.goalUnit {
        case .reps:
            return "\(Int(coordinator.currentProgress)) / \(coordinator.currentTarget)"
        case .seconds:
            return "\(Self.clock(coordinator.currentProgress)) / \(Self.clock(Double(coordinator.currentTarget)))"
        }
    }

    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    @ViewBuilder private var cueBanner: some View {
        if !coordinator.poseVisible {
            Label("Reposition so your whole body is in view", systemImage: "viewfinder")
                .padding()
                .background(.ultraThinMaterial, in: Capsule())
                .foregroundStyle(.white)
        } else if let cue = coordinator.lastFormCue {
            Label(cue, systemImage: "exclamationmark.triangle.fill")
                .typography(Typography.bodyStrong)
                .padding()
                .background(Palette.accentRedDeep, in: Capsule())
                .foregroundStyle(.white)
        }
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label("Camera access needed", systemImage: "camera.fill")
        } description: {
            Text("CrazyWork counts your reps on-device. Enable the camera in Settings.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var exerciseName: String {
        let id = plan.indices.contains(coordinator.currentSetIndex)
            ? plan[coordinator.currentSetIndex].exerciseID : ""
        return ExerciseRegistry.displayName(for: id)
    }

    // MARK: - Lifecycle

    private func run() async {
        coordinator.start()
        audioPlayer.muted = !audioEnabled
        UIApplication.shared.isIdleTimerDisabled = true // keep the screen awake mid-workout
        guard await CameraAuthorization.request() else {
            cameraDenied = true
            return
        }
        pipeline.attachPreview(position: .front)
        pipeline.configure(position: .front)
        pipeline.start()

        for await sample in pipeline.frames {
            latestFrame = sample.frame
            latestImageSize = sample.imageSize
            for event in coordinator.feed(sample.frame) { audioPlayer.handle(event) }
            if coordinator.phase == .finished { break }
        }
        pipeline.stop() // camera off once the workout completes
        if coordinator.phase == .finished { saveIfNeeded() } // persist the moment it ends
    }

    private func saveIfNeeded() {
        guard !saved else { return }
        saved = true
        let session = WorkoutSession(startedAt: Date())
        for (i, r) in coordinator.results.enumerated() {
            let set = ExerciseSet(exerciseID: r.exerciseID, goalUnit: r.goalUnit.rawValue,
                                  target: r.target, order: i)
            set.completed = r.completed
            set.averageFormScore = r.averageFormScore
            set.findingsSummary = r.findingsSummary
            session.sets.append(set)
        }
        session.endedAt = Date()
        modelContext.insert(session)
        do {
            try modelContext.save()
            onComplete?() // advance the path only when the session actually persisted
        } catch {
            assertionFailure("Failed to save workout: \(error)") // don't silently lose history
        }

        guard healthSyncEnabled else { return }
        let results = coordinator.results
        let start = session.startedAt
        let end = session.endedAt ?? Date()
        Task {
            let body = await HealthStore.shared.body()
            let minutes = max(0, end.timeIntervalSince(start)) / 60
            let kcal = CalorieEstimator.kilocalories(results: results, durationMinutes: minutes, body: body)
            try? await HealthStore.shared.save(start: start, end: end, activeEnergyKcal: kcal)
        }
    }
}
