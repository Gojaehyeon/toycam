import SwiftUI
import UIKit
import Photos
import PhotosUI
import AVFoundation

/// 효과음 — 휠 틱 + 셔터.
/// AVAudioPlayer + .playback 세션: 무음모드에서도 재생되고, 볼륨 버튼(미디어 볼륨)으로 조절됨.
final class SoundFX {
    static let shared = SoundFX()
    private var tickPlayers: [AVAudioPlayer] = []   // 빠른 연속 틱 대응 풀
    private var tickIndex = 0
    private var buttonPlayers: [AVAudioPlayer] = [] // 버튼 클릭음 풀
    private var buttonIndex = 0
    private var shutterPlayer: AVAudioPlayer?

    private init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)

        if let url = Bundle.main.url(forResource: "wheel_tick", withExtension: "wav") {
            tickPlayers = (0..<4).compactMap { _ in
                guard let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
                p.volume = 0.3
                p.prepareToPlay()
                return p
            }
        }
        if let url = Bundle.main.url(forResource: "shutter", withExtension: "wav") {
            shutterPlayer = try? AVAudioPlayer(contentsOf: url)
            shutterPlayer?.volume = 0.55
            shutterPlayer?.prepareToPlay()
        }
        if let url = Bundle.main.url(forResource: "button", withExtension: "wav") {
            buttonPlayers = (0..<4).compactMap { _ in
                guard let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
                p.volume = 0.35
                p.prepareToPlay()
                return p
            }
        }
    }

    func tick() {
        guard !tickPlayers.isEmpty else { return }
        let p = tickPlayers[tickIndex]
        tickIndex = (tickIndex + 1) % tickPlayers.count
        p.currentTime = 0
        p.play()
    }

    func shutter() {
        shutterPlayer?.currentTime = 0
        shutterPlayer?.play()
    }

    func button() {
        guard !buttonPlayers.isEmpty else { return }
        let p = buttonPlayers[buttonIndex]
        buttonIndex = (buttonIndex + 1) % buttonPlayers.count
        p.currentTime = 0
        p.play()
    }
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

/// 버튼 진동 + 클릭음 (sound: false 면 진동만 — 셔터음 등 자체 사운드가 있는 경우)
private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium, sound: Bool = true) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
    if sound { SoundFX.shared.button() }
}

