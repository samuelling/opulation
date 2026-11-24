// His back camera, reading her face: the luma plane of each frame, scaled to ~640 px wide, goes to FlyCode.read.
import AVFoundation
import SwiftUI

final class FaceCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "opulation.camera")
    private var busy = false
    /** called on the main queue with what was read (payload nil while only glimpsed) */
    var onRead: ((FlyCode.Read?) -> Void)?
    var running: Bool { session.isRunning }

    static func requestAccess() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }

    func start() throws {
        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw NSError(domain: "OPUlation", code: 10, userInfo: [NSLocalizedDescriptionKey: "No camera."]) }
        session.beginConfiguration(); session.sessionPreset = .hd1280x720
        let input = try AVCaptureDeviceInput(device: dev); if session.canAddInput(input) { session.addInput(input) }
        let out = AVCaptureVideoDataOutput(); out.alwaysDiscardsLateVideoFrames = true
        out.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        out.setSampleBufferDelegate(self, queue: queue); if session.canAddOutput(out) { session.addOutput(out) }
        session.commitConfiguration()
        try? dev.lockForConfiguration(); if dev.isFocusModeSupported(.continuousAutoFocus) { dev.focusMode = .continuousAutoFocus }; dev.unlockForConfiguration()
        queue.async { self.session.startRunning() }
    }
    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func captureOutput(_ output: AVCaptureOutput, didOutput sb: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !busy, let px = CMSampleBufferGetImageBuffer(sb) else { return }
        busy = true; defer { busy = false }
        CVPixelBufferLockBaseAddress(px, .readOnly); defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(px, 0) else { return }
        let W = CVPixelBufferGetWidthOfPlane(px, 0), H = CVPixelBufferGetHeightOfPlane(px, 0), stride = CVPixelBufferGetBytesPerRowOfPlane(px, 0)
        let step = max(1, W / 640), w = W / step, h = H / step, src = base.assumingMemoryBound(to: UInt8.self)
        var img = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h { let row = src + y * step * stride; for x in 0..<w { img[y * w + x] = row[x * step] } }
        let r = FlyCode.read(img, w, h)
        DispatchQueue.main.async { self.onRead?(r) }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView { let v = PreviewView(); v.layer0.session = session; v.layer0.videoGravity = .resizeAspectFill; return v }
    func updateUIView(_ v: PreviewView, context: Context) {}
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var layer0: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
