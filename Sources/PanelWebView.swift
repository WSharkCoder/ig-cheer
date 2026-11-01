import Cocoa
import WebKit

private final class ClickThroughWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class PanelWebSurface: NSView, WKNavigationDelegate, WKScriptMessageHandler {
    var onLike: (() -> Void)?
    var onNextQuote: (() -> Void)?
    var onOpenModels: (() -> Void)?
    var onRefreshPredictions: (() -> Void)?
    var onSaveMyPrediction: ((String, Int, Int) -> Void)?
    var onClearMyPrediction: ((String) -> Void)?
    var onKeepAlive: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onMouseEnter: (() -> Void)?
    var onMouseExit: (() -> Void)?
    var onResize: ((CGFloat) -> Void)?

    private let webView: ClickThroughWebView
    private var loaded = false
    private var pendingState: PanelState?
    private var pendingTail: CGFloat?
    private var lastStateJSON: String?
    private var previewMode = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = ClickThroughWebView(frame: .zero, configuration: configuration)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        configuration.userContentController.add(self, name: "panel")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsMagnification = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        if let url = Bundle.main.url(forResource: "panel", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExit?()
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "panel")
    }

    func setState(_ state: PanelState) {
        pendingState = state
        guard loaded else { return }
        applyPendingState()
    }

    func setTail(x: CGFloat) {
        pendingTail = x
        guard loaded else { return }
        applyTail()
    }

    /// Preview captures need the whole card, not the clipped 983pt viewport.
    func setPreviewMode() {
        previewMode = true
        guard loaded else { return }
        applyPreviewMode()
    }

    private func applyPreviewMode() {
        webView.evaluateJavaScript("document.body.classList.add('preview-mode');", completionHandler: nil)
    }

    func snapshot(completion: @escaping (NSImage?) -> Void) {
        let configuration = WKSnapshotConfiguration()
        webView.takeSnapshot(with: configuration) { image, error in
            if let error {
                NSLog("IGCheer preview snapshot error: \(error.localizedDescription)")
            }
            completion(image)
        }
    }

    private func applyPendingState() {
        guard let state = pendingState else { return }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(state),
              let json = String(data: data, encoding: .utf8) else { return }
        lastStateJSON = json
        webView.evaluateJavaScript("window.renderPanel(\(json));") { _, error in
            if let error {
                NSLog("IGCheer panel render error: \(error.localizedDescription)")
            }
        }
        applyTail()
    }

    private func applyTail() {
        guard let tail = pendingTail else { return }
        webView.evaluateJavaScript("window.setTail(\(Double(tail)));", completionHandler: nil)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        if previewMode { applyPreviewMode() }
        applyPendingState()
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        if let url = Bundle.main.url(forResource: "panel", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: Bundle.main.resourceURL ?? Bundle.main.bundleURL)
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        switch action {
        case "like":
            onLike?()
        case "nextQuote":
            onNextQuote?()
        case "openModels":
            onOpenModels?()
        case "refreshPrediction":
            onRefreshPredictions?()
        case "saveMyPrediction":
            if let matchID = body["matchID"] as? String,
               let ig = body["igScore"] as? NSNumber,
               let opponent = body["opponentScore"] as? NSNumber {
                onSaveMyPrediction?(matchID, ig.intValue, opponent.intValue)
            }
        case "clearMyPrediction":
            if let matchID = body["matchID"] as? String {
                onClearMyPrediction?(matchID)
            }
        case "keepAlive":
            onKeepAlive?()
        case "dismiss":
            onDismiss?()
        case "resize":
            if let number = body["height"] as? NSNumber {
                onResize?(CGFloat(number.doubleValue))
            }
        default:
            break
        }
    }
}
