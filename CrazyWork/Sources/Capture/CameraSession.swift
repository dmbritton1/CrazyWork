import AVFoundation

/// Owns the AVCaptureSession and emits sample buffers to a delegate.
final class CameraSession: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.frames")
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?

    func configure() throws {
        session.beginConfiguration()
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            throw NSError(domain: "CameraSession", code: 1)
        }
        session.addInput(input)
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
    }

    func start() {
        nonisolated(unsafe) let session = self.session
        queue.async { if !session.isRunning { session.startRunning() } }
    }

    func stop() {
        nonisolated(unsafe) let session = self.session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        onSampleBuffer?(sampleBuffer)
    }
}
