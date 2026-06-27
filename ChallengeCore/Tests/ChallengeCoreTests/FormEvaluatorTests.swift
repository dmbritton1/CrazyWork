import Testing
@testable import ChallengeCore

@Suite("FormEvaluator — body-line sag/pike against a straightness tolerance")
struct FormEvaluatorTests {

    /// Side-view frame. Convention: y increases upward (Vision normalized).
    /// Shoulder left, ankle right, hip in the middle at height `hipY`.
    private func frame(hipY: Double, confidence: Double = 0.9) -> PoseFrame {
        func jp(_ x: Double, _ y: Double) -> JointPoint {
            JointPoint(location: Point2D(x: x, y: y), confidence: confidence)
        }
        return PoseFrame(timestamp: 0, joints: [
            .leftShoulder: jp(0.0, 1.0), .rightShoulder: jp(0.0, 1.0),
            .leftHip: jp(1.0, hipY), .rightHip: jp(1.0, hipY),
            .leftAnkle: jp(2.0, 1.0), .rightAnkle: jp(2.0, 1.0),
        ])
    }

    @Test("a straight body is in good form with no issue")
    func straight() {
        let e = FormEvaluator(config: FormConfig(strictness: .lenient))
        let r = e.evaluate(frame(hipY: 1.0))
        #expect(r.isAcceptable)
        #expect(r.issue == nil)
    }

    @Test("dropped hips are flagged as sagging")
    func sag() {
        let e = FormEvaluator(config: FormConfig(strictness: .moderate))
        let r = e.evaluate(frame(hipY: 0.3))
        #expect(r.isAcceptable == false)
        #expect(r.issue == .sagging)
    }

    @Test("raised hips are flagged as piking")
    func pike() {
        let e = FormEvaluator(config: FormConfig(strictness: .moderate))
        let r = e.evaluate(frame(hipY: 1.7))
        #expect(r.isAcceptable == false)
        #expect(r.issue == .piking)
    }

    @Test("strict tolerance rejects a small deviation that lenient allows")
    func strictnessMatters() {
        let small = frame(hipY: 0.85)   // slight sag
        #expect(FormEvaluator(config: FormConfig(strictness: .lenient)).evaluate(small).isAcceptable)
        #expect(FormEvaluator(config: FormConfig(strictness: .strict)).evaluate(small).isAcceptable == false)
    }

    @Test("missing joints yield an unknown (non-failing) evaluation")
    func unknown() {
        let e = FormEvaluator(config: FormConfig(strictness: .strict))
        let r = e.evaluate(PoseFrame(timestamp: 0, joints: [:]))
        #expect(r.bodyLineAngle == nil)
        #expect(r.isAcceptable)        // can't judge -> don't punish
        #expect(r.issue == nil)
    }
}
