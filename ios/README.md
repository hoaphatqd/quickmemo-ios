# OneTapStealth (Ngụy trang: QuickMemo) — AutoClick 1 Chạm Ẩn Danh cho iPhone (Không Jailbreak)

Dự án viết bằng **Swift / SwiftUI** dành cho iPhone thông thường (cài qua **Sideloadly / AltStore / SideStore / Xcode**), thiết kế chuyên biệt cho mục tiêu **1 chạm — Không theo dõi thiết bị — Ẩn hoàn toàn trước các ứng dụng khác**.

---

## 1. Kiến trúc Ẩn Danh & Chống Phát Hiện (Stealth Architecture)

Trên iOS không Jailbreak, các ứng dụng/game thường kiểm tra gian lận hoặc phát hiện công cụ tự động qua 5 kênh. Bộ mã nguồn này xử lý triệt để cả 5 kênh:

1. **Ẩn hoàn toàn thiết bị ngoại vi (`UITouch.TouchType.direct`)**:
   - Nếu bạn dùng chuột Bluetooth, thiết bị bấm vật lý HID, hay AssistiveTouch Mouse, iOS sẽ gắn nhãn sự kiện là `UITouch.TouchType.indirectPointer` và liệt kê thiết bị trong `GCMouse.mice()` / `GCController.controllers()`.
   - `OneTapStealth` **không dùng Bluetooth/HID ngoại vi**. Mọi cú chạm được phát qua kênh cảm ứng 1 ngón trực tiếp (`pointerType: "touch"` / `XCUICoordinate.press(forDuration:)`), tạo ra `UITouch.TouchType.direct` giống hệt đầu ngón tay thật chạm vào màn hình.
2. **Bộ kiểm toán `StealthGuard` tích hợp sẵn**:
   - Tự động kiểm tra và cảnh báo nếu trên iPhone đang còn kết nối chuột (`GCMouse`), tay cầm (`GCController`), bàn phím rời (`GCKeyboard`), hoặc đang bật quay màn hình/AirPlay (`UIScreen.main.isCaptured`) để bạn ngắt hết trước khi mở ứng dụng mục tiêu.
3. **Chống quét ứng dụng từ App khác (`No URL Scheme` & Ngụy trang Bundle)**:
   - Ứng dụng mang tên hiển thị **`QuickMemo`** (`com.personal.quickmemo.utility`) và **tuyệt đối không khai báo `CFBundleURLTypes`** trong `Info.plist`. Không một ứng dụng nào khác trên iPhone có thể dùng `UIApplication.shared.canOpenURL(...)` để dò ra máy có cài AutoClick.
4. **Chạy ngầm không gây gián đoạn âm thanh (`.mixWithOthers`)**:
   - Nhiều app phát hiện phần mềm chạy ngầm khi bị cướp quyền âm thanh (`AVAudioSession.interruptionNotification`). `PiPOverlayManager` cấu hình `.playback` kèm `.mixWithOthers` để chạy nền 100% êm ái, không làm ngắt tiếng hay phát tín hiệu cho app đang mở.
5. **Thuật toán Mô phỏng Ngón Tay Thật (`HumanizedTouchEngine`)**:
   - **Lệch tâm Gaussian (Box-Muller)**: Không bao giờ chạm trùng 100% vào một điểm tọa độ cố định tới từng số thập phân.
   - **Thời gian giữ đầu ngón tay (`42ms – 86ms`)**: Mô phỏng đúng độ trễ khi phần thịt đầu ngón tay chạm và nhấc khỏi màn hình cảm ứng (không phải cú click `0ms` của máy).
   - **Biến thiên nhịp (`±14%`)**: Phá vỡ quy luật khoảng cách thời gian cố định giữa các lần chạm.

---

## 2. Cấu trúc Thư mục Dự án

