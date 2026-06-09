import SwiftUI

/// Memory layout MUST match the `Uniforms` struct in Shaders.metal (all Float, sequential).
struct Uniforms {
    var pixelSize: Float = 5       // 출력 픽셀 블록 크기 (클수록 더 도트)
    var colorLevels: Float = 2     // 채널당 색 단계 수 (2 = 1비트 느낌)
    var ditherStrength: Float = 1.0
    var saturation: Float = 1.4
    var contrast: Float = 1.2
    var vignette: Float = 0.2
    var grayscale: Float = 0       // 0=컬러, 1=흑백
    var greenScreen: Float = 1     // 0=일반, 1=게임보이 그린 LCD
    var zoom: Float = 1            // 1 ... 4 디지털 줌
    var resX: Float = 1
    var resY: Float = 1
    var texAspect: Float = 1       // 카메라 텍스처 가로/세로
    var viewAspect: Float = 1      // 화면 가로/세로
}

/// SwiftUI 컨트롤이 바인딩하는 조절 가능한 파라미터.
final class PixelParams: ObservableObject {
    @Published var pixelSize: Double = 5       // 2 ... 40
    @Published var colorLevels: Double = 2     // 2 ... 32
    @Published var ditherStrength: Double = 1.0 // 0 ... 1
    @Published var saturation: Double = 1.4    // 0 ... 2.5
    @Published var contrast: Double = 1.2      // 0.5 ... 2
    @Published var vignette: Double = 0.2      // 0 ... 1
    @Published var grayscale: Bool = false
    @Published var greenScreen: Bool = true
    @Published var zoom: Double = 1            // 1 ... 4
    @Published var indicatorAngle: Double = 0  // 휠 인디케이터 회전 (셰이더와 무관)
    @Published var useFrontCamera: Bool = false

    func fillUniforms(_ u: inout Uniforms) {
        u.pixelSize = Float(pixelSize)
        u.colorLevels = Float(colorLevels)
        u.ditherStrength = Float(ditherStrength)
        u.saturation = Float(saturation)
        u.contrast = Float(contrast)
        u.vignette = Float(vignette)
        u.grayscale = grayscale ? 1 : 0
        u.greenScreen = greenScreen ? 1 : 0
        u.zoom = Float(zoom)
    }
}
