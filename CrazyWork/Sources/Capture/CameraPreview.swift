import SwiftUI
import AVFoundation

/// Hosts the pipeline-owned `AVCaptureVideoPreviewLayer` (which already has its
/// orientation/mirroring configured). The skeleton overlay is drawn on top in
/// `LiveWorkoutView`, in the same coordinate space.
struct CameraPreview: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.attach(previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {}

    final class PreviewHostView: UIView {
        private weak var preview: AVCaptureVideoPreviewLayer?

        func attach(_ layer: AVCaptureVideoPreviewLayer) {
            preview = layer
            layer.frame = bounds
            self.layer.addSublayer(layer)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)   // no implicit resize animation
            preview?.frame = bounds
            CATransaction.commit()
        }
    }
}
