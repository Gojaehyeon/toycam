import AVFoundation
import CoreVideo

/// AVCaptureSession을 구성하고 프레임(CVPixelBuffer)을 콜백으로 전달한다.
final class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "toycam.camera.queue")
    private var currentInput: AVCaptureDeviceInput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var hasStarted = false

    /// 새 프레임이 들어올 때 호출 (백그라운드 큐).
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    /// 같은 세션을 공유하는 라이브 컬러 프리뷰 레이어 (미니 뷰파인더용).
    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    func start(front: Bool) {
        guard !hasStarted else { return }
        hasStarted = true
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else { return }
            self?.queue.async { self?.configure(front: front) }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func switchCamera(front: Bool) {
        queue.async { [weak self] in self?.configure(front: front) }
    }

    private func configure(front: Bool) {
        session.beginConfiguration()
        session.sessionPreset = .high

        if let existing = currentInput {
            session.removeInput(existing)
            currentInput = nil
        }

        let position: AVCaptureDevice.Position = front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        currentInput = input

        if !session.outputs.contains(videoOutput) {
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
        }

        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = front
            }
            // 전·후면에 맞는 올바른 회전 각도를 기기가 직접 계산 (전면 미러링까지 반영).
            setupRotation(for: device, connection: connection)
        }

        session.commitConfiguration()

        if !session.isRunning {
            session.startRunning()
        }
    }

    /// RotationCoordinator로 카메라별 수평 보정 각도를 적용하고, 변화도 추적.
    private func setupRotation(for device: AVCaptureDevice, connection: AVCaptureConnection) {
        rotationObservation = nil
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        applyRotation(coordinator.videoRotationAngleForHorizonLevelCapture, to: connection)
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture, options: [.new]
        ) { [weak self, weak connection] _, change in
            guard let self, let connection, let angle = change.newValue else { return }
            self.queue.async { self.applyRotation(angle, to: connection) }
        }
    }

    private func applyRotation(_ angle: CGFloat, to connection: AVCaptureConnection) {
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        onFrame?(pixelBuffer, time)
    }
}
