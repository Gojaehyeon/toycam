import SwiftUI
import MetalKit
import AVFoundation

/// 촬영 트리거 및 결과 전달용 허브.
final class CameraHub: ObservableObject {
    /// View 쪽에서 등록하는 실제 촬영 동작.
    var captureAction: (() -> UIImage?)?
    /// 촬영 완료 시 UI로 결과 전달.
    @Published var lastCaptured: UIImage?

    /// 동영상 녹화 시작/종료 동작 (View 쪽에서 등록).
    var startRecordingAction: (() -> Void)?
    var stopRecordingAction: ((@escaping (URL?) -> Void) -> Void)?

    func capture() {
        if let image = captureAction?() {
            lastCaptured = image
        }
    }

    func startRecording() { startRecordingAction?() }
    func stopRecording(_ completion: @escaping (URL?) -> Void) { stopRecordingAction?(completion) }
}

/// MTKView + Renderer 를 묶는 SwiftUI 래퍼 (공유 CameraManager 사용 — 메인 그린 LCD).
struct MetalCameraView: UIViewRepresentable {
    @ObservedObject var params: PixelParams
    let hub: CameraHub
    let camera: CameraManager

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.preferredFramesPerSecond = 60
        view.isOpaque = true

        let coord = context.coordinator
        guard let renderer = Renderer(mtkView: view) else { return view }
        coord.renderer = renderer
        view.delegate = renderer

        camera.onFrame = { [weak renderer] buffer, time in
            renderer?.update(pixelBuffer: buffer, time: time)
        }
        camera.start(front: params.useFrontCamera)
        coord.isFront = params.useFrontCamera

        hub.captureAction = { [weak coord] in coord?.renderer?.captureImage() }
        hub.startRecordingAction = { [weak coord] in coord?.renderer?.startRecording() }
        hub.stopRecordingAction = { [weak coord] done in coord?.renderer?.stopRecording(completion: done) }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        let coord = context.coordinator
        if let renderer = coord.renderer {
            params.fillUniforms(&renderer.uniforms)
        }
        if coord.isFront != params.useFrontCamera {
            coord.isFront = params.useFrontCamera
            camera.switchCamera(front: params.useFrontCamera)
        }
    }

    final class Coordinator {
        var renderer: Renderer?
        var isFront = false
    }
}

/// 같은 카메라 세션의 라이브 컬러 프리뷰 (미니 뷰파인더).
struct MiniPreviewView: UIViewRepresentable {
    let camera: CameraManager

    func makeUIView(context: Context) -> PreviewContainer {
        let v = PreviewContainer()
        v.backgroundColor = .black
        v.previewLayer = camera.makePreviewLayer()
        if let layer = v.previewLayer {
            v.layer.addSublayer(layer)
            if let conn = layer.connection, conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }
        }
        return v
    }

    func updateUIView(_ uiView: PreviewContainer, context: Context) {}

    final class PreviewContainer: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer?
        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}
