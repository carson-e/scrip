import SwiftUI
import WebKit

struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeCoordinator() -> Coordinator {
        Coordinator(webView: webView)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 920, height: 720))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.clipsToBounds = true
        pin(webView, to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if webView.superview != nsView {
            pin(webView, to: nsView)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        OffscreenWebHost.shared.embed(coordinator.webView)
    }

    final class Coordinator {
        let webView: WKWebView
        init(webView: WKWebView) {
            self.webView = webView
        }
    }
}

@MainActor
func pin(_ webView: WKWebView, to container: NSView) {
    webView.removeFromSuperview()
    webView.translatesAutoresizingMaskIntoConstraints = false
    webView.clipsToBounds = true
    NSLayoutConstraint.deactivate(webView.constraints)
    container.addSubview(webView)
    NSLayoutConstraint.activate([
        webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
        webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        webView.topAnchor.constraint(equalTo: container.topAnchor),
        webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
}
