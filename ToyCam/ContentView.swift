import SwiftUI
import UIKit
import Photos
import AudioToolbox

/// 저지연 시스템 사운드 — 휠 틱 + 셔터.
final class SoundFX {
    static let shared = SoundFX()
    private var tickID: SystemSoundID = 0
    private var shutterID: SystemSoundID = 0
    private init() {
        if let u = Bundle.main.url(forResource: "wheel_tick", withExtension: "wav") {
            AudioServicesCreateSystemSoundID(u as CFURL, &tickID)
        }
        if let u = Bundle.main.url(forResource: "shutter", withExtension: "wav") {
            AudioServicesCreateSystemSoundID(u as CFURL, &shutterID)
        }
    }
    func tick() { if tickID != 0 { AudioServicesPlaySystemSound(tickID) } }
    func shutter() { if shutterID != 0 { AudioServicesPlaySystemSound(shutterID) } }
}

/// 누르면 살짝 들어가는 물리 버튼 느낌.
private struct PressDownStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .offset(y: configuration.isPressed ? 2 : 0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private func pixelFont(_ size: CGFloat) -> Font { .custom("PressStart2P-Regular", size: size) }

/// params를 직접 observe → ContentView 재렌더와 무관하게 갱신 (실기기 대응).
private struct ZoomButtonView: View {
    @ObservedObject var params: PixelParams
    let z: Double
    let green: Color
    let glassBg: Color
    let creamHi: Color
    let creamLo: Color
    let onTap: () -> Void
    var body: some View {
        let active = params.zoom == z
        return Button(action: onTap) {
            Text("x\(Int(z))")
                .font(pixelFont(10))
                .foregroundStyle(active ? glassBg : Color(red: 0.35, green: 0.35, blue: 0.37))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(active ? AnyShapeStyle(green)
                              : AnyShapeStyle(LinearGradient(colors: [creamHi, creamLo],
                                                             startPoint: .top, endPoint: .bottom)))
                )
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(PressDownStyle())
    }
}

/// 휠 위치 표시 회색 원 — params.indicatorAngle을 observe해 드래그 중에도 회전.
private struct WheelIndicatorDot: View {
    @ObservedObject var params: PixelParams
    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.42)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: 13, height: 13)
            .overlay(Circle().stroke(.black.opacity(0.2), lineWidth: 0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 16)
            .rotationEffect(.degrees(params.indicatorAngle))
    }
}

struct ContentView: View {
    @StateObject private var params = PixelParams()
    @StateObject private var hub = CameraHub()
    @StateObject private var camera = CameraManager()
    @State private var showSettings = false
    @State private var flash = false
    @State private var presetIndex = 0
    @State private var isRecording = false
    @State private var recordSeconds = 0
    @State private var shutterPressed = false
    @State private var wheelAngle: Double? = nil
    @State private var wheelAccum: Double = 0
    @State private var wheelHapticAccum: Double = 0
    @State private var shots: [Shot] = []
    @State private var viewerOpen = false
    @State private var viewerIndex = 0

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // 크림 플라스틱 + 그린 LCD 팔레트
    private let cream    = Color(red: 0.87, green: 0.86, blue: 0.82)
    private let creamHi  = Color(red: 0.95, green: 0.94, blue: 0.91)
    private let creamLo  = Color(red: 0.72, green: 0.71, blue: 0.67)
    private let bezel    = Color(red: 0.17, green: 0.17, blue: 0.18)
    private let glassBg  = Color(red: 0.05, green: 0.10, blue: 0.05)
    private let green    = Color(red: 0.56, green: 0.74, blue: 0.10)
    private let greenDim = Color(red: 0.30, green: 0.45, blue: 0.10)
    private let dpadGray = Color(red: 0.42, green: 0.43, blue: 0.46)
    private let ledRed   = Color(red: 0.86, green: 0.16, blue: 0.13)

    private let presets: [(name: String, code: String, p: Double, c: Double, d: Double, s: Double, ct: Double, v: Double)] = [
        ("도트",   "DOT",   5,  2, 1.0, 1.4, 1.20, 0.20),
        ("레트로", "RETRO", 10, 4, 0.8, 1.4, 1.10, 0.30),
        ("필름",   "FILM",  4,  8, 0.4, 1.2, 1.05, 0.40),
    ]
    private var currentCode: String { presets[presetIndex].code }

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()

