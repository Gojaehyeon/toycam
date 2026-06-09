import SwiftUI
import AVKit
import AVFoundation

/// 세션 중 앱 안에서 찍은 결과물 한 건.
struct Shot: Identifiable {
    let id = UUID()
    let thumbnail: UIImage   // 사진은 결과 원본, 영상은 첫 프레임 썸네일
    let videoURL: URL?       // nil 이면 사진
    var isVideo: Bool { videoURL != nil }
}

enum ShotThumbnail {
    /// 영상 첫 프레임을 썸네일로 추출.
    static func fromVideo(_ url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        let time = CMTime(seconds: 0.05, preferredTimescale: 600)
        guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// 영상을 반복 재생하는 플레이어.
struct LoopingPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                let p = AVPlayer(url: url)
                p.actionAtItemEnd = .none
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: p.currentItem, queue: .main) { _ in
                    p.seek(to: .zero); p.play()
                }
                player = p
                p.play()
            }
            .onDisappear { player?.pause() }
    }
}

/// 결과물 전체화면 뷰어 — 좌우로 넘기며 사진 보기 / 영상 재생.
struct ShotViewer: View {
    let shots: [Shot]
    @Binding var index: Int
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(shots.enumerated()), id: \.element.id) { i, shot in
                    Group {
                        if let url = shot.videoURL {
                            LoopingPlayer(url: url)
                        } else {
                            Image(uiImage: shot.thumbnail)
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: shots.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}
