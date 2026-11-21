import Foundation
import CoreGraphics
import UIKit

/// Chế độ thực thi chạm 1 ngón
enum TouchExecutionMode: String, CaseIterable, Identifiable {
    case systemWideLoopback = "Toàn hệ thống (System-Wide 127.0.0.1)"
    case internalWebView = "Trình duyệt ẩn danh tích hợp (WebView)"

    var id: String { rawValue }
}

/// Engine điều khiển AutoClick 1 chạm với thuật toán mô phỏng ngón tay thật (Humanized 1-Finger Touch):
/// - Tạo biến thiên tọa độ Gaussian (không bao giờ chạm trùng 100% cùng 1 tọa độ pixel tuyệt đối).
/// - Tạo biến thiên thời gian nhấn giữ (42ms - 86ms) như độ đàn hồi của đầu ngón tay thật.
/// - Tạo biến thiên chu kỳ giữa các lần chạm để tránh bị phát hiện bởi bộ lọc nhịp cố định (Fixed-Interval Detector).
final class HumanizedTouchEngine: ObservableObject {

    // MARK: - Cấu hình 1 chạm
    @Published var targetX: CGFloat = 200
    @Published var targetY: CGFloat = 420
    @Published var baseIntervalMs: Double = 150       // Thời gian nghỉ giữa 2 lần chạm (ms)
    @Published var enableHumanJitter: Bool = true     // Bật mô phỏng ngón tay thật
    @Published var jitterRadiusPt: CGFloat = 3.5      // Bán kính lệch ngẫu nhiên (pt)
    @Published var maxTapCount: Int = 0               // 0 = Chạy vô hạn cho tới khi bấm Dừng 1 chạm
    @Published var executionMode: TouchExecutionMode = .systemWideLoopback
    @Published var loopbackPort: UInt16 = 8100

    // MARK: - Trạng thái thời gian thực
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var totalTaps: Int = 0
    @Published private(set) var lastTapPoint: CGPoint = .zero
    @Published private(set) var lastHoldMs: Int = 0
    @Published private(set) var runnerConnected: Bool = false
    @Published private(set) var statusMessage: String = "Sẵn sàng (1 chạm để Bắt đầu)"

    /// Callback khi ở chế độ WebView nội bộ
    var onInternalWebTap: ((CGPoint, Int) -> Void)?

    private let loopbackSession: URLSession = StealthGuard.makeLoopbackOnlySession()
    private var workerTask: Task<Void, Never>?
    private var wdaSessionId: String?

    init() {
        let bounds = UIScreen.main.bounds
        self.targetX = round(bounds.width * 0.5)
        self.targetY = round(bounds.height * 0.55)
    }

    // MARK: - 1-Touch Toggle (Bật/Tắt chỉ với 1 chạm)
    func toggleOneTap() {
        if isRunning {
            stop()
        } else {
            start()
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        statusMessage = "Đang chạy AutoClick 1 ngón..."

        workerTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            await self.runTapLoop()
        }
    }

    func stop() {
        workerTask?.cancel()
        workerTask = nil
        DispatchQueue.main.async {
            self.isRunning = false
            self.statusMessage = "Đã dừng (Tổng: \(self.totalTaps) chạm)"
        }
    }

    func resetCounter() {
        totalTaps = 0
    }