            VStack(spacing: 14) {
                screen
                zoomSection
                controlDeck
            }
            .padding(.top, 20)
            .padding(.bottom, 8)

            if flash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }
            if showSettings { settingsSheet }
            if viewerOpen {
                ShotViewer(shots: shots, index: $viewerIndex) {
                    withAnimation { viewerOpen = false }
                }
                .transition(.opacity).zIndex(10)
            }
        }
        .overlay(alignment: .top) { islandStatusBar }
        .animation(.easeInOut(duration: 0.12), value: flash)
        .animation(.spring(duration: 0.25), value: showSettings)
        .animation(.easeInOut(duration: 0.2), value: viewerOpen)
        .onReceive(ticker) { _ in if isRecording { recordSeconds += 1 } }
    }

    // MARK: STATUS 바 (다이나믹 아일랜드와 합쳐지는 최상단 검정 바)

    private var topInset: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.safeAreaInsets.top) ?? 59
    }

    private var islandStatusBar: some View {
        Rectangle()
            .fill(Color.black)
            .frame(height: max(topInset, 44))
            .overlay(
                HStack {
                    HStack(spacing: 13) {
                        Image(systemName: "speaker.wave.2.fill")
                        Image(systemName: "person.fill")
                        Image(systemName: "camera.macro")
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "photo.fill")
                        Image(systemName: "battery.75")
                        Text("85%").font(pixelFont(8))
                    }
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(green)
                .padding(.horizontal, 24)
            )
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
    }

    // MARK: 그린 LCD 화면 + HUD

    private var screen: some View {
        VStack(spacing: 10) {
            topHud
            MetalCameraView(params: params, hub: hub, camera: camera)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { showSettings.toggle() } }
            bottomHud
        }
        // 1) 검정 베젤 (좌우는 얇게, 위아래는 HUD 띠로 넉넉히)
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(bezel.shadow(.inner(color: .black.opacity(0.65), radius: 3, y: 1)))
        )
        // 2) 리세스 채널 (눌린 크림)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(creamLo.opacity(0.5).shadow(.inner(color: .black.opacity(0.35), radius: 5, y: 2)))
        )
        // 3) 솟아오른 외곽 플라스틱 패널
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 34)
                .fill(cream)
                .shadow(color: .black.opacity(0.2), radius: 9, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 34)
                .stroke(LinearGradient(colors: [creamHi, .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
        )
        .padding(.horizontal, 8)
    }

    // 상단 검정 띠: ZOOM 바 + (녹화중 REC) + APPLIED 배지
    private var topHud: some View {
        HStack(spacing: 8) {
            Text("ZOOM").font(pixelFont(10)).foregroundStyle(green)
                .padding(.horizontal, 4).padding(.vertical, 3)
                .overlay(Rectangle().stroke(green, lineWidth: 2))
            Text("x1").font(pixelFont(7)).foregroundStyle(green)
            ZStack(alignment: .leading) {
                Rectangle().stroke(green, lineWidth: 1.5)
                Rectangle().fill(green)
                    .padding(2)
                    .frame(width: 70 * CGFloat((params.zoom - 1) / 3), alignment: .leading)
            }
            .frame(width: 70, height: 12)
            Text("x4").font(pixelFont(7)).foregroundStyle(green)

            Spacer()

            if isRecording {
                Text("REC \(timeString(recordSeconds))").font(pixelFont(8)).foregroundStyle(ledRed)
            }
            Text("APPLIED:").font(pixelFont(7)).foregroundStyle(green)
            Text(currentCode).font(pixelFont(8)).foregroundStyle(glassBg)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 8).fill(green))
        }
    }

    // 하단 검정 띠: 조작 힌트
    private var bottomHud: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    hudArrows
                    Text("SELECT").font(pixelFont(8)).foregroundStyle(green)
                }
                HStack(spacing: 5) {
                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(green)
                    Text("FILTER/OK").font(pixelFont(8)).foregroundStyle(green)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill").font(.system(size: 8)).foregroundStyle(green)
                    Text("GALLERY").font(pixelFont(8)).foregroundStyle(green)
                }
                HStack(spacing: 4) {
                    Image(systemName: "trash.fill").font(.system(size: 8)).foregroundStyle(green)
                    Text("CANCEL").font(pixelFont(8)).foregroundStyle(green)
                }
            }
        }
    }

    private var hudArrows: some View {
        HStack(spacing: 1) {
            Image(systemName: "arrowtriangle.left.fill")
            Image(systemName: "arrowtriangle.up.fill")
            Image(systemName: "arrowtriangle.down.fill")
            Image(systemName: "arrowtriangle.right.fill")
        }
        .font(.system(size: 7))
        .foregroundStyle(green)
    }

    // MARK: 컨트롤 덱

    private var controlDeck: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                dpad
                    .offset(x: 10, y: 10)
                Spacer(minLength: 8)
                VStack(spacing: 12) {
                    galleryButton
                        .rotationEffect(.degrees(-30))
                    lcdButton
                        .rotationEffect(.degrees(-30))
                }
                .offset(x: 10, y: -10)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                frontBackButton
                    .offset(x: -16, y: 14)
                Spacer(minLength: 10)
                clickWheel
                    // 레이아웃 점유는 그대로 두고 휠만 프레임 우하단 밖으로 삐져나오게
                    .padding(.trailing, -24)
                    .padding(.bottom, -38)
                    .offset(x: -3, y: -15)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(cream)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(creamHi.opacity(0.7), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        )
        .padding(.horizontal, 16)
    }

    // 배율조정 섹션 — 좌측 미니 라이브 컬러 뷰파인더 + 줌 버튼
    private var zoomSection: some View {
        HStack(spacing: 14) {
            miniViewfinder
            VStack(alignment: .leading, spacing: 8) {
                Text("ZOOM").font(pixelFont(8)).foregroundStyle(creamLo)
                HStack(spacing: 8) {
                    ForEach([1.0, 2.0, 4.0], id: \.self) { z in
                        ZoomButtonView(params: params, z: z, green: green, glassBg: glassBg,
                                       creamHi: creamHi, creamLo: creamLo) {
                            haptic(.medium)
                            params.zoom = z
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20).fill(cream)
                .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(creamHi.opacity(0.7), lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var miniViewfinder: some View {
        MiniPreviewView(camera: camera)
            .frame(width: 74, height: 56)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(bezel.shadow(.inner(color: .black.opacity(0.6), radius: 2, y: 1)))
            )
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(creamLo, lineWidth: 1))
    }


    // 그레이 D-패드
    private var dpad: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(dpadGray).frame(width: 116, height: 38)
            RoundedRectangle(cornerRadius: 8).fill(dpadGray).frame(width: 38, height: 116)
            RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.18)).frame(width: 30, height: 30)

            VStack(spacing: 0) {
                arrowHit("chevron.up") { adjustPixel(+1) }
                Spacer().frame(height: 38)
                arrowHit("chevron.down") { adjustPixel(-1) }
            }.frame(height: 116)
            HStack(spacing: 0) {
                arrowHit("chevron.left") { cyclePreset(-1) }
                Spacer().frame(width: 38)
                arrowHit("chevron.right") { cyclePreset(+1) }
            }.frame(width: 116)
        }
        .frame(width: 116, height: 116)
        .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
    }

    private func arrowHit(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button { haptic(.light); action() } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 39, height: 39)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // FRONT/BACK 원형 버튼
    private var frontBackButton: some View {
        VStack(spacing: 4) {
            Text("FRONT/BACK").font(pixelFont(6)).foregroundStyle(creamLo)
            Button {
                guard !isRecording else { return }
                haptic(.medium)
                params.useFrontCamera.toggle()
            } label: {
                Circle()
                    .fill(LinearGradient(colors: [creamHi, creamLo], startPoint: .top, endPoint: .bottom))
                    .frame(width: 52, height: 52)
                    .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            }
            .buttonStyle(PressDownStyle())
        }
    }

    // iPod 스타일 클릭휠 — 가운데=촬영/영상, 링을 돌리면=필터 전환
    private var clickWheel: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [creamHi, creamLo], startPoint: .top, endPoint: .bottom))
                .frame(width: 228, height: 228)
                .overlay(Circle().stroke(.black.opacity(0.10), lineWidth: 1))
                .shadow(color: .black.opacity(0.16), radius: 13, y: 6)
                .contentShape(Circle())
                .simultaneousGesture(wheelDrag)
            WheelIndicatorDot(params: params)   // 제스처 뷰 밖의 형제 → 드래그 중에도 갱신
            wheelCenter
        }
        .frame(width: 228, height: 228)
    }

    private var wheelCenter: some View {
        Circle()
            .fill(isRecording ? AnyShapeStyle(ledRed)
                  : AnyShapeStyle(LinearGradient(colors: [creamHi, creamLo], startPoint: .top, endPoint: .bottom)))
            .frame(width: 96, height: 96)
            .overlay(Circle().stroke(.black.opacity(0.14), lineWidth: 1))
            .overlay(
                Image(systemName: isRecording ? "stop.fill" : "camera.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(isRecording ? .white : Color(red: 0.3, green: 0.3, blue: 0.32))
            )
            .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            .scaleEffect(shutterPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.08), value: shutterPressed)
            .contentShape(Circle())
            .onTapGesture {
                if isRecording { stopRecording() } else { capture() }
            }
            .onLongPressGesture(minimumDuration: 0.4, pressing: { p in shutterPressed = p }, perform: {
                if !isRecording { startRecording() }
            })
    }

    private var wheelDrag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let cx = 114.0, cy = 114.0
                let dx = Double(value.location.x) - cx
                let dy = Double(value.location.y) - cy
                let dist = (dx * dx + dy * dy).squareRoot()
                guard dist > 56 else { return }   // 가운데 버튼 영역 제외
                let angle = atan2(dy, dx) * 180 / .pi
                if let last = wheelAngle {
                    var delta = angle - last
                    if delta > 180 { delta -= 360 }
                    if delta < -180 { delta += 360 }
                    wheelAccum += delta
                    wheelHapticAccum += delta
                    params.indicatorAngle += delta   // 회색 원이 손가락 따라 회전 (params observe)
                    // 돌릴 때 세밀한 진동 + 또각 사운드 (15°마다 클릭감)
                    while wheelHapticAccum >= 15 { wheelHapticAccum -= 15; UISelectionFeedbackGenerator().selectionChanged(); SoundFX.shared.tick() }
                    while wheelHapticAccum <= -15 { wheelHapticAccum += 15; UISelectionFeedbackGenerator().selectionChanged(); SoundFX.shared.tick() }
                    // 필터 전환은 45°마다
                    while wheelAccum >= 45 { wheelAccum -= 45; wheelStepPreset(1) }
                    while wheelAccum <= -45 { wheelAccum += 45; wheelStepPreset(-1) }
                }
                wheelAngle = angle
            }
            .onEnded { _ in wheelAngle = nil; wheelAccum = 0; wheelHapticAccum = 0 }
    }

    // LCD 버튼 (켜지면 초록, 아래 레이블)
    private var lcdButton: some View {
        Button {
            haptic(.medium)
            params.greenScreen.toggle()
        } label: {
            VStack(spacing: 4) {
                Ellipse()
                    .fill(params.greenScreen ? AnyShapeStyle(green)
                          : AnyShapeStyle(LinearGradient(colors: [creamHi, creamLo], startPoint: .top, endPoint: .bottom)))
                    .frame(width: 74, height: 26)
                    .overlay(Ellipse().stroke(.black.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
                Text("LCD").font(pixelFont(6)).foregroundStyle(params.greenScreen ? green : creamLo)
            }
        }
        .buttonStyle(PressDownStyle())
    }

    // 앨범 버튼 (최근 결과물 썸네일 + 아래 레이블)
    private var galleryButton: some View {
        Button {
            guard !shots.isEmpty else { return }
            haptic(.light)
            viewerIndex = shots.count - 1
            withAnimation(.easeInOut(duration: 0.2)) { viewerOpen = true }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Ellipse()
                        .fill(LinearGradient(colors: [creamHi, creamLo], startPoint: .top, endPoint: .bottom))
                    if let last = shots.last {
                        Image(uiImage: last.thumbnail)
                            .resizable().scaledToFill()
                            .frame(width: 74, height: 26)
                            .clipShape(Ellipse())
                            .id(last.id)
                            .transition(.scale(scale: 1.9).combined(with: .move(edge: .top)).combined(with: .opacity))
                    }
                }
                .frame(width: 74, height: 26)
                .overlay(Ellipse().stroke(.black.opacity(0.15), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
                Text("ALBUM").font(pixelFont(6)).foregroundStyle(creamLo)
            }
        }
        .buttonStyle(PressDownStyle())
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: shots.last?.id)
    }

    // MARK: 설정 시트 (화면 탭으로 열림 — 정밀 조절)

    private var settingsSheet: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { withAnimation { showSettings = false } }

            VStack {
                Spacer()
                VStack(spacing: 10) {
                    HStack {
                        Text("SETTINGS").font(pixelFont(10)).foregroundStyle(bezel)
                        Spacer()
                        Button { haptic(.light); withAnimation { showSettings = false } } label: {
                            Image(systemName: "xmark").font(.headline)
                        }.foregroundStyle(bezel)
                    }
                    sliderRow("픽셀", $params.pixelSize, 2...40, "0")
                    sliderRow("색상", $params.colorLevels, 2...32, "0")
                    sliderRow("디더", $params.ditherStrength, 0...1, "1")
                    sliderRow("대비", $params.contrast, 0.5...2, "2")
                    sliderRow("비네팅", $params.vignette, 0...1, "1")
                    Toggle(isOn: $params.grayscale) { Text("흑백").font(.caption.weight(.bold)) }
                        .tint(greenDim).foregroundStyle(bezel)
                    HStack(spacing: 8) {
                        ForEach(Array(presets.enumerated()), id: \.offset) { i, preset in
                            Button { applyPreset(i) } label: {
                                Text(preset.name).font(.caption.bold())
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(green.opacity(0.2))
                                    .foregroundStyle(bezel)
                            }
                        }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20).fill(creamHi))
                .padding(.horizontal, 12).padding(.bottom, 14)
            }
            .transition(.move(edge: .bottom))
        }
    }

    private func sliderRow(_ label: String, _ value: Binding<Double>,
                           _ range: ClosedRange<Double>, _ decimals: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption.monospaced()).frame(width: 44, alignment: .leading)
            Slider(value: value, in: range).tint(greenDim)
            Text(String(format: "%.\(decimals)f", value.wrappedValue))
                .font(.caption.monospaced()).frame(width: 38, alignment: .trailing)
        }
        .foregroundStyle(bezel)
    }

    // MARK: 동작

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func timeString(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    private func addShot(_ shot: Shot) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            shots.append(shot)
            viewerIndex = shots.count - 1
        }
    }

    private func adjustPixel(_ delta: Double) {
        params.pixelSize = min(40, max(2, params.pixelSize + delta))
    }

    private func cyclePreset(_ dir: Int) {
        presetIndex = (presetIndex + dir + presets.count) % presets.count
        applyPreset(presetIndex)
    }

    // 클릭휠 회전용 — 진동은 셀렉션 햅틱이 따로 처리하므로 임팩트 햅틱 없음
    private func wheelStepPreset(_ dir: Int) {
        presetIndex = (presetIndex + dir + presets.count) % presets.count
        let p = presets[presetIndex]
        withAnimation {
            params.pixelSize = p.p; params.colorLevels = p.c; params.ditherStrength = p.d
            params.saturation = p.s; params.contrast = p.ct; params.vignette = p.v
        }
    }

    private func applyPreset(_ i: Int) {
        haptic(.light)
        presetIndex = i
        let p = presets[i]
        withAnimation {
            params.pixelSize = p.p; params.colorLevels = p.c; params.ditherStrength = p.d
            params.saturation = p.s; params.contrast = p.ct; params.vignette = p.v
        }
    }

    private func capture() {
        haptic(.heavy)
        SoundFX.shared.shutter()
        withAnimation { flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation { flash = false } }
        hub.capture()
        guard let image = hub.lastCaptured else { return }
        addShot(Shot(thumbnail: image, videoURL: nil))
        save(image)
    }

    private func startRecording() {
        haptic(.heavy)
        recordSeconds = 0
        isRecording = true
        hub.startRecording()
    }

    private func stopRecording() {
        haptic(.heavy)
        isRecording = false
        hub.stopRecording { url in
            guard let url else { return }
            let thumb = ShotThumbnail.fromVideo(url) ?? UIImage()
            addShot(Shot(thumbnail: thumb, videoURL: url))
            saveVideo(url)
        }
    }

    private func save(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { _, _ in }
        }
    }

    private func saveVideo(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { _, _ in }
        }
    }
}

#Preview {
    ContentView()
}