- [project.yml](file:///d:/ios/project.yml): Cấu hình XcodeGen tạo project Xcode tự động.
- [Sources/App/Info.plist](file:///d:/ios/Sources/App/Info.plist): Cấu hình quyền tối giản, ngụy trang tên `QuickMemo`, chặn hoàn toàn URL Scheme và kết nối mạng ngoài.
- [Sources/App/OneTapStealthApp.swift](file:///d:/ios/Sources/App/OneTapStealthApp.swift): Điểm khởi chạy ứng dụng.
- [Sources/Core/StealthGuard.swift](file:///d:/ios/Sources/Core/StealthGuard.swift): Module kiểm toán ẩn thiết bị (`GCMouse`, `GCController`, `GCKeyboard`, `UIScreen`) và khóa mạng `127.0.0.1` Loopback-Only.
- [Sources/Core/HumanizedTouchEngine.swift](file:///d:/ios/Sources/Core/HumanizedTouchEngine.swift): Engine AutoClick 1 chạm với thuật toán lệch tâm Gaussian và biến thiên thời gian nhấn giữ.
- [Sources/Core/PiPOverlayManager.swift](file:///d:/ios/Sources/Core/PiPOverlayManager.swift): Tạo nút điều khiển nổi 1-Chạm (Picture-in-Picture HUD) đè lên mọi màn hình ứng dụng khác mà không cần Jailbreak.
- [Sources/UI/MainView.swift](file:///d:/ios/Sources/UI/MainView.swift): Giao diện điều khiển 1 chạm, kéo-thả tâm ngắm trực quan và bảng kiểm tra trạng thái ẩn danh.
- [Sources/UI/StealthWebView.swift](file:///d:/ios/Sources/UI/StealthWebView.swift): Chế độ trình duyệt cô lập (`.nonPersistent()`, xóa dấu vết `navigator.webdriver`) khi cần AutoClick trực tiếp trên nền Web.
- [TouchRunnerUITests/TouchRunner.swift](file:///d:/ios/TouchRunnerUITests/TouchRunner.swift): Dịch vụ phát cảm ứng 1 ngón nội bộ khóa cứng vào `127.0.0.1:8100` (ẩn hoàn toàn khỏi mạng Wi-Fi/LAN).
- [.github/workflows/build-ipa.yml](file:///d:/ios/.github/workflows/build-ipa.yml): Workflow tự động biên dịch ra file `QuickMemo-OneTapStealth.ipa` trên GitHub để bạn tải về Windows và cài bằng **Sideloadly / AltStore**.

---

## 3. Cách đóng gói `.ipa` trên Windows và Cài vào iPhone qua Sideloadly / AltStore

Vì bạn đang dùng Windows, bạn không cần cài macOS hay Xcode:

1. Đẩy thư mục `d:\ios` lên một kho chứa (Repository) **Private** trên GitHub của bạn.
2. Vào tab **Actions** trên GitHub -> Chọn workflow **Build Unsigned IPA (Sideloadly / AltStore)** -> Bấm **Run workflow**.
3. Sau khoảng 1–2 phút, tải file **`QuickMemo-OneTapStealth.ipa`** trong mục **Artifacts**.
4. Mở **Sideloadly** (hoặc **AltStore / SideStore**) trên Windows, kéo file `QuickMemo-OneTapStealth.ipa` vào và cài lên iPhone bằng Apple ID của bạn.

### Cách sử dụng Nút nổi 1-Chạm trên mọi ứng dụng:
1. Mở app **QuickMemo** trên iPhone, kiểm tra bảng **Trạng thái Ẩn Thiết Bị** báo **`AN TOÀN 100%`**.
2. Kéo tâm ngắm tới vị trí cần chạm và chọn tốc độ chạm.
3. Bấm **"Bật nút nổi PiP trên mọi App"** -> Vuốt thoát ra màn hình chính và mở ứng dụng bạn muốn.
4. Chạm **1 lần** vào nút **Play / Pause** trên cửa sổ nổi PiP nhỏ ở góc màn hình để **Bắt đầu / Dừng** AutoClick ngay lập tức.
