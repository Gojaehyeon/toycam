import SwiftUI
import MetalKit

/// 촬영 트리거 및 결과 전달용 허브.
final class CameraHub: ObservableObject {
    /// View 쪽에서 등록하는 실제 촬영 동작.
    var captureAction: (() -> UIImage?)?
    /// 촬영 완료 시 UI로 결과 전달.
    @Published var lastCaptured: UIImage?

    func capture() {
        if let image = captureAction?() {
            lastCaptured = image
        }
    }
}

/// MTKView + Renderer + CameraManager를 묶는 SwiftUI 래퍼.
struct MetalCameraView: UIViewRepresentable {
    @ObservedObject var params: PixelParams
    let hub: CameraHub

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

        let camera = CameraManager()
        camera.onFrame = { [weak renderer] buffer in
            renderer?.update(pixelBuffer: buffer)
        }
        camera.start(front: params.useFrontCamera)
        coord.camera = camera
        coord.isFront = params.useFrontCamera

        hub.captureAction = { [weak coord] in coord?.renderer?.captureImage() }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        let coord = context.coordinator
        if let renderer = coord.renderer {
            params.fillUniforms(&renderer.uniforms)
        }
        if coord.isFront != params.useFrontCamera {
            coord.isFront = params.useFrontCamera
            coord.camera?.switchCamera(front: params.useFrontCamera)
        }
    }

    static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
        coordinator.camera?.stop()
    }

    final class Coordinator {
        var renderer: Renderer?
        var camera: CameraManager?
        var isFront = false
    }
}