    // MARK: - Vòng lặp chạm thông minh
    private func runTapLoop() async {
        while !Task.isCancelled {
            let (tapPoint, holdMs, nextDelayNs) = computeNextHumanizedTap()

            let success: Bool
            switch executionMode {
            case .systemWideLoopback:
                success = await performSystemWideDirectTap(at: tapPoint, holdMs: holdMs)
            case .internalWebView:
                await MainActor.run {
                    self.onInternalWebTap?(tapPoint, holdMs)
                }
                success = true
            }

            await MainActor.run {
                if success {
                    self.totalTaps += 1
                    self.lastTapPoint = tapPoint
                    self.lastHoldMs = holdMs
                    self.runnerConnected = true
                    if self.maxTapCount > 0 && self.totalTaps >= self.maxTapCount {
                        self.stop()
                    }
                } else {
                    self.runnerConnected = false
                    self.statusMessage = "Chưa kết nối TouchRunner nội bộ (127.0.0.1:\(self.loopbackPort))"
                }
            }

            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: nextDelayNs)
        }
    }

    /// Sinh tọa độ, thời gian giữ ngón tay, và khoảng nghỉ tiếp theo theo phân phối tự nhiên của con người
    private func computeNextHumanizedTap() -> (point: CGPoint, holdMs: Int, delayNs: UInt64) {
        let screen = UIScreen.main.bounds
        var x = targetX
        var y = targetY
        var hold = 55
        var interval = max(25.0, baseIntervalMs)

        if enableHumanJitter {
            // Phân phối Gaussian Box-Muller quanh tâm (targetX, targetY)
            let u1 = Double.random(in: 0.0001...0.9999)
            let u2 = Double.random(in: 0.0001...0.9999)
            let z0 = sqrt(-2.0 * log(u1)) * cos(2.0 * .pi * u2)
            let z1 = sqrt(-2.0 * log(u1)) * sin(2.0 * .pi * u2)

            let sigma = Double(jitterRadiusPt) * 0.45
            x += CGFloat(z0 * sigma)
            y += CGFloat(z1 * sigma)

            // Giới hạn trong khung màn hình an toàn
            x = min(max(4.0, x), screen.width - 4.0)
            y = min(max(4.0, y), screen.height - 4.0)

            // Thời gian đầu ngón tay tiếp xúc màn hình: 42ms - 86ms
            hold = Int.random(in: 42...86)

            // Độ lệch nhịp giữa các lần chạm: ±14%
            let jitterFactor = Double.random(in: 0.86...1.14)
            interval = max(20.0, baseIntervalMs * jitterFactor)
        }

        let roundedPoint = CGPoint(
            x: (x * 100).rounded() / 100,
            y: (y * 100).rounded() / 100
        )
        let delayNs = UInt64(interval * 1_000_000)
        return (roundedPoint, hold, delayNs)
    }

    // MARK: - Giao tiếp 127.0.0.1 Loopback với On-Device TouchRunner (XCTest / WDA)
    /// Gửi lệnh chạm 1 ngón chuẩn Digitizer (pointerType = "touch" -> UITouch.TouchType.direct)
    /// hoàn toàn qua cổng loopback 127.0.0.1 nội bộ trên iPhone, không qua mạng ngoài hay thiết bị Bluetooth.
    private func performSystemWideDirectTap(at point: CGPoint, holdMs: Int) async -> Bool {
        // 1. Ưu tiên endpoint rút gọn /tap của TouchRunnerUITests nội bộ (nhanh nhất, < 2ms latency)
        if let fastURL = URL(string: "http://127.0.0.1:\(loopbackPort)/tap"),
           StealthGuard.isStrictLoopback(fastURL) {
            var req = URLRequest(url: fastURL)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = [
                "x": point.x,
                "y": point.y,
                "holdMs": holdMs
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

            if let (_, resp) = try? await loopbackSession.data(for: req),
               let httpResp = resp as? HTTPURLResponse,
               (200...299).contains(httpResp.statusCode) {
                return true
            }
        }

        // 2. Fallback tương thích chuẩn W3C WebDriverAgent (/session/:id/actions) với pointerType = "touch"
        let sessionId = await resolveOrCreateWDASession()
        guard let sid = sessionId,
              let w3cURL = URL(string: "http://127.0.0.1:\(loopbackPort)/session/\(sid)/actions"),
              StealthGuard.isStrictLoopback(w3cURL) else {
            return false
        }

        let w3cTouchPayload: [String: Any] = [
            "actions": [
                [
                    "type": "pointer",
                    "id": "finger1",
                    // Quan trọng: pointerType = "touch" tạo UITouch.TouchType.direct (cảm ứng ngón tay thật),
                    // KHÔNG phải "mouse" (.indirectPointer) nên các app không thể phát hiện chuột giả lập.
                    "parameters": ["pointerType": "touch"],
                    "actions": [
                        ["type": "pointerMove", "duration": 0, "x": point.x, "y": point.y],
                        ["type": "pointerDown", "button": 0],
                        ["type": "pause", "duration": holdMs],
                        ["type": "pointerUp", "button": 0]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: w3cURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: w3cTouchPayload)

        do {
            let (_, response) = try await loopbackSession.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return true
            }
        } catch {
            wdaSessionId = nil
        }
        return false
    }

    private func resolveOrCreateWDASession() async -> String? {
        if let existing = wdaSessionId {
            return existing
        }
        guard let statusURL = URL(string: "http://127.0.0.1:\(loopbackPort)/status"),
              StealthGuard.isStrictLoopback(statusURL) else {
            return nil
        }

        do {
            let (data, _) = try await loopbackSession.data(from: statusURL)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sid = json["sessionId"] as? String, !sid.isEmpty {
                wdaSessionId = sid
                return sid
            }
        } catch {
            return nil
        }

        // Tạo session mới nếu chưa có
        guard let createURL = URL(string: "http://127.0.0.1:\(loopbackPort)/session"),
              StealthGuard.isStrictLoopback(createURL) else {
            return nil
        }
        var req = URLRequest(url: createURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["capabilities": [:]])

        if let (data, _) = try? await loopbackSession.data(for: req),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let sid = json["sessionId"] as? String {
                wdaSessionId = sid
                return sid
            }
            if let value = json["value"] as? [String: Any],
               let sid = value["sessionId"] as? String {
                wdaSessionId = sid
                return sid
            }
        }
        return nil
    }
}