private func timeString(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

// MARK: - 팔레트 / 프리셋 (파일 전역 — 추출된 서브뷰들과 공유)

private let cream    = Color(red: 0.87, green: 0.86, blue: 0.82)
private let creamHi  = Color(red: 0.95, green: 0.94, blue: 0.91)
private let creamLo  = Color(red: 0.72, green: 0.71, blue: 0.67)
private let bezel    = Color(red: 0.17, green: 0.17, blue: 0.18)
private let glassBg  = Color(red: 0.05, green: 0.10, blue: 0.05)
private let green    = Color(red: 0.56, green: 0.74, blue: 0.10)
private let greenDim = Color(red: 0.30, green: 0.45, blue: 0.10)
private let dpadGray = Color(red: 0.42, green: 0.43, blue: 0.46)
private let ledRed   = Color(red: 0.86, green: 0.16, blue: 0.13)

// (이름, 코드, 픽셀, 색상단계, 디더, 채도, 대비, 비네팅, 컬러모드, PRO 여부)
private let presets: [(name: String, code: String, p: Double, c: Double, d: Double, s: Double, ct: Double, v: Double, m: Int, pro: Bool)] = [
    // 무료 4종 — 시그니처 룩
    ("도트",       "DOT",     4,  2, 1.0, 1.4, 1.20, 0.20, 0,  false),
    ("레트로",     "RETRO",  10,  4, 0.8, 1.4, 1.10, 0.30, 0,  false),
    ("게임보이",   "GB",      8,  2, 1.0, 1.0, 1.15, 0.25, 1,  false),
    ("느와르",     "NOIR",    5,  3, 0.7, 1.0, 1.35, 0.55, 7,  false),
    // PRO 20종
    ("필름",       "FILM",    4,  8, 0.4, 1.2, 1.05, 0.40, 0,  true),
    ("세피아",     "SEPIA",   4,  6, 0.5, 1.0, 1.05, 0.45, 2,  true),
    ("앰버",       "AMBER",   6,  3, 0.8, 1.0, 1.20, 0.35, 3,  true),
    ("버추얼보이", "VBOY",    9,  2, 0.9, 1.0, 1.25, 0.30, 4,  true),
    ("아이스",     "ICE",     5,  4, 0.6, 1.0, 1.10, 0.35, 5,  true),
    ("네온",       "NEON",    6,  3, 0.6, 2.2, 1.25, 0.25, 0,  true),
    ("파스텔",     "PASTEL",  5, 16, 0.2, 0.8, 0.90, 0.10, 0,  true),
    ("네가",       "NEGA",    6,  4, 0.7, 1.3, 1.10, 0.30, 6,  true),
    ("원비트",     "1BIT",    6,  2, 1.0, 1.0, 1.30, 0.15, 7,  true),
    ("로파이",     "LOFI",   14,  3, 0.9, 1.5, 1.15, 0.35, 0,  true),
    ("디지캠",     "CCD",     3, 24, 0.15, 1.15, 1.05, 0.20, 14, true),
    ("골드필름",   "GOLD",    4, 12, 0.3, 1.25, 1.08, 0.35, 13, true),
    ("후지",       "FUJI",    4, 12, 0.3, 1.1, 1.05, 0.30, 14, true),
    ("크로스",     "XPRO",    5,  8, 0.5, 1.5, 1.20, 0.40, 15, true),
    ("시아노",     "CYANO",   5,  5, 0.6, 1.0, 1.10, 0.40, 8,  true),
    ("베이퍼",     "VAPOR",   6,  6, 0.6, 1.4, 1.10, 0.25, 9,  true),
    ("서멀",       "THERMAL", 8,  8, 0.4, 1.0, 1.10, 0.20, 10, true),
    ("나이트",     "NIGHT",   7,  4, 0.8, 1.0, 1.20, 0.45, 11, true),
    ("씨지에이",   "CGA",     8,  2, 1.0, 1.6, 1.20, 0.20, 12, true),
    ("패미컴",     "NES",     7,  2, 0.9, 1.5, 1.15, 0.25, 16, true),
]

// MARK: - 실기기 갱신 대응 서브뷰들
// ContentView 본문의 @State 기반 재렌더가 실기기에서 누락되는 문제가 있어,
// 표시 상태는 전부 hub/params(@Published)에 두고 아래 뷰들이 직접 observe한다.

/// 줌 배율 버튼.
private struct ZoomButtonView: View {
    @ObservedObject var params: PixelParams
    let z: Double
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

/// 실제 배터리 잔량 표시 (STATUS 바).
private struct BatteryStatusView: View {
    @State private var level: Int = BatteryStatusView.read()

    static func read() -> Int {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let l = UIDevice.current.batteryLevel
        return l < 0 ? 100 : Int((l * 100).rounded())   // 시뮬레이터(-1)는 100으로
    }

    private var symbol: String {
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
            Text("\(level)%").font(pixelFont(8))
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIDevice.batteryLevelDidChangeNotification)) { _ in
            level = Self.read()
        }
    }
}

/// 휠 위치 표시 회색 원 — 드래그 중에도 회전.
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

/// LCD 화면 전체 (베젤 + HUD + 카메라/앨범 전환).
private struct LCDView: View {
    @ObservedObject var params: PixelParams
    @ObservedObject var hub: CameraHub
    @ObservedObject var store: ProStore
    let camera: CameraManager

