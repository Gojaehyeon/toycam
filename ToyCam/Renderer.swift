import MetalKit
import CoreVideo
import UIKit

/// 카메라 텍스처를 셰이더로 처리해 MTKView에 그리고, 촬영 시 UIImage로 추출한다.
final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private var textureCache: CVMetalTextureCache!

    private let lock = NSLock()
    private var currentTexture: MTLTexture?
    private var texAspect: Float = 1

    var uniforms = Uniforms()
    private var drawableSize = CGSize(width: 1, height: 1)

    init?(mtkView: MTKView) {
        guard let device = mtkView.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary(),
              let vtx = library.makeFunction(name: "vtx"),
              let frag = library.makeFunction(name: "frag") else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vtx
        desc.fragmentFunction = frag
        desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        self.pipeline = pipeline

        let sd = MTLSamplerDescriptor()
        sd.minFilter = .nearest
        sd.magFilter = .nearest
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: sd) else { return nil }
        self.sampler = sampler

        super.init()
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    /// 카메라 프레임을 Metal 텍스처로 변환해 보관 (카메라 큐에서 호출).
    func update(pixelBuffer: CVPixelBuffer) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture)
        guard status == kCVReturnSuccess,
              let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return }

        lock.lock()
        currentTexture = texture
        texAspect = Float(width) / Float(height)
        lock.unlock()
    }

    // MARK: MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = size
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor else { return }

        lock.lock()
        let texture = currentTexture
        let ta = texAspect
        lock.unlock()

        guard let texture else { return }

        var u = uniforms
        u.resX = Float(drawableSize.width)
        u.resY = Float(drawableSize.height)
        u.texAspect = ta
        u.viewAspect = Float(drawableSize.width / max(drawableSize.height, 1))

        guard let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.present(drawable)
        cb.commit()
    }

    // MARK: 촬영 — 처리된 결과를 오프스크린 렌더해서 UIImage로 추출

    func captureImage() -> UIImage? {
        lock.lock()
        let texture = currentTexture
        let ta = texAspect
        lock.unlock()
        guard let texture else { return nil }

        // 화면 비율을 유지하되 충분한 해상도로 렌더.
        let outW = max(Int(drawableSize.width.rounded()) * 2, 720)
        let outH = max(Int(drawableSize.height.rounded()) * 2, 1280)

        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: outW, height: outH, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        guard let target = device.makeTexture(descriptor: td) else { return nil }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store

        var u = uniforms
        u.resX = Float(outW)
        u.resY = Float(outH)
        u.texAspect = ta
        u.viewAspect = Float(outW) / Float(outH)

        guard let cb = commandQueue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return nil }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentTexture(texture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()

        return Renderer.makeUIImage(from: target)
    }

    private static func makeUIImage(from texture: MTLTexture) -> UIImage? {
        let w = texture.width, h = texture.height
        let rowBytes = w * 4
        var raw = [UInt8](repeating: 0, count: rowBytes * h)
        texture.getBytes(&raw, bytesPerRow: rowBytes,
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // bgra8Unorm -> CGImage: byteOrder32Little + premultipliedFirst
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx = CGContext(data: &raw, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: rowBytes,
                                  space: colorSpace, bitmapInfo: bitmapInfo.rawValue),
              let cg = ctx.makeImage() else { return nil }
        return UIImage(cgImage: cg)
    }
}
