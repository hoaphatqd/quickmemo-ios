import SwiftUI
import AVKit

/// Host layer kích hoạt AVSampleBufferDisplayLayer cho cửa sổ nổi PiP
struct PiPLayerHostView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.backgroundColor = .clear
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        layer.frame = uiView.bounds
    }
}

struct MainView: View {
    @StateObject private var touchEngine: HumanizedTouchEngine
    @StateObject private var stealthGuard = StealthGuard()
    @StateObject private var pipManager: PiPOverlayManager

    @State private var showCrosshairOverlay: Bool = true
    @State private var webURL: String = "https://example.com"

    init() {
        let engine = HumanizedTouchEngine()
        _touchEngine = StateObject(wrappedValue: engine)
        _pipManager = StateObject(wrappedValue: PiPOverlayManager(touchEngine: engine))
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground)
                .ignoresSafeArea()

            // Layer ẩn 1x1 phục vụ cửa sổ nổi PiP 1-Chạm
            PiPLayerHostView(layer: pipManager.displayLayer)
                .frame(width: 1, height: 1)
                .opacity(0.01)

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    oneTapControlCard
                    coordinateConfigCard
                    humanizedJitterCard
                    if touchEngine.executionMode == .internalWebView {
                        embeddedWebCard
                    }
                    stealthAuditCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Tâm ngắm 1 chạm kéo-thả trực tiếp trên màn hình
            if showCrosshairOverlay {
                draggableCrosshair
            }
        }
    }

    // MARK: - Header
    private var headerCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(stealthGuard.isFullyStealth ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                    .frame(width: 46, height: 46)
                Image(systemName: stealthGuard.isFullyStealth ? "hand.point.up.left.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(stealthGuard.isFullyStealth ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("QuickMemo • 1-Tap Stealth")
                        .font(.headline)
                    Text("OFFLINE")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                }
                Text(touchEngine.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                stealthGuard.runAudit()
            }) {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Nút Bật/Tắt 1 Chạm & Cửa sổ nổi PiP
    private var oneTapControlCard: some View {
        VStack(spacing: 14) {
            Picker("Chế độ", selection: $touchEngine.executionMode) {
                ForEach(TouchExecutionMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // Nút 1-Chạm Lớn
            Button(action: {
                touchEngine.toggleOneTap()
                pipManager.renderCurrentStatusFrame()
            }) {
                HStack(spacing: 12) {
                    Image(systemName: touchEngine.isRunning ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(touchEngine.isRunning ? "DỪNG AUTOCLICK (1-CHẠM)" : "BẮT ĐẦU AUTOCLICK (1-CHẠM)")
                            .font(.headline.bold())
                        Text("Đã chạm: \(touchEngine.totalTaps) lần • Giữ: \(touchEngine.lastHoldMs)ms")
                            .font(.caption)
                            .opacity(0.9)
                    }
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(touchEngine.isRunning ? Color.red : Color.blue)
                .cornerRadius(14)
            }

            HStack(spacing: 10) {
                // Nút bật Cửa sổ nổi PiP (Đè lên mọi app khác)
                Button(action: {
                    pipManager.togglePiP()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: pipManager.isPiPActive ? "pip.exit" : "pip.enter")
                        Text(pipManager.isPiPActive ? "Tắt nút nổi PiP" : "Bật nút nổi PiP trên mọi App")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.purple.opacity(0.15))
                    .foregroundColor(.purple)
                    .cornerRadius(10)
                }

                // Nút Ẩn/Hiện tâm ngắm
                Button(action: {
                    showCrosshairOverlay.toggle()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: showCrosshairOverlay ? "scope" : "eye.slash")
                        Text(showCrosshairOverlay ? "Tâm ngắm" : "Đã ẩn tâm")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.orange.opacity(0.15))
                    .foregroundColor(.orange)
                    .cornerRadius(10)
                }
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Cấu hình tọa độ 1 điểm & tốc độ chạm
    private var coordinateConfigCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tọa độ 1 Chạm & Chu kỳ", systemImage: "target")
                    .font(.subheadline.bold())
                Spacer()
                Text("(\(Int(touchEngine.targetX)), \(Int(touchEngine.targetY))) pt")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
            }

            VStack(spacing: 8) {
                HStack {
                    Text("Tọa độ X: \(Int(touchEngine.targetX))")
                        .font(.caption)
                        .frame(width: 95, alignment: .leading)
                    Slider(value: $touchEngine.targetX, in: 10...(UIScreen.main.bounds.width - 10), step: 1)
                }
                HStack {
                    Text("Tọa độ Y: \(Int(touchEngine.targetY))")
                        .font(.caption)
                        .frame(width: 95, alignment: .leading)
                    Slider(value: $touchEngine.targetY, in: 40...(UIScreen.main.bounds.height - 40), step: 1)
                }
                HStack {
                    let cps = 1000.0 / max(25.0, touchEngine.baseIntervalMs)
                    Text(String(format: "Chu kỳ: %dms (%.1f/s)", Int(touchEngine.baseIntervalMs), cps))
                        .font(.caption)
                        .frame(width: 145, alignment: .leading)
                    Slider(value: $touchEngine.baseIntervalMs, in: 35...2000, step: 5)
                }
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Mô phỏng ngón tay thật (Chống phát hiện AutoClick)
    private var humanizedJitterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $touchEngine.enableHumanJitter) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mô phỏng ngón tay thật (Anti-Detection)")
                        .font(.subheadline.bold())
                    Text("Lệch tâm Gaussian ±\(String(format: "%.1f", touchEngine.jitterRadiusPt))pt • Giữ 42-86ms • Lệch nhịp ±14%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if touchEngine.enableHumanJitter {
                HStack {
                    Text("Độ lệch ngón tay:")
                        .font(.caption)
                    Slider(value: $touchEngine.jitterRadiusPt, in: 1.0...12.0, step: 0.5)
                    Text("\(String(format: "%.1f", touchEngine.jitterRadiusPt)) pt")
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Chế độ WebView ẩn danh
    private var embeddedWebCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trình duyệt cô lập (Không Cookie / Không Tracking)")
                .font(.subheadline.bold())
            StealthWebViewContainer(touchEngine: touchEngine, urlString: webURL)
                .frame(height: 300)
                .cornerRadius(10)
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Kiểm toán ẩn thiết bị & cô lập
    private var stealthAuditCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Trạng thái Ẩn Thiết Bị & Chống Theo Dõi", systemImage: "eye.slash.circle.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text(stealthGuard.isFullyStealth ? "AN TOÀN 100%" : "CẦN KIỂM TRA")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stealthGuard.isFullyStealth ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                    .foregroundColor(stealthGuard.isFullyStealth ? .green : .orange)
                    .cornerRadius(6)
            }

            ForEach(stealthGuard.auditItems) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.isSafe ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(item.isSafe ? .green : .orange)
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption.bold())
                        Text(item.detail)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(14)
    }

    // MARK: - Tâm ngắm kéo thả
    private var draggableCrosshair: some View {
        GeometryReader { _ in
            ZStack {
                Circle()
                    .stroke(touchEngine.isRunning ? Color.red : Color.blue, lineWidth: 2.5)
                    .frame(width: 44, height: 44)
                Circle()
                    .fill((touchEngine.isRunning ? Color.red : Color.blue).opacity(0.22))
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(touchEngine.isRunning ? Color.red : Color.blue)
                    .frame(width: 7, height: 7)
            }
            .position(x: touchEngine.targetX, y: touchEngine.targetY)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        touchEngine.targetX = max(10, min(UIScreen.main.bounds.width - 10, value.location.x))
                        touchEngine.targetY = max(40, min(UIScreen.main.bounds.height - 40, value.location.y))
                        pipManager.renderCurrentStatusFrame()
                    }
            )
        }
        .ignoresSafeArea()
    }
}
