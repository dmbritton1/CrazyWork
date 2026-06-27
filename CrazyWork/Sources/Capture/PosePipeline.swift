import AVFoundation
import Vision
import ChallengeCore

/// Runs Vision pose detection on camera frames and delivers each mapped
/// `PoseFrame` on the main actor via a sendable callback.
///
/// The pipeline is intentionally decoupled from `SessionCoordinator`: it only
/// ever moves the `Sendable` `PoseFrame` across the concurrency boundary, which
/// keeps it clean under Swift 6 strict concurrency. Callers wire it to the
/// coordinator with `{ frame in coordinator.feed(frame) }`.
final class PosePipeline {
    private let camera = CameraSession()
    private let onPoseFrame: @MainActor (PoseFrame) -> Void

    init(onPoseFrame: @escaping @MainActor (PoseFrame) -> Void) {
        self.onPoseFrame = onPoseFrame
    }

    func startThrowing() throws {
        try camera.configure()
        camera.onSampleBuffer = { [weak self] buffer in self?.handle(buffer) }
        camera.start()
    }

    func stop() { camera.stop() }

    private func handle(_ buffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([request])
        guard let observation = request.results?.first else { return }
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
        let frame = VisionPoseMapper.makeFrame(from: observation, timestamp: timestamp)
        let deliver = onPoseFrame
        Task { @MainActor in deliver(frame) }
    }
}
