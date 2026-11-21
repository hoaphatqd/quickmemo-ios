import XCTest
import Network

/// On-Device TouchRunner:
/// - Chỉ lắng nghe trên giao diện Loopback nội bộ 127.0.0.1:8100 (Ẩn hoàn toàn khỏi mạng LAN/Wi-Fi, không thiết bị nào khác quét thấy).
/// - Sử dụng XCUICoordinate.press(forDuration:) của iOS để phát tín hiệu cảm ứng 1 ngón trực tiếp (UITouch.TouchType.direct)
///   với thời gian giữ ngón tay tự nhiên (42-86ms) trên mọi ứng dụng đang mở trên màn hình.
final class TouchRunner: XCTestCase {

    private var listener: NWListener?
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    func testStartStealthLoopbackTouchServer() throws {
        continueAfterFailure = true

        let params = NWParameters.tcp
        // Khóa cứng vào giao diện Loopback 127.0.0.1 để không lộ cổng ra Wi-Fi/LAN
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: 8100)!
        )

        let nwListener = try NWListener(using: params)
        self.listener = nwListener

        nwListener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        nwListener.start(queue: .main)

        // Giữ runner hoạt động liên tục trong nền
        let keepAlive = XCTestExpectation(description: "Keep 127.0.0.1 TouchRunner Alive")
        wait(for: [keepAlive], timeout: 86400 * 7)
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self = self,
                  let data = data,
                  let rawRequest = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            if rawRequest.hasPrefix("POST /tap") {
                if let bodyRange = rawRequest.range(of: "\r\n\r\n") {
                    let jsonString = String(rawRequest[bodyRange.upperBound...])
                    if let bodyData = jsonString.data(using: .utf8),
                       let payload = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                       let x = payload["x"] as? Double,
                       let y = payload["y"] as? Double {
                        let holdMs = (payload["holdMs"] as? Int) ?? 55
                        self.performNativeSingleFingerTouch(x: CGFloat(x), y: CGFloat(y), holdMs: holdMs)
                    }
                }
                self.sendHTTP200(on: connection, body: #"{"status":"ok"}"#)
            } else if rawRequest.hasPrefix("GET /status") {
                self.sendHTTP200(on: connection, body: #"{"sessionId":"local-stealth","status":0}"#)
            } else {
                self.sendHTTP200(on: connection, body: #"{"status":"idle"}"#)
            }
        }
    }

    /// Phát sự kiện chạm 1 ngón tay trực tiếp (UITouch.TouchType.direct) tại tọa độ (x, y) toàn màn hình
    private func performNativeSingleFingerTouch(x: CGFloat, y: CGFloat, holdMs: Int) {
        let rootCoord = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let targetCoord = rootCoord.withOffset(CGVector(dx: x, dy: y))
        let durationSeconds = max(0.035, min(0.25, Double(holdMs) / 1000.0))
        targetCoord.press(forDuration: durationSeconds)
    }

    private func sendHTTP200(on connection: NWConnection, body: String) {
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