    var body: some View {
        VStack(spacing: 10) {
            topHud
            ZStack {
                // 카메라는 항상 살아있고, 앨범 모드일 땐 위에 덮음 (복귀 즉시)
                MetalCameraView(params: params, hub: hub, camera: camera)
                if hub.albumMode {
                    ZStack {
                        glassBg
                        albumView
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture { if !hub.albumMode { withAnimation { hub.showSettings.toggle() } } }
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
        .animation(.easeInOut(duration: 0.2), value: hub.albumMode)
    }

    private var currentCode: String { presets[params.presetIndex].code }

    private var topHud: some View {
        Group { if hub.albumMode { albumTopHud } else { cameraTopHud } }
    }

    private var bottomHud: some View {
        Group { if hub.albumMode { albumBottomHud } else { cameraBottomHud } }
    }

    // 앨범 상단: ALBUM 라벨 + 인덱스
    private var albumTopHud: some View {
        HStack(spacing: 8) {
            Text("ALBUM").font(pixelFont(10)).foregroundStyle(green)
                .padding(.horizontal, 4).padding(.vertical, 3)
                .overlay(Rectangle().stroke(green, lineWidth: 2))
            Spacer()
            if !hub.shots.isEmpty {
                Text("\(min(hub.albumSelection, hub.shots.count - 1) + 1)/\(hub.shots.count)")
                    .font(pixelFont(9)).foregroundStyle(green)
            }
        }
    }

    // 앨범 하단: 조작 힌트
    private var albumBottomHud: some View {
        HStack(alignment: .center) {
            HStack(spacing: 4) {
                hudArrows
                Text("SELECT").font(pixelFont(8)).foregroundStyle(green)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(green)
                    Text("OK VIEW").font(pixelFont(8)).foregroundStyle(green)
                }
                HStack(spacing: 4) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(green)
                    Text("DELETE").font(pixelFont(8)).foregroundStyle(green)
                }
                HStack(spacing: 4) {
                    Image(systemName: "photo.fill").font(.system(size: 8)).foregroundStyle(green)
                    Text("ALBUM EXIT").font(pixelFont(8)).foregroundStyle(green)
                }
            }
        }
    }

    // 카메라 상단: ZOOM 바 + (녹화중 REC) + 필름 잔량 + 필터 배지
    private var cameraTopHud: some View {
        HStack(spacing: 8) {
            Text("ZOOM").font(pixelFont(10)).foregroundStyle(green)
                .lineLimit(1).fixedSize()
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

            if hub.isRecording {
                Text("REC \(timeString(hub.recordSeconds))").font(pixelFont(8)).foregroundStyle(ledRed)
            }
            if !store.isPro {
                // 남은 무료 필름 장수
                let left = max(0, CameraHub.freeShotLimit - hub.shotsUsed)
                Text("FILM \(left)").font(pixelFont(7))
                    .lineLimit(1).fixedSize()
                    .foregroundStyle(left == 0 ? ledRed : green)
            }
            HStack(spacing: 4) {
                if presets[params.presetIndex].pro && !store.isPro {
                    Image(systemName: "lock.fill").font(.system(size: 9, weight: .bold))
                }
                Text(currentCode).font(pixelFont(8)).lineLimit(1).fixedSize()
            }
            .foregroundStyle(glassBg)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 8).fill(green))
        }
    }

