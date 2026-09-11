import AppKit
import WebKit

@MainActor
final class OffscreenWebHost {
    static let shared = OffscreenWebHost()

    private let window: NSWindow
    private let container: NSView

    private init() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 920, height: 720))
        let window = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 920, height: 720),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .transient]
        window.contentView = container
        window.orderBack(nil)
        self.window = window
        self.container = container
    }

    func embed(_ webView: WKWebView) {
        guard webView.superview != container else { return }
        pin(webView, to: container)
    }
}
