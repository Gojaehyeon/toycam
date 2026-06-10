import UIKit
import AVFoundation

/// 앱에서 찍은 결과물을 Documents/shots 에 영구 보관하고, 실행 시 다시 불러온다.
/// (사진앱 저장과 별개로 자체 사본을 유지 — 앨범이 세션을 넘어 유지되게)
enum ShotStore {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// 앨범 그리드/버튼용 다운스케일 썸네일.
    static func makeThumb(_ image: UIImage, maxSide: CGFloat = 600) -> UIImage {
        let s = max(image.size.width, image.size.height)
        guard s > maxSide, s > 0 else { return image }
        let k = maxSide / s
        let size = CGSize(width: image.size.width * k, height: image.size.height * k)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func savePhoto(_ image: UIImage) -> Shot? {
        let id = UUID().uuidString
        let fullURL = dir.appendingPathComponent("\(id).jpg")
        let thumbURL = dir.appendingPathComponent("\(id)_thumb.jpg")
        let thumb = makeThumb(image)
        guard let full = image.jpegData(compressionQuality: 0.92),
              let small = thumb.jpegData(compressionQuality: 0.85) else { return nil }
        do {
            try full.write(to: fullURL)
            try small.write(to: thumbURL)
        } catch { return nil }
        return Shot(thumbnail: thumb, videoURL: nil, imageURL: fullURL)
    }

    /// 임시 mp4를 Documents로 옮겨 영구 보관.
    static func saveVideo(tempURL: URL) -> Shot? {
        let id = UUID().uuidString
        let dst = dir.appendingPathComponent("\(id).mp4")
        do { try FileManager.default.moveItem(at: tempURL, to: dst) } catch { return nil }
        let thumb = ShotThumbnail.fromVideo(dst) ?? UIImage()
        if let small = thumb.jpegData(compressionQuality: 0.85) {
            try? small.write(to: dir.appendingPathComponent("\(id)_thumb.jpg"))
        }
        return Shot(thumbnail: thumb, videoURL: dst, imageURL: nil)
    }

    /// 보관 파일 삭제 (원본 + 썸네일). 사진앱에 저장된 사본은 건드리지 않음.
    static func delete(_ shot: Shot) {
        let fm = FileManager.default
        for url in [shot.imageURL, shot.videoURL].compactMap({ $0 }) {
            try? fm.removeItem(at: url)
            let thumb = dir.appendingPathComponent(
                url.deletingPathExtension().lastPathComponent + "_thumb.jpg")
            try? fm.removeItem(at: thumb)
        }
    }

    /// 저장된 모든 결과물을 촬영 순서대로 로드.
    static func loadAll() -> [Shot] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return [] }

        struct Entry { var thumb: URL?; var video: URL?; var image: URL?; var date = Date.distantPast }
        var byID: [String: Entry] = [:]
        for f in files {
            let name = f.deletingPathExtension().lastPathComponent
            let baseID = name.hasSuffix("_thumb") ? String(name.dropLast(6)) : name
            var e = byID[baseID] ?? Entry()
            if name.hasSuffix("_thumb") {
                e.thumb = f
            } else {
                let date = (try? f.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                e.date = date
                if f.pathExtension == "mp4" { e.video = f } else { e.image = f }
            }
            byID[baseID] = e
        }

        return byID.values
            .sorted { $0.date < $1.date }
            .compactMap { e in
                let thumb = e.thumb.flatMap { UIImage(contentsOfFile: $0.path) }
                if let v = e.video {
                    return Shot(thumbnail: thumb ?? UIImage(), videoURL: v, imageURL: nil)
                }
                if let i = e.image {
                    guard let t = thumb ?? UIImage(contentsOfFile: i.path) else { return nil }
                    return Shot(thumbnail: t, videoURL: nil, imageURL: i)
                }
                return nil
            }
    }
}