    // 카메라 하단: 조작 힌트 (십자=미세조정 / 휠=필터)
    private var cameraBottomHud: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "arrowtriangle.up.fill")
                    Image(systemName: "arrowtriangle.down.fill")
                    Text("PIXEL").font(pixelFont(8))
                }
                HStack(spacing: 4) {
                    Image(systemName: "arrowtriangle.left.fill")
                    Image(systemName: "arrowtriangle.right.fill")
                    Text("COLOR").font(pixelFont(8))
                }
            }
            .font(.system(size: 7))
            .foregroundStyle(green)
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 8))
                    Text("FILTER").font(pixelFont(8))
                }
                HStack(spacing: 4) {
                    Image(systemName: "photo.fill").font(.system(size: 8))
                    Text("ALBUM").font(pixelFont(8))
                }
            }
            .foregroundStyle(green)
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

    // 앨범 뷰 (LCD 안: 큰 사진 + 3x3 그리드)
    private var albumView: some View {
        Group {
            if hub.shots.isEmpty {
                Text("NO PHOTOS").font(pixelFont(10)).foregroundStyle(green)
            } else {
                let sel = min(max(hub.albumSelection, 0), hub.shots.count - 1)
                let page = sel / 9
                HStack(spacing: 10) {
                    ZStack {
                        Image(uiImage: hub.shots[sel].thumbnail)
                            .resizable().scaledToFit()
                        if hub.shots[sel].isVideo {
                            Image(systemName: "play.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(Rectangle().stroke(green, lineWidth: 2))

                    VStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { row in
                            HStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { col in
                                    albumCell(page * 9 + row * 3 + col, selected: sel)
                                }
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func albumCell(_ idx: Int, selected: Int) -> some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.06))
            if idx < hub.shots.count {
                Image(uiImage: hub.shots[idx].thumbnail).resizable().scaledToFill()
            }
        }
        .frame(width: 30, height: 30)
        .clipped()
        .overlay(Rectangle().stroke(idx == selected ? green : green.opacity(0.25),
                                    lineWidth: idx == selected ? 2.5 : 1))
    }
}

/// 셔터 플래시 오버레이.
private struct FlashOverlay: View {
    @ObservedObject var hub: CameraHub
    var body: some View {
        Group {
            if hub.flash {
                Color.white.ignoresSafeArea().transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: hub.flash)
    }
}

/// 전체화면 뷰어 호스트.
private struct ViewerOverlay: View {
    @ObservedObject var hub: CameraHub
    var body: some View {
        Group {
            if hub.viewerOpen {
                ShotViewer(shots: hub.shots, index: $hub.viewerIndex) {
                    withAnimation { hub.viewerOpen = false }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: hub.viewerOpen)
    }
}

/// 설정 시트 호스트 (화면 탭으로 열림 — 정밀 조절).
private struct SettingsOverlay: View {
    @ObservedObject var params: PixelParams
    @ObservedObject var hub: CameraHub
    @ObservedObject var store: ProStore
    let onPreset: (Int) -> Void

    var body: some View {
        Group {
            if hub.showSettings { sheet }
        }
        .animation(.spring(duration: 0.25), value: hub.showSettings)
    }

    private var sheet: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
                .onTapGesture { withAnimation { hub.showSettings = false } }

            VStack {
                Spacer()
                VStack(spacing: 10) {
                    HStack {
                        Text("SETTINGS").font(pixelFont(10)).foregroundStyle(bezel)
                        Spacer()
                        Button { haptic(.light); withAnimation { hub.showSettings = false } } label: {
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
                    // 비PRO에겐 PRO 필터가 아예 안 보임
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(Array(presets.enumerated()).filter { store.isPro || !$0.element.pro },
                                id: \.offset) { i, preset in
                            Button { onPreset(i) } label: {
                                Text(preset.code).font(pixelFont(7))
                                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                                    .background(params.presetIndex == i ? green.opacity(0.5) : green.opacity(0.2))
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

    private func sliderRow(_ label: LocalizedStringKey, _ value: Binding<Double>,
                           _ range: ClosedRange<Double>, _ decimals: String) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.caption.monospaced()).frame(width: 44, alignment: .leading)
            Slider(value: value, in: range).tint(greenDim)
            Text(String(format: "%.\(decimals)f", value.wrappedValue))
                .font(.caption.monospaced()).frame(width: 38, alignment: .trailing)
        }
        .foregroundStyle(bezel)
    }
}

/// 라이브러리 사진 선택 호스트 — 선택 즉시 현재 필터로 변환 (PRO).
private struct ImportHost: View {
    @ObservedObject var hub: CameraHub
    let onPicked: (UIImage) -> Void
    @State private var item: PhotosPickerItem?

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .photosPicker(isPresented: $hub.showImport, selection: $item, matching: .images)
            .onChange(of: item) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        onPicked(image)
                    }
                    item = nil
                }
            }
    }
}

/// PRO 카트리지 페이월 호스트.
private struct PaywallHost: View {
    @ObservedObject var hub: CameraHub
    @ObservedObject var store: ProStore
    var body: some View {
        Group {
            if hub.showPaywall {
                CartridgePaywall(hub: hub, store: store)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: hub.showPaywall)
    }
}

/// "PRO 카트리지를 꽂는" 페이월 — 구독 없음, 한 번 구매.
private struct CartridgePaywall: View {
    @ObservedObject var hub: CameraHub
    @ObservedObject var store: ProStore

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { withAnimation { hub.showPaywall = false } }

            VStack {
                Spacer()
                VStack(spacing: 16) {
                    cartridge
                    Text("PRO CARTRIDGE").font(pixelFont(13)).foregroundStyle(bezel)

                    VStack(alignment: .leading, spacing: 7) {
                        featureRow("숨겨진 필터 20종 해제 (총 24종)")
                        featureRow("촬영 무제한 (무료는 필름 24장)")
                        featureRow("사진 불러오기 무제한")
                        featureRow("앞으로 추가되는 필터도 전부")
                    }

                    Button {
                        haptic(.heavy)
                        Task {
                            if await store.purchase() {
                                withAnimation { hub.showPaywall = false }
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if store.purchasing {
                                ProgressView().tint(glassBg)
                            }
                            Text("\(store.displayPrice) · 평생 소장")
                                .font(pixelFont(11))
                        }
                        .foregroundStyle(glassBg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 12).fill(green))
                    }
                    .buttonStyle(PressDownStyle())
                    .disabled(store.purchasing)

                    Text("구독 없음 · 한 번 구매하면 평생 내 것")
                        .font(pixelFont(7)).foregroundStyle(creamLo)

                    Button {
                        Task { await store.restore() ; if store.isPro { withAnimation { hub.showPaywall = false } } }
                    } label: {
                        Text("구매 복원").font(.caption).foregroundStyle(creamLo).underline()
                    }

                    // 심사 요건: 이용약관(표준 EULA) + 개인정보처리방침
                    HStack(spacing: 10) {
                        Link("이용약관",
                             destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        Text("·")
                        Link("개인정보처리방침",
                             destination: URL(string: "https://toycam.gojaehyun.com/privacy.html")!)
                    }
                    .font(.caption2)
                    .foregroundStyle(creamLo.opacity(0.8))
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 24).fill(creamHi))
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
    }

    // 게임보이 카트리지 그래픽
    private var cartridge: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 4)
                .fill(bezel)
                .frame(width: 64, height: 10)
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.18)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 130, height: 116)
                VStack(spacing: 6) {
                    // 그루브 라인
                    VStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule().fill(Color.black.opacity(0.35)).frame(width: 96, height: 3)
                        }
                    }
                    // 라벨
                    ZStack {
                        RoundedRectangle(cornerRadius: 6).fill(green)
                        VStack(spacing: 3) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("TOYCAM").font(pixelFont(9))
                            Text("PRO").font(pixelFont(7))
                        }
                        .foregroundStyle(glassBg)
                    }
                    .frame(width: 96, height: 64)
                }
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 6, y: 4)
    }

    private func featureRow(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.square.fill").foregroundStyle(green)
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(bezel)
        }
    }
}

