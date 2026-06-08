import SwiftUI
import Photos

struct ContentView: View {
    @StateObject private var params = PixelParams()
    @StateObject private var hub = CameraHub()
    @State private var showControls = false
    @State private var chromeVisible = false
    @State private var flash = false
    @State private var toast: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MetalCameraView(params: params, hub: hub)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        chromeVisible.toggle()
                        if !chromeVisible { showControls = false }
                    }
                }

            // 셔터 플래시
            if flash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }

            VStack {
                if chromeVisible { topBar }
                Spacer()
                if showControls { controlPanel }
                shutterBar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)

            if let toast {
                Text(toast)
                    .font(.footnote.bold())
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 80)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: flash)
        .animation(.spring(duration: 0.25), value: showControls)
        .animation(.easeInOut(duration: 0.2), value: chromeVisible)
        .animation(.easeInOut, value: toast)
    }

    private var topBar: some View {
        HStack {
            Button { withAnimation { showControls.toggle() } } label: {
                Image(systemName: showControls ? "slider.horizontal.3" : "slider.horizontal.below.rectangle")
                    .font(.title3)
            }
            Spacer()
            Button { params.useFrontCamera.toggle() } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title3)
            }
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
    }

    private var controlPanel: some View {
        VStack(spacing: 10) {
            sliderRow("픽셀", $params.pixelSize, 2...40, "0")
            sliderRow("색상", $params.colorLevels, 2...32, "0")
            sliderRow("디더", $params.ditherStrength, 0...1, "1")
            sliderRow("채도", $params.saturation, 0...2.5, "1")
            sliderRow("대비", $params.contrast, 0.5...2, "2")
            sliderRow("비네팅", $params.vignette, 0...1, "1")
            Toggle(isOn: $params.grayscale) {
                Text("흑백").font(.caption.monospaced())
            }
            .tint(.white)
            .foregroundStyle(.white)
            HStack {
                presetButton("도트", p: 28, c: 6, d: 0.9, s: 1.5, ct: 1.2, v: 0.5)
                presetButton("레트로", p: 10, c: 12, d: 0.6, s: 1.4, ct: 1.1, v: 0.4)
                presetButton("필름", p: 4, c: 24, d: 0.3, s: 1.2, ct: 1.05, v: 0.55)
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.bottom, 12)
    }

    private func sliderRow(_ label: String, _ value: Binding<Double>,
                           _ range: ClosedRange<Double>, _ decimals: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption.monospaced()).frame(width: 44, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: "%.\(decimals)f", value.wrappedValue))
                .font(.caption.monospaced()).frame(width: 38, alignment: .trailing)
        }
        .foregroundStyle(.white)
    }

    private func presetButton(_ name: String, p: Double, c: Double, d: Double,
                              s: Double, ct: Double, v: Double) -> some View {
        Button {
            withAnimation {
                params.pixelSize = p; params.colorLevels = c; params.ditherStrength = d
                params.saturation = s; params.contrast = ct; params.vignette = v
            }
        } label: {
            Text(name).font(.caption.bold())
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(.white.opacity(0.12), in: Capsule())
        }
        .foregroundStyle(.white)
    }

    private var shutterBar: some View {
        Button(action: capture) {
            ZStack {
                Rectangle()
                    .stroke(.white, lineWidth: 4).frame(width: 76, height: 76)
                Rectangle()
                    .fill(.white).frame(width: 62, height: 62)
            }
        }
    }

    private func capture() {
        withAnimation { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation { flash = false }
        }
        hub.capture()
        guard let image = hub.lastCaptured else {
            showToast("촬영 실패")
            return
        }
        save(image)
    }

    private func save(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                showToast("사진 접근 권한 필요")
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { ok, _ in
                DispatchQueue.main.async {
                    showToast(ok ? "저장됨 📸" : "저장 실패")
                }
            }
        }
    }

    private func showToast(_ msg: String) {
        DispatchQueue.main.async {
            toast = msg
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if toast == msg { toast = nil }
            }
        }
    }
}

#Preview {
    ContentView()
}
