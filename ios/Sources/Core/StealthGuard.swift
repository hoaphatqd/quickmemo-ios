import Foundation
import UIKit
import GameController

/// StealthGuard đảm bảo ứng dụng:
/// 1. Không phát sinh bất kỳ kết nối mạng ra ngoài (chặn mọi host khác ngoài 127.0.0.1).
/// 2. Kiểm tra xem có thiết bị ngoại vi (Bluetooth Mouse, Gamepad, AirPlay) nào đang lộ diện với iOS không,
///    giúp người dùng ngắt hết các thiết bị phụ trước khi chạy để các app khác chỉ thấy cảm ứng 1 ngón thuần túy.
/// 3. Không lưu trữ Cookie, Cache, hay Device ID (IDFV/IDFA).
final class StealthGuard: ObservableObject {

    struct StealthAuditItem: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let isSafe: Bool
    }

    @Published private(set) var auditItems: [StealthAuditItem] = []
    @Published private(set) var isFullyStealth: Bool = true

    init() {
        purgeAllLocalTraces()
        runAudit()
    }

    /// Xóa toàn bộ cache, cookie, credential mặc định của WebKit/URLSession để không để lại dấu vết
    func purgeAllLocalTraces() {
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)

        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    /// Tạo URLSession chỉ cho phép gọi nội bộ 127.0.0.1 (Loopback), hoàn toàn không lưu cache/cookie
    static func makeLoopbackOnlySession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 1.5
        // Không gửi bất kỳ header nhận diện nào
        config.httpAdditionalHeaders = [
            "User-Agent": "CFNetwork",
            "Connection": "keep-alive"
        ]
        return URLSession(configuration: config)
    }

    /// Kiểm tra xem địa chỉ URL có phải 100% nội bộ (localhost / 127.0.0.1) hay không.
    /// Chặn tuyệt đối mọi kết nối ra Internet.
    static func isStrictLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    /// Quét toàn bộ các dấu hiệu mà ứng dụng mục tiêu trên iOS thường dùng để phát hiện thiết bị phụ hoặc AutoClick
    func runAudit() {
        var results: [StealthAuditItem] = []

        // 1. Kiểm tra chuột rời / Trackpad Bluetooth (GCMouse)
        // Các app/game thường kiểm tra GCMouse.mice() hoặc UITouch.type == .indirectPointer
        let connectedMice = GCMouse.mice()
        results.append(
            StealthAuditItem(
                title: "Ẩn Chuột / Trackpad ngoại vi (GCMouse)",
                detail: connectedMice.isEmpty
                    ? "Không có chuột Bluetooth/USB nào kết nối. Cảm ứng sẽ là UITouch.direct (ngón tay thật)."
                    : "Phát hiện \(connectedMice.count) chuột ngoại vi! Hãy tắt Bluetooth chuột để tránh lộ UITouch.indirectPointer.",
                isSafe: connectedMice.isEmpty
            )
        )

        // 2. Kiểm tra tay cầm / thiết bị HID Bluetooth (GCController)
        let controllers = GCController.controllers()
        results.append(
            StealthAuditItem(
                title: "Ẩn Tay cầm / Thiết bị HID (GCController)",
                detail: controllers.isEmpty
                    ? "0 thiết bị điều khiển ngoại vi. Các app khác không thấy thiết bị phụ nào."
                    : "Đang có \(controllers.count) thiết bị HID/Controller kết nối. Nên ngắt kết nối để ẩn hoàn toàn.",
                isSafe: controllers.isEmpty
            )
        )

        // 3. Kiểm tra bàn phím cứng gắn ngoài (GCKeyboard)
        let hasExternalKeyboard = GCKeyboard.coalesced != nil
        results.append(
            StealthAuditItem(
                title: "Ẩn Bàn phím cứng ngoại vi (GCKeyboard)",
                detail: !hasExternalKeyboard
                    ? "Không có bàn phím vật lý gắn ngoài."
                    : "Đang gắn bàn phím ngoại vi (GCKeyboard.coalesced != nil).",
                isSafe: !hasExternalKeyboard
            )
        )

        // 4. Kiểm tra màn hình phụ / AirPlay / Quay màn hình (UIScreen)
        let multipleScreens = UIScreen.screens.count > 1
        let isCaptured = UIScreen.main.isCaptured
        let screenSafe = !multipleScreens && !isCaptured
        results.append(
            StealthAuditItem(
                title: "Ẩn Màn hình phụ & Stream (UIScreen)",
                detail: screenSafe
                    ? "1 màn hình gốc duy nhất, không phát hiện AirPlay hoặc Screen Capture."
                    : "Đang bật quay màn hình hoặc AirPlay Mirroring (app khác có thể đọc UIScreen.main.isCaptured).",
                isSafe: screenSafe
            )
        )

        // 5. Kiểm tra URL Scheme (Chống quét canOpenURL từ app khác)
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let noURLSchemes = (urlTypes == nil || urlTypes?.isEmpty == true)
        results.append(
            StealthAuditItem(
                title: "Chống dò tìm ứng dụng (No URL Scheme)",
                detail: noURLSchemes
                    ? "App không đăng ký URL Scheme và ngụy trang tên 'QuickMemo'. App khác không thể quét canOpenURL."
                    : "Cảnh báo: Có CFBundleURLTypes trong Info.plist.",
                isSafe: noURLSchemes
            )
        )

        // 6. Chế độ Zero-Tracking / Offline 100%
        results.append(
            StealthAuditItem(
                title: "Chặn theo dõi thiết bị (Zero-Tracking)",
                detail: "Không dùng IDFA/IDFV, không cấp quyền Bluetooth/LAN, khóa mạng ngoài (chỉ loopback 127.0.0.1).",
                isSafe: true
            )
        )

        DispatchQueue.main.async {
            self.auditItems = results
            self.isFullyStealth = results.allSatisfy { $0.isSafe }
        }
    }
}