/// 앨범 버튼 (타원 + 최근 썸네일 + 아래 레이블) — 누르면 앨범 모드 토글.
private struct AlbumButton: View {
    @ObservedObject var hub: CameraHub
    var body: some View {
        Button {
            haptic(.medium)
            withAnimation(.easeInOut(duration: 0.2)) {
                hub.albumMode.toggle()
                if hub.albumMode { hub.albumSelection = max(0, hub.shots.count - 1) }
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Ellipse()
                        .fill(LinearGradient(colors: [creamHi, creamLo], startPoint: .top, endPoint: .bottom))
                    if let last = hub.shots.last {
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
                Text("ALBUM").font(pixelFont(6)).foregroundStyle(hub.albumMode ? green : creamLo)
            }
        }
        .buttonStyle(PressDownStyle())
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: hub.shots.last?.id)
    }
}

/// LCD 모드 버튼 (타원 + 아래 레이블) — 그린 → 흑백 → 컬러 사이클.
private struct LcdButton: View {
    @ObservedObject var params: PixelParams

    private var ovalStyle: AnyShapeStyle {
        switch params.lcdMode {
        case 1: return AnyShapeStyle(green)
        case 2: return AnyShapeStyle(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.35)],
                                                    startPoint: .top, endPoint: .bottom))
        default: return AnyShapeStyle(LinearGradient(colors: [creamHi, creamLo],
                                                     startPoint: .top, endPoint: .bottom))
        }
    }

    private var label: String {
        switch params.lcdMode {
        case 1: return "GREEN"
        case 2: return "MONO"
        default: return "COLOR"
        }
    }

    private var labelColor: Color {
        switch params.lcdMode {
        case 1: return green
        case 2: return Color(white: 0.35)
        default: return creamLo
        }
    }

    var body: some View {
        Button {
            haptic(.medium)
            // 그린(1) → 흑백(2) → 컬러(0) → 그린(1)
            params.lcdMode = params.lcdMode == 1 ? 2 : (params.lcdMode == 2 ? 0 : 1)
        } label: {
            VStack(spacing: 4) {
                Ellipse()
                    .fill(ovalStyle)
                    .frame(width: 74, height: 26)
                    .overlay(Ellipse().stroke(.black.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
                Text(label).font(pixelFont(6)).foregroundStyle(labelColor)
            }
        }
        .buttonStyle(PressDownStyle())
    }
}

/// FRONT/BACK 원형 버튼 — 앨범 모드에선 ✕(선택 항목 삭제)로 변신.
private struct FrontBackButton: View {
    @ObservedObject var hub: CameraHub
    let onFlip: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(hub.albumMode ? "DELETE" : "FRONT/BACK")
                .font(pixelFont(6))
                .foregroundStyle(hub.albumMode ? ledRed : creamLo)
            Button {
                if hub.albumMode {
                    onDelete()
                } else {
                    guard !hub.isRecording else { return }
                    haptic(.medium)
                    onFlip()
                }
            } label: {
                Circle()
                    .fill(LinearGradient(colors: [creamHi, creamLo], startPoint: .top, endPoint: .bottom))
                    .frame(width: 52, height: 52)
                    .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 1))
                    .overlay {
                        if hub.albumMode {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color(red: 0.3, green: 0.3, blue: 0.32))
                        }
                    }
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            }
            .buttonStyle(PressDownStyle())
        }
    }
}

