import Foundation
import AVFoundation
import Vision
import ChallengeCore

/// One detected pose plus the size of the (upright) image it came from, so the
/// overlay can map normalized joints onto the screen correctly.
struct PoseSample: Sendable {
    let frame: PoseFrame
    let imageSize: CGSize
}

/// Owns the camera, the preview layer, and Vision inference.
///
/// Orientation (the thing that made detection "egregious" before): the camera
/// delivers a landscape sensor buffer for a portrait-held phone. We rotate BOTH
/// the data-output connection and the preview connection to upright (and mirror
/// the front camera on both) so they share one coordinate space. Vision then
/// analyzes an upright image (good detection) and we pass `.up`. The overlay
/// maps joints with `ViewportMapper`.
///
/// Concurrency: the capture delegate (serial on `sessionQueue`) only hands
/// buffers to a `bufferingNewest(1)` stream; a single consumer task runs Vision
/// one frame at a time, dropping anything that piles up — the ~10–15 fps
/// throttle, with no shared mutable state across executors.
final class PosePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Clockwise rotation to upright for a portrait-locked app. If the camera
    /// ever appears upside-down, change to 270.
    private static let portraitRotationAngle: CGFloat = 90

    let session = AVCaptureSession()
    let previewLayer = AVCaptureVideoPreviewLayer()

    let frames: AsyncStream<PoseSample>
    private let framesContinuation: AsyncStream<PoseSample>.Continuation

    private let buffers: AsyncStream<TimedBuffer>
    private let buffersContinuation: AsyncStream<TimedBuffer>.Continuation

    private let request = DetectHumanBodyPoseRequest()
    private let sessionQueue = DispatchQueue(label: "com.dmbritton.crazywork.camera")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var processingTask: Task<Void, Never>?
    private var cameraPosition: AVCaptureDevice.Position = .front
    private let startTime = Date()

    private struct TimedBuffer: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer
        let timestamp: TimeInterval
        let imageSize: CGSize
    }

    override init() {
        var framesCont: AsyncStream<PoseSample>.Continuation!
        frames = AsyncStream { framesCont = $0 }
        framesContinuation = framesCont

        var buffersCont: AsyncStream<TimedBuffer>.Continuation!
        buffers = AsyncStream(TimedBuffer.self, bufferingPolicy: .bufferingNewest(1)) { buffersCont = $0 }
        buffersContinuation = buffersCont

        super.init()
    }

    /// Attach the preview layer (main actor — it's a UI object). Call before
    /// `configure`/`start`.
    @MainActor
    func attachPreview(position: AVCaptureDevice.Position) {
        cameraPosition = position
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        applyOrientation(to: previewLayer.connection, position: position)
    }

    func configure(position: AVCaptureDevice.Position = .front) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            session.sessionPreset = .high

            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }

            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            applyOrientation(to: videoOutput.connection(with: .video), position: position)
            session.commitConfiguration()
        }
    }

    func start() {
        startProcessing()
        sessionQueue.async { [weak self] in
            guard let self, !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, session.isRunning else { return }
            session.stopRunning()
        }
        processingTask?.cancel()
        buffersContinuation.finish()
        framesContinuation.finish()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Buffer is already rotated to upright by the connection, so these dims
        // are the upright (portrait) dimensions the overlay needs.
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                          height: CVPixelBufferGetHeight(pixelBuffer))
        buffersContinuation.yield(TimedBuffer(pixelBuffer: pixelBuffer,
                                              timestamp: Date().timeIntervalSince(startTime),
                                              imageSize: size))
    }

    // MARK: - Inference loop

    private func startProcessing() {
        processingTask = Task { [request, buffers, framesContinuation] in
            for await item in buffers {
                if Task.isCancelled { break }
                // .up because the connection already delivered an upright buffer.
                guard let observation = try? await request.perform(on: item.pixelBuffer, orientation: .up).first
                else { continue }
                let frame = PoseMapping.poseFrame(from: observation, timestamp: item.timestamp)
                framesContinuation.yield(PoseSample(frame: frame, imageSize: item.imageSize))
            }
        }
    }

    // MARK: - Orientation

    private func applyOrientation(to connection: AVCaptureConnection?, position: AVCaptureDevice.Position) {
        guard let connection else { return }
        if connection.isVideoRotationAngleSupported(Self.portraitRotationAngle) {
            connection.videoRotationAngle = Self.portraitRotationAngle
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (position == .front)
        }
    }
}
