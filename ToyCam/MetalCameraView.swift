import SwiftUI
import MetalKit
import AVFoundation

/// 촬영 트리거 및 결과 전달용 허브.
final class CameraHub: ObservableObject {
    /// View 쪽에서 등록하는 실제 촬영 동작.
    var captureAction: (() -> UIImage?)?
    /// 촬영 완료 시 UI로 결과 전달.
    @Published var lastCaptured: UIImage?

    // UI 표시 상태 — ContentView 본문 재렌더에 의존하지 않도록 전부 @Published로 보관.
    // (실기기에서 @State 기반 갱신이 누락되는 문제 대응: observe하는 자식 뷰가 직접 갱신)
    @Published var shots: [Shot] = []
    @Published var albumMode = false
    @Published var albumSelection = 0
    @Published var viewerOpen = false
    @Published var viewerIndex = 0
    @Published var isRecording = false
    @Published var recordSeconds = 0
    @Published var flash = false
    @Published var showSettings = false
    @Published var showPaywall = false
    @Published var showImport = false

    /// 라이브러리 사진을 현재 필터로 변환 (View 쪽에서 등록).
    var processImageAction: ((UIImage) -> UIImage?)?

    /// 저장된 결과물 로드를 한 번만 수행.
    var didLoadShots = false

    /// 무료 필름 1롤 = 총 24장 (사진+영상 합산).
    static let freeShotLimit = 24

    /// 누적 촬영 횟수 (영구 저장).
    @Published var shotsUsed: Int = UserDefaults.standard.integer(forKey: "shotsUsed") {
        didSet { UserDefaults.standard.set(shotsUsed, forKey: "shotsUsed") }
    }

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
        hub.processImageAction = { [weak coord] image in coord?.renderer?.process(image: image) }
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