/// 휠 중앙 버튼 — 카메라: 촬영/녹화, 앨범: OK.
private struct WheelCenterButton: View {
    @ObservedObject var hub: CameraHub
    let onCapture: () -> Void
    let onStartRecording: () -> Void
    let onStopRecording: () -> Void
    let onAlbumOK: () -> Void
    @State private var pressed = false

    var body: some View {
        Circle()
            .fill(hub.isRecording ? AnyShapeStyle(ledRed)
                  : AnyShapeStyle(LinearGradient(colors: [creamHi, creamLo], startPoint: .top, endPoint: .bottom)))
            .frame(width: 96, height: 96)
            .overlay(Circle().stroke(.black.opacity(0.14), lineWidth: 1))
            .overlay(
                Image(systemName: hub.albumMode ? "checkmark" : (hub.isRecording ? "stop.fill" : "camera.fill"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(hub.isRecording ? .white : Color(red: 0.3, green: 0.3, blue: 0.32))
            )
            .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            .scaleEffect(pressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .contentShape(Circle())
            .onTapGesture {
                if hub.albumMode { onAlbumOK() }
                else if hub.isRecording { onStopRecording() } else { onCapture() }
            }
            .onLongPressGesture(minimumDuration: 0.4, pressing: { p in pressed = p }, perform: {
                if !hub.albumMode && !hub.isRecording { onStartRecording() }
            })
    }
}

// MARK: - 메인 뷰

struct ContentView: View {
    @StateObject private var params = PixelParams()
    @StateObject private var hub = CameraHub()
    @StateObject private var camera = CameraManager()
    @StateObject private var store = ProStore()
    @State private var wheelAngle: Double? = nil
    @State private var wheelAccum: Double = 0
    @State private var wheelHapticAccum: Double = 0

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            cream.ignoresSafeArea()

            VStack(spacing: 14) {
                LCDView(params: params, hub: hub, store: store, camera: camera)
                zoomSection
                controlDeck
            }
            .padding(.top, 20)
            .padding(.bottom, 8)

            FlashOverlay(hub: hub)
            ImportHost(hub: hub) { importAndConvert($0) }
            SettingsOverlay(params: params, hub: hub, store: store) { applyPreset($0) }
            PaywallHost(hub: hub, store: store).zIndex(9)
            ViewerOverlay(hub: hub).zIndex(10)
        }
        .overlay(alignment: .top) { islandStatusBar }
        .onReceive(ticker) { _ in if hub.isRecording { hub.recordSeconds += 1 } }
        .onAppear {
            restoreLastFilter()
            loadStoredShots()
            // 스크린샷/테스트용 숨김 런치 인자
            if CommandLine.arguments.contains("-startAlbum") {
                hub.albumMode = true
            }
            if CommandLine.arguments.contains("-showPaywall") {
                hub.showPaywall = true
            }
        }
    }

    /// 마지막으로 골랐던 필터를 복원해 셰이더 파라미터까지 적용.
    private func restoreLastFilter() {
        let saved = min(max(params.presetIndex, 0), presets.count - 1)
        setPresetParams(saved)
        // 권한 로드가 끝난 뒤, 비PRO인데 PRO 필터에 있으면 무료 필터로 이동
        Task { @MainActor in
            while store.loading { try? await Task.sleep(nanoseconds: 100_000_000) }
            if !store.isPro && presets[params.presetIndex].pro {
                setPresetParams(0)
            }
        }
    }

    /// 앱에서 찍어 보관 중인 결과물을 앨범으로 로드 (최초 1회).
    private func loadStoredShots() {
        guard !hub.didLoadShots else { return }
        hub.didLoadShots = true
        DispatchQueue.global(qos: .userInitiated).async {
            let stored = ShotStore.loadAll()
            guard !stored.isEmpty else { return }
            DispatchQueue.main.async {
                // 로드 전에 찍은 것이 있어도 순서 유지 (저장분이 앞)
                hub.shots.insert(contentsOf: stored, at: 0)
                hub.albumSelection = hub.shots.count - 1
            }
        }
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
                        BatteryStatusView()
                    }
                }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(green)
                .padding(.horizontal, 24)
            )
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
    }

    // MARK: 컨트롤 덱

    private var controlDeck: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
                dpad
                    .offset(x: 10, y: 10)
                Spacer(minLength: 8)
                VStack(spacing: 10) {
                    AlbumButton(hub: hub)
                        .rotationEffect(.degrees(-30))
                    LcdButton(params: params)
                        .rotationEffect(.degrees(-30))
                    importButton
                        .rotationEffect(.degrees(-30))
                }
                .offset(x: 10, y: -10)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                FrontBackButton(hub: hub,
                                onFlip: { params.useFrontCamera.toggle() },
                                onDelete: { deleteSelectedShot() })
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
                        ZoomButtonView(params: params, z: z) {
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
                arrowHit("chevron.up") { if hub.albumMode { albumNav(-3) } else { adjustPixel(+1) } }
                Spacer().frame(height: 38)
                arrowHit("chevron.down") { if hub.albumMode { albumNav(+3) } else { adjustPixel(-1) } }
            }.frame(height: 116)
            HStack(spacing: 0) {
                arrowHit("chevron.left") { if hub.albumMode { albumNav(-1) } else { adjustColor(-1) } }
                Spacer().frame(width: 38)
                arrowHit("chevron.right") { if hub.albumMode { albumNav(+1) } else { adjustColor(+1) } }
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


    // iPod 스타일 클릭휠 — 가운데=촬영/영상(앨범에선 OK), 링을 돌리면=필터/사진 선택
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
            WheelCenterButton(hub: hub,
                              onCapture: { capture() },
                              onStartRecording: { startRecording() },
                              onStopRecording: { stopRecording() },
                              onAlbumOK: { openSelectedShot() })
        }
        .frame(width: 228, height: 228)
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
                    // 돌릴 때 세밀한 진동 (15°마다 클릭감 — 진동만)
                    while wheelHapticAccum >= 15 { wheelHapticAccum -= 15; UISelectionFeedbackGenerator().selectionChanged() }
                    while wheelHapticAccum <= -15 { wheelHapticAccum += 15; UISelectionFeedbackGenerator().selectionChanged() }
                    // 45°마다: 앨범모드=사진 선택 / 평소=필터 전환 — 이때 또각 사운드
                    while wheelAccum >= 45 { wheelAccum -= 45; SoundFX.shared.tick(); if hub.albumMode { albumNav(1) } else { wheelStepPreset(1) } }
                    while wheelAccum <= -45 { wheelAccum += 45; SoundFX.shared.tick(); if hub.albumMode { albumNav(-1) } else { wheelStepPreset(-1) } }
                }
                wheelAngle = angle
            }
            .onEnded { _ in wheelAngle = nil; wheelAccum = 0; wheelHapticAccum = 0 }
    }

    // MARK: 동작

    private func addShot(_ shot: Shot) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            hub.shots.append(shot)
            hub.viewerIndex = hub.shots.count - 1
        }
    }

    private func adjustPixel(_ delta: Double) {
        params.pixelSize = min(40, max(2, params.pixelSize + delta))
    }

    private func adjustColor(_ delta: Double) {
        params.colorLevels = min(32, max(2, params.colorLevels + delta))
    }

    /// 무료 필름(총 촬영 횟수) 소진 여부.
    private func shotLimitReached() -> Bool {
        !store.isPro && hub.shotsUsed >= CameraHub.freeShotLimit
    }

    // 가져오기 버튼 (타원 + 아래 레이블) — 라이브러리 사진을 현재 필터로 변환 (최초 1회 무료, 이후 PRO)
    private static let importUsedKey = "importUsedOnce"

    private var importButton: some View {
        Button {
            haptic(.medium)
            let usedFree = UserDefaults.standard.bool(forKey: Self.importUsedKey)
            if store.isPro || !usedFree {
                hub.showImport = true
            } else {
                withAnimation { hub.showPaywall = true }
            }
        } label: {
            VStack(spacing: 4) {
                Ellipse()
                    .fill(LinearGradient(colors: [creamHi, creamLo], startPoint: .top, endPoint: .bottom))
                    .frame(width: 74, height: 26)
                    .overlay(Ellipse().stroke(.black.opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
                Text("IMPORT").font(pixelFont(6)).foregroundStyle(creamLo)
            }
        }
        .buttonStyle(PressDownStyle())
    }

    /// 가져온 사진을 현재 필터로 변환 → 앨범·사진앱 저장 → 바로 보여주기
    private func importAndConvert(_ image: UIImage) {
        guard let processed = hub.processImageAction?(image) else { return }
        // 무료 1회는 변환이 실제로 성공했을 때만 소진
        if !store.isPro { UserDefaults.standard.set(true, forKey: Self.importUsedKey) }
        haptic(.heavy, sound: false)
        SoundFX.shared.shutter()
        if let shot = ShotStore.savePhoto(processed) { addShot(shot) }
        save(processed)
        hub.viewerIndex = max(0, hub.shots.count - 1)
        withAnimation { hub.viewerOpen = true }
    }

    // 앨범: 선택 이동 (D패드/휠)
    private func albumNav(_ delta: Int) {
        guard !hub.shots.isEmpty else { return }
        hub.albumSelection = min(max(hub.albumSelection + delta, 0), hub.shots.count - 1)
    }

    // 앨범: OK = 선택 항목 전체화면으로
    private func openSelectedShot() {
        guard !hub.shots.isEmpty else { return }
        haptic(.medium)
        hub.viewerIndex = min(max(hub.albumSelection, 0), hub.shots.count - 1)
        withAnimation { hub.viewerOpen = true }
    }

    // 앨범: ✕ = 선택 항목을 앨범과 보관 파일에서 제거 (사진앱 사본은 유지)
    private func deleteSelectedShot() {
        guard !hub.shots.isEmpty else { return }
        haptic(.medium)
        let idx = min(max(hub.albumSelection, 0), hub.shots.count - 1)
        let removed = hub.shots[idx]
        withAnimation(.easeInOut(duration: 0.15)) {
            hub.shots.remove(at: idx)
            hub.albumSelection = min(idx, max(0, hub.shots.count - 1))
        }
        ShotStore.delete(removed)
    }

    private func setPresetParams(_ i: Int) {
        params.presetIndex = i
        let p = presets[i]
        withAnimation {
            params.pixelSize = p.p; params.colorLevels = p.c; params.ditherStrength = p.d
            params.saturation = p.s; params.contrast = p.ct; params.vignette = p.v
            params.colorMode = p.m
        }
    }

    /// 현재 사용 가능한 필터 인덱스 — 비PRO에겐 PRO 필터가 아예 안 보임.
    private var availablePresetIndices: [Int] {
        store.isPro ? Array(presets.indices)
                    : presets.indices.filter { !presets[$0].pro }
    }

    // 클릭휠 회전용 — 진동은 셀렉션 햅틱이 따로 처리하므로 임팩트 햅틱 없음
    private func wheelStepPreset(_ dir: Int) {
        let available = availablePresetIndices
        guard !available.isEmpty else { return }
        let pos = available.firstIndex(of: params.presetIndex) ?? 0
        let next = available[(pos + dir + available.count) % available.count]
        setPresetParams(next)
    }

    private func applyPreset(_ i: Int) {
        haptic(.light)
        setPresetParams(i)
    }

    private func capture() {
        // 무료 필름 소진 (또는 비정상적으로 PRO 필터에 있는 경우) → 페이월
        if shotLimitReached() || (presets[params.presetIndex].pro && !store.isPro) {
            haptic(.medium)
            withAnimation { hub.showPaywall = true }
            return
        }
        haptic(.heavy, sound: false)   // 셔터음이 따로 남
        SoundFX.shared.shutter()
        withAnimation { hub.flash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { withAnimation { hub.flash = false } }
        hub.capture()
        guard let image = hub.lastCaptured else { return }
        hub.shotsUsed += 1
        if let shot = ShotStore.savePhoto(image) { addShot(shot) }
        save(image)
    }

    private func startRecording() {
        // 무료 필름 소진 → 페이월 (동영상도 촬영 1회로 계산)
        guard !shotLimitReached() else {
            haptic(.medium)
            withAnimation { hub.showPaywall = true }
            return
        }
        haptic(.heavy)
        hub.recordSeconds = 0
        hub.isRecording = true
        hub.startRecording()
    }

    private func stopRecording() {
        haptic(.heavy)
        hub.isRecording = false
        hub.stopRecording { url in
            guard let url else { return }
            guard let shot = ShotStore.saveVideo(tempURL: url) else { return }
            hub.shotsUsed += 1
            addShot(shot)
            if let stored = shot.videoURL { saveVideo(stored) }
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
