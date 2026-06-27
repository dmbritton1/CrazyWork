import SwiftUI
import SwiftData
import UIKit
import ChallengeCore

struct LiveWorkoutView: View {
    let plan: [PlannedSet]
    @Environment(\.modelContext) private var modelContext
    @State private var coordinator: SessionCoordinator
    @State private var pipeline: PosePipeline?
    @State private var latestJoints: [JointName: Joint] = [:]
    @State private var saved = false
    @State private var cameraDenied = false

    init(plan: [PlannedSet]) {
        self.plan = plan
        _coordinator = State(initialValue: SessionCoordinator(plan: plan))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            SkeletonOverlay(joints: latestJoints).ignoresSafeArea()

            VStack {
                if cameraDenied {
                    VStack(spacing: 12) {
                        Text("Camera access is off").font(.title2).foregroundStyle(.white)
                        Text("CrazyWork needs the camera to count your reps.").foregroundStyle(.secondary)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }.buttonStyle(.borderedProminent)
                    }
                } else if coordinator.phase == .active {
                    let set = plan[coordinator.currentSetIndex]
                    Text("Set \(coordinator.currentSetIndex + 1)/\(plan.count) · \(coordinator.currentReps)/\(set.targetReps)")
                        .font(.title2).foregroundStyle(.white)
                    Text("\(coordinator.currentReps)").font(.system(size: 96, weight: .bold)).foregroundStyle(.white)
                    cueText
                } else if coordinator.phase == .resting {
                    Text("Rest").font(.largeTitle).foregroundStyle(.white)
                    Button("Next set") { coordinator.beginNextSet() }.buttonStyle(.borderedProminent)
                } else if coordinator.phase == .finished {
                    SummaryView(results: coordinator.results)
                        .onAppear { saveIfNeeded() }
                }
            }
            .padding()
        }
        .onAppear { coordinator.start(); Task { await startCamera() } }
        .onDisappear { pipeline?.stop() }
    }

    @ViewBuilder private var cueText: some View {
        switch coordinator.status {
        case .outOfFrame: Text("Step back so I can see you").foregroundStyle(.yellow)
        case .lowConfidence: Text("Improve lighting").foregroundStyle(.yellow)
        case .tracking:
            if let f = coordinator.lastFindings.first {
                Text(cue(for: f)).foregroundStyle(.orange)
            }
        }
    }

    private func cue(for f: Finding) -> String {
        switch f {
        case .shallowDepth: return "Go deeper"
        case .backNotStraight: return "Straighten your back"
        case .torsoLean: return "Keep your chest up"
        case .kneesCaving: return "Push your knees out"
        }
    }

    private func startCamera() async {
        switch CameraAuthorization.current {
        case .denied:
            cameraDenied = true
            return
        case .undetermined:
            let granted = await CameraAuthorization.request()
            if !granted { cameraDenied = true; return }
        case .authorized:
            break
        }
        let p = PosePipeline(onPoseFrame: { frame in
            latestJoints = frame.joints
            coordinator.feed(frame)
        })
        do { try p.startThrowing(); pipeline = p } catch { cameraDenied = true }
    }

    private func saveIfNeeded() {
        guard !saved else { return }
        saved = true
        let session = WorkoutSession(startedAt: Date())
        for (i, r) in coordinator.results.enumerated() {
            let set = ExerciseSet(exerciseID: r.exerciseID, targetReps: r.targetReps, order: i)
            set.completedReps = r.completedReps
            set.averageFormScore = r.averageFormScore
            set.findingsSummary = r.findingsSummary
            session.sets.append(set)
        }
        session.endedAt = Date()
        modelContext.insert(session)
        try? modelContext.save()
    }
}
