import Combine
import Foundation
import os
import ScripCore
import WebKit

private let log = Logger(subsystem: "com.carson.Scrip", category: "scrape")

@MainActor
public final class ProviderWebSession: NSObject, ObservableObject, UsageFetching, WKNavigationDelegate, WKUIDelegate {
    public let provider: ProviderID
    public let webView: WKWebView
    @Published public var canGoBack = false
    @Published public var canGoForward = false

    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var loadGeneration = 0
    private var jobGeneration = 0
    private var timeoutTask: Task<Void, Never>?
    private var popups: [WKWebView] = []
    private var observations: [NSKeyValueObservation] = []

    public init(provider: ProviderID) {
        self.provider = provider
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        let config = WKWebViewConfiguration()
        config.websiteDataStore = Self.dataStore(for: provider)
        config.defaultWebpagePreferences = prefs
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.preferences.isElementFullscreenEnabled = true
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 920, height: 720), configuration: config)
        self.webView = view
        super.init()
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        #if DEBUG
        if #available(macOS 13.3, *) {
            view.isInspectable = true
        }
        #endif
        observations = [
            view.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoBack = view.canGoBack }
            },
            view.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoForward = view.canGoForward }
            },
        ]
    }

    private var activeWebView: WKWebView {
        popups.last ?? webView
    }

    public func goBack() {
        let view = activeWebView
        if let item = view.backForwardList.backItem {
            view.go(to: item)
        } else if view.canGoBack {
            view.goBack()
        } else {
            view.evaluateJavaScript("window.history.back()") { _, _ in }
        }
        refreshHistory()
    }

    public func goForward() {
        let view = activeWebView
        if let item = view.backForwardList.forwardItem {
            view.go(to: item)
        } else if view.canGoForward {
            view.goForward()
        } else {
            view.evaluateJavaScript("window.history.forward()") { _, _ in }
        }
        refreshHistory()
    }

    public func loadHomeIfNeeded() {
        if webView.url == nil {
            loadHome()
        }
    }

    public func loadHome() {
        activeWebView.load(URLRequest(url: provider.homeURL))
    }

    public func reloadPage() {
        activeWebView.reload()
    }

    public func fetchSnapshot(allowNavigation: Bool = true) async -> PageSnapshot {
        jobGeneration += 1
        let generation = jobGeneration
        let page = await performFetch(allowNavigation: allowNavigation, generation: generation)
        log.result(provider: provider, page: page, allowNavigation: allowNavigation)
        return page
    }

    private func performFetch(allowNavigation: Bool, generation: Int) async -> PageSnapshot {
        if !allowNavigation {
            if webView.url == nil || provider == .cursor {
                await load(provider.usageURLs.first ?? provider.homeURL, generation: generation)
            }
            return await restoreUsage(generation: generation)
        }

        if webView.url == nil || !isOnProviderSite() || provider == .cursor {
            await load(provider.usageURLs.first ?? provider.homeURL, generation: generation)
        } else {
            await remountUsagePanel()
        }

        var best = await restoreUsage(generation: generation)
        if hasUsage(best) || best.blocked {
            return best
        }

        for url in provider.usageURLs {
            guard generation == jobGeneration else { break }
            if webView.url?.absoluteString == url.absoluteString { continue }
            await load(url, generation: generation)
            best = merge(best, await restoreUsage(generation: generation))
            if hasUsage(best) || best.blocked {
                return best
            }
            if looksSignedOut(best) { break }
        }

        if await hasProviderCookies(), !best.blocked, !looksSignedOut(best), best.error == nil,
           !best.lines.isEmpty || !best.text.isEmpty {
            best.loggedIn = true
        }
        return best
    }

    public func signOut() async {
        let store = webView.configuration.websiteDataStore
        await store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        )
        loadHome()
    }

    private func hasUsage(_ page: PageSnapshot) -> Bool {
        UsageParser.hasStructuredUsage(provider: provider, page: page)
    }

    private func looksSignedOut(_ page: PageSnapshot) -> Bool {
        !page.loggedIn && !page.blocked && page.error == nil && !page.text.isEmpty
    }

    private func merge(_ current: PageSnapshot, _ next: PageSnapshot) -> PageSnapshot {
        if next.blocked || hasUsage(next) { return next }
        if current.loggedIn && !next.loggedIn { return current }
        return next
    }

    private func pollExtract(generation: Int, timeout: Duration = .seconds(12)) async -> PageSnapshot {
        let clock = ContinuousClock()
        let start = clock.now
        var last = PageSnapshot.empty
        while !Task.isCancelled, generation == jobGeneration {
            last = await extract()
            if last.blocked || hasUsage(last) || looksSignedOut(last) {
                return last
            }
            if clock.now - start > timeout {
                if last.error == nil, last.text.isEmpty {
                    last.error = .timeout
                }
                break
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        return last
    }

    private func restoreUsage(generation: Int) async -> PageSnapshot {
        await waitUntilIdle()
        var best = await extract()
        if best.blocked || looksSignedOut(best) { return best }
        if hasUsage(best) {
            return await waitForResetDate(best, generation: generation)
        }

        var step = (await evaluate(ScrapeScripts.openUsageView) as? String) ?? "missing"
        if step == "settings" {
            await waitUntilIdle()
            try? await Task.sleep(for: .milliseconds(400))
            _ = await clickUsageIfNeeded()
            step = "usage"
        }
        if step == "usage" {
            await waitUntilIdle()
            best = merge(best, await pollExtract(generation: generation, timeout: .seconds(8)))
        }
        return await waitForResetDate(best, generation: generation)
    }

    private func waitForResetDate(_ page: PageSnapshot, generation: Int) async -> PageSnapshot {
        guard provider == .cursor, hasUsage(page), !UsageParser.hasResetDate(provider: .cursor, page: page) else {
            return page
        }
        let clock = ContinuousClock()
        let start = clock.now
        var best = page
        while !Task.isCancelled, generation == jobGeneration, clock.now - start < .seconds(5) {
            try? await Task.sleep(for: .milliseconds(400))
            let next = await extract()
            if hasUsage(next) {
                best = next
            }
            if UsageParser.hasResetDate(provider: .cursor, page: best) { break }
        }
        return best
    }

    private func isOnProviderSite() -> Bool {
        guard let host = webView.url?.host?.lowercased() else { return false }
        return provider.cookieHosts.contains { host.contains($0) }
    }

    private func load(_ url: URL, generation: Int) async {
        await navigate(generation: generation) {
            self.webView.load(URLRequest(url: url))
        }
    }

    private func navigate(generation: Int, _ work: () -> Void) async {
        await withCheckedContinuation { continuation in
            loadContinuation?.resume()
            loadContinuation = continuation
            loadGeneration = generation
            timeoutTask?.cancel()
            work()
            timeoutTask = Task.detached { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                await self?.finishLoad(ifGeneration: generation)
            }
        }
        await waitUntilIdle()
    }

    private func waitUntilIdle() async {
        let clock = ContinuousClock()
        let start = clock.now
        while webView.isLoading || loadContinuation != nil {
            if clock.now - start > .seconds(8) { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func remountUsagePanel() async {
        let action = (await evaluate(ScrapeScripts.remountUsage) as? String) ?? "missing"
        if action == "switched" {
            try? await Task.sleep(for: .milliseconds(300))
            _ = await clickUsageIfNeeded()
        }
        await waitUntilIdle()
    }

    private func clickUsageIfNeeded() async -> Bool {
        (await evaluate(ScrapeScripts.clickUsage) as? Bool) ?? false
    }

    private func extract() async -> PageSnapshot {
        let js = ScrapeScripts.extract(hints: provider.loginHints, keywords: provider.usageKeywords)
        guard let result = await evaluate(js) else {
            return PageSnapshot(loggedIn: false, blocked: false, error: .emptyDocument)
        }
        guard let raw = result as? String, let data = raw.data(using: .utf8) else {
            return PageSnapshot(loggedIn: false, blocked: false, error: .emptyDocument)
        }
        do {
            var page = try JSONDecoder().decode(PageSnapshot.self, from: data)
            if page.blocked {
                page.error = .blocked
            }
            return page
        } catch {
            log.error("extract failed \(self.provider.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return PageSnapshot(loggedIn: false, blocked: false, error: .jsThrew)
        }
    }

    private func evaluate(_ js: String) async -> Any? {
        await waitUntilIdle()
        return await withCheckedContinuation { continuation in
            let box = ResumeBox(continuation)
            webView.evaluateJavaScript(js) { result, _ in
                box.resume(result)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                box.resume(nil)
            }
        }
    }

    private func finishLoad(ifGeneration generation: Int) {
        guard loadGeneration == generation else { return }
        finishLoad()
    }

    private func hasProviderCookies() async -> Bool {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        return cookies.contains { cookie in
            provider.cookieHosts.contains { host in
                cookie.domain.localizedCaseInsensitiveContains(host)
            }
        }
    }

    private func refreshHistory() {
        let view = activeWebView
        canGoBack = view.canGoBack || view.backForwardList.backItem != nil
        canGoForward = view.canGoForward || view.backForwardList.forwardItem != nil
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if popups.contains(where: { $0 === webView }),
           let url = navigationAction.request.url,
           isProviderURL(url)
        {
            decisionHandler(.cancel)
            absorbPopup(webView, url: url)
            return
        }
        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if popups.contains(where: { $0 === webView }) {
            if let url = webView.url, isProviderURL(url) {
                absorbPopup(webView, url: url)
            }
            return
        }
        refreshHistory()
        finishLoad()
        recoverBlankMainIfNeeded()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if popups.contains(where: { $0 === webView }) { return }
        finishLoad()
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        if popups.contains(where: { $0 === webView }) { return }
        finishLoad()
    }

    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, url.absoluteString != "about:blank" {
            webView.load(navigationAction.request)
            return nil
        }
        configuration.websiteDataStore = webView.configuration.websiteDataStore
        let popup = WKWebView(frame: webView.bounds, configuration: configuration)
        popup.autoresizingMask = [.width, .height]
        popup.navigationDelegate = self
        popup.uiDelegate = self
        #if DEBUG
        if #available(macOS 13.3, *) {
            popup.isInspectable = true
        }
        #endif
        webView.addSubview(popup)
        popups.append(popup)
        return popup
    }

    public func webViewDidClose(_ webView: WKWebView) {
        dismissPopup(webView)
        recoverBlankMainIfNeeded()
    }

    private func isProviderURL(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return provider.cookieHosts.contains { host.contains($0) }
    }

    private func absorbPopup(_ popup: WKWebView, url: URL) {
        dismissPopup(popup)
        webView.load(URLRequest(url: url))
    }

    private func dismissPopup(_ popup: WKWebView) {
        popup.removeFromSuperview()
        popups.removeAll { $0 === popup }
        refreshHistory()
    }

    private func recoverBlankMainIfNeeded() {
        let raw = webView.url?.absoluteString ?? ""
        if raw.isEmpty || raw == "about:blank" {
            loadHome()
        }
    }

    private func finishLoad() {
        timeoutTask?.cancel()
        timeoutTask = nil
        loadContinuation?.resume()
        loadContinuation = nil
    }

    private static func dataStore(for provider: ProviderID) -> WKWebsiteDataStore {
        let key = "scrip.datastore.\(provider.rawValue)"
        let uuid: UUID
        if let stored = UserDefaults.standard.string(forKey: key), let parsed = UUID(uuidString: stored) {
            uuid = parsed
        } else {
            uuid = UUID()
            UserDefaults.standard.set(uuid.uuidString, forKey: key)
        }
        return WKWebsiteDataStore(forIdentifier: uuid)
    }
}

private final class ResumeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Any?, Never>?

    init(_ continuation: CheckedContinuation<Any?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Any?) {
        lock.lock()
        let taken = continuation
        continuation = nil
        lock.unlock()
        taken?.resume(returning: value)
    }
}

private extension Logger {
    func result(provider: ProviderID, page: PageSnapshot, allowNavigation: Bool) {
        let usage = UsageParser.hasStructuredUsage(provider: provider, page: page)
        info("refresh \(provider.rawValue, privacy: .public) loggedIn=\(page.loggedIn) blocked=\(page.blocked) usage=\(usage) nav=\(allowNavigation) error=\(page.error?.rawValue ?? "none", privacy: .public)")
    }
}
