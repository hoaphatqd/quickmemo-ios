import Foundation
import AVFoundation
import AVKit
import UIKit
import CoreMedia
import CoreVideo

/// Quản lý cửa sổ nổi 1-Chạm (Picture-in-Picture Floating HUD) trên iOS không cần Jailbreak.
/// - Khi người dùng thoát ra màn hình chính hoặc mở app/game khác, cửa sổ PiP siêu nhỏ sẽ nổi trên màn hình.
/// - Bấm nút Play/Pause trên cửa sổ nổi PiP = Bật/Tắt AutoClick chỉ với 1 chạm mà không cần chuyển app.
/// - Sử dụng AVAudioSession(.playback, options: [.mixWithOthers]) để chạy ngầm không làm tắt âm thanh của app khác.
final class PiPOverlayManager: NSObject, ObservableObject {

    @Published private(set) var isPiPActive: Bool = false
    @Published private(set) var isPiPPossible: Bool = false

    let displayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    private weak var touchEngine: HumanizedTouchEngine?
    private var renderTimer: Timer?

    init(touchEngine: HumanizedTouchEngine) {
        self.touchEngine = touchEngine
        super.init()
        configureSilentMixableAudioSession()
        setupSampleBufferPiP()
    }

    /// Cấu hình AudioSession chạy nền với tùy chọn .mixWithOthers
    /// Quan trọng: .mixWithOthers giúp các app khác KHÔNG phát hiện bị chiếm quyền âm thanh (Audio Interruption).
    private func configureSilentMixableAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Bỏ qua lỗi trên Simulator nếu không có thiết bị âm thanh
        }
    }

    private func setupSampleBufferPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            isPiPPossible = false
            return
        }

        displayLayer.videoGravity = .resizeAspect
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )

        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.delegate = self
        // Ẩn nút tua tiến/lùi 15s, chỉ giữ duy nhất nút 1-Chạm Play/Pause ở giữa
        controller.requiresLinearPlayback = true
        if #available(iOS 14.2, *) {
            controller.canStartPictureInPictureAutomaticallyFromInline = true
        }

        self.pipController = controller
        self.isPiPPossible = true

        // Đẩy frame trạng thái định kỳ vào buffer layer
        startFrameFeed()
    }

    func togglePiP() {
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            renderCurrentStatusFrame()
            pip.startPictureInPicture()
        }
    }

    private func startFrameFeed() {
        renderCurrentStatusFrame()
        renderTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.renderCurrentStatusFrame()
        }
    }

    /// Vẽ giao diện HUD thu nhỏ hiển thị trạng thái ĐANG CHẠY / TẠM DỪNG và số lượt chạm
    func renderCurrentStatusFrame() {
        let size = CGSize(width: 320, height: 180)
        let isRunning = touchEngine?.isRunning ?? false
        let taps = touchEngine?.totalTaps ?? 0
        let x = Int(touchEngine?.targetX ?? 0)
        let y = Int(touchEngine?.targetY ?? 0)

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)

            // Nền tối tối giản
            UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0).setFill()
            ctx.fill(rect)

            // Viền trạng thái
            let accentColor = isRunning
                ? UIColor(red: 0.18, green: 0.82, blue: 0.45, alpha: 1.0)
                : UIColor(red: 0.95, green: 0.62, blue: 0.15, alpha: 1.0)
            accentColor.setStroke()
            let border = UIBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), cornerRadius: 14)
            border.lineWidth = 4
            border.stroke()

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .bold),
                .foregroundColor: accentColor
            ]
            let statusText = isRunning ? "● ĐANG CLICK (1-CHẠM)" : "❚❚ ĐÃ DỪNG (CHẠM ĐỂ CHẠY)"
            statusText.draw(at: CGPoint(x: 20, y: 24), withAttributes: titleAttrs)

            let infoAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 20, weight: .medium),
                .foregroundColor: UIColor.white
            ]
            let tapText = "Số lần chạm: \(taps)"
            tapText.draw(at: CGPoint(x: 20, y: 74), withAttributes: infoAttrs)

            let coordAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 17, weight: .regular),
                .foregroundColor: UIColor(white: 0.75, alpha: 1.0)
            ]
            let coordText = "Tọa độ: (\(x), \(y)) • Ẩn danh: BẬT"
            coordText.draw(at: CGPoint(x: 20, y: 118), withAttributes: coordAttrs)
        }

        if let sampleBuffer = Self.makeSampleBuffer(from: image) {
            if displayLayer.status == .failed {
                displayLayer.flush()
            }
            displayLayer.enqueue(sampleBuffer)
        }
    }

    // MARK: - Chuyển UIImage sang CMSampleBuffer cho cửa sổ PiP
    private static func makeSampleBuffer(from image: UIImage) -> CMSampleBuffer? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height

        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDesc = formatDescription else { return nil }

        let now = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 600)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 2),
            presentationTimeStamp: now,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescription: formatDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}

// MARK: - AVPictureInPictureControllerDelegate & PlaybackDelegate (Điều khiển 1 chạm)
extension PiPOverlayManager: AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
    }

    /// Khi người dùng chạm 1 lần vào nút Play/Pause trên cửa sổ nổi PiP:
    /// Bật hoặc Tắt AutoClick ngay lập tức!
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        guard let engine = touchEngine else { return }
        if playing && !engine.isRunning {
            engine.start()
        } else if !playing && engine.isRunning {
            engine.stop()
        }
        renderCurrentStatusFrame()
        pictureInPictureController.invalidatePlaybackState()
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        return CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return !(touchEngine?.isRunning ?? false)
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
