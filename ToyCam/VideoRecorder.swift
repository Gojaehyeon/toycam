import AVFoundation
import CoreVideo

/// 셰이더로 처리된 프레임을 받아 mp4(H.264)로 기록한다.
final class VideoRecorder {
    let size: CGSize
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStarted = false
    private(set) var outputURL: URL?
    private(set) var isRecording = false

    init(size: CGSize) { self.size = size }

    /// 렌더 타깃으로 쓸 픽셀버퍼 풀.
    var pixelBufferPool: CVPixelBufferPool? { adaptor?.pixelBufferPool }

    func start() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("toycam_\(UUID().uuidString).mp4")
        outputURL = url

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: attrs)

        if writer.canAdd(input) { writer.add(input) }
        guard writer.startWriting() else { return }

        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.sessionStarted = false
        self.isRecording = true
    }

    func append(_ buffer: CVPixelBuffer, at time: CMTime) {
        guard isRecording, let writer, let input, let adaptor else { return }
        if writer.status == .failed { return }
        if !sessionStarted {
            writer.startSession(atSourceTime: time)
            sessionStarted = true
        }
        if input.isReadyForMoreMediaData {
            adaptor.append(buffer, withPresentationTime: time)
        }
    }

    func finish(completion: @escaping (URL?) -> Void) {
        guard isRecording, let writer, let input else { completion(nil); return }
        isRecording = false
        input.markAsFinished()
        let url = outputURL
        writer.finishWriting {
            let ok = writer.status == .completed
            DispatchQueue.main.async { completion(ok ? url : nil) }
        }
        self.writer = nil
        self.input = nil
        self.adaptor = nil
    }
}
