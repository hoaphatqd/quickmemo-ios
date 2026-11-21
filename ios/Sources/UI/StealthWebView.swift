import SwiftUI
import WebKit

/// Trình duyệt WebView cô lập (Non-Persistent DataStore) không lưu Cookie/Tracking,
/// tích hợp tâm ngắm 1 chạm trực tiếp.
struct StealthWebViewContainer: UIViewRepresentable {
    @ObservedObject var touchEngine: HumanizedTouchEngine
    let urlString: String

    func makeCoordinator() -> Coordinator {
        Coordinator(touchEngine: touchEngine)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Sử dụng bộ nhớ tạm nonPersistent() để chống theo dõi thiết bị 100%
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true

        // Chặn WebRTC rò rỉ IP LAN và ẩn thuộc tính webdriver/automation
        let stealthScript = """
        (function() {
            Object.defineProperty(navigator, 'webdriver', { get: () => false });
            delete window.cdc_adoQpoasnfa76pfcZLmcfl_Array;
            delete window.cdc_adoQpoasnfa76pfcZLmcfl_Promise;
            delete window.cdc_adoQpoasnfa76pfcZLmcfl_Symbol;
        })();
        """
        let userScript = WKUserScript(
            source: stealthScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(userScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

        context.coordinator.bind(webView: webView)

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator {
        private weak var webView: WKWebView?
        private let touchEngine: HumanizedTouchEngine

        init(touchEngine: HumanizedTouchEngine) {
            self.touchEngine = touchEngine
        }

        func bind(webView: WKWebView) {
            self.webView = webView
            touchEngine.onInternalWebTap = { [weak self] point, holdMs in
                self?.injectHumanizedDOMTouch(at: point, holdMs: holdMs)
            }
        }

        private func injectHumanizedDOMTouch(at point: CGPoint, holdMs: Int) {
            guard let webView = webView else { return }
            let js = """
            (function(x, y, holdMs) {
                const el = document.elementFromPoint(x, y);
                if (!el) return;
                const touchObj = new Touch({
                    identifier: Date.now(),
                    target: el,
                    clientX: x,
                    clientY: y,
                    radiusX: 11.5,
                    radiusY: 11.5,
                    rotationAngle: 0,
                    force: 0.85
                });
                const touchList = [touchObj];
                el.dispatchEvent(new TouchEvent('touchstart', {
                    bubbles: true, cancelable: true, view: window,
                    touches: touchList, targetTouches: touchList, changedTouches: touchList
                }));
                el.dispatchEvent(new PointerEvent('pointerdown', {
                    bubbles: true, cancelable: true, pointerType: 'touch',
                    clientX: x, clientY: y, isPrimary: true
                }));
                setTimeout(function() {
                    el.dispatchEvent(new TouchEvent('touchend', {
                        bubbles: true, cancelable: true, view: window,
                        touches: [], targetTouches: [], changedTouches: touchList
                    }));
                    el.dispatchEvent(new PointerEvent('pointerup', {
                        bubbles: true, cancelable: true, pointerType: 'touch',
                        clientX: x, clientY: y, isPrimary: true
                    }));
                    el.click();
                }, holdMs);
            })(\(point.x), \(point.y), \(holdMs));
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
