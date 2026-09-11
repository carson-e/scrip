import AppKit
import ScripCore
import ScripWeb
import SwiftUI

extension ProviderID {
    var tint: Color {
        switch self {
        case .grok: Color(red: 0.72, green: 0.74, blue: 0.80)
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.33)
        case .cursor: Color(red: 0.31, green: 0.58, blue: 0.98)
        }
    }

    var menuBarColor: NSColor {
        switch self {
        case .grok: NSColor(srgbRed: 0.72, green: 0.74, blue: 0.80, alpha: 1)
        case .claude: NSColor(srgbRed: 0.85, green: 0.47, blue: 0.33, alpha: 1)
        case .cursor: NSColor(srgbRed: 0.31, green: 0.58, blue: 0.98, alpha: 1)
        }
    }
}

extension Color {
    static let scripPanel     = Color(hex: 0x141414)
    static let scripFooter    = Color(hex: 0x0F0F0F)
    static let scripElement   = Color(hex: 0x1E1E1E)
    static let scripRowHover  = Color(hex: 0x1A1A1A)
    static let scripTrack     = Color(hex: 0x282828)
    static let scripBorderSub = Color(hex: 0x3C3C3C)
    static let scripBorderAct = Color(hex: 0x606060)
    static let scripText      = Color(hex: 0xEEEEEE)
    static let scripMuted     = Color(hex: 0x808080)
    static let scripBlue      = Color(hex: 0x005FFF)
    static let scripBlueHi    = Color(hex: 0x3385FF)
    static let scripPercent   = Color(hex: 0xFFFFAF)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: 1
        )
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Image(nsImage: MenuBarRenderer.image(from: store.snapshots, enabled: store.orderedEnabled))
            .renderingMode(.template)
    }
}

enum MenuBarRenderer {
    static func image(from snapshots: [ProviderID: UsageSnapshot], enabled: [ProviderID]) -> NSImage {
        let ids = enabled.isEmpty ? Array(ProviderID.allCases) : enabled
        let diameter: CGFloat = 13
        let lineWidth: CGFloat = 2
        let ringTextGap: CGFloat = 3
        let itemGap: CGFloat = 10
        let height: CGFloat = 18
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]
        let nameSizes = ids.map { $0.displayName.size(withAttributes: attrs) }
        let itemWidths = nameSizes.map { diameter + ringTextGap + $0.width }
        let width = max(
            itemWidths.reduce(0, +) + itemGap * CGFloat(max(ids.count - 1, 0)),
            18
        )
        let size = NSSize(width: width, height: height)
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

        if let ctx = NSGraphicsContext.current?.cgContext {
            let radius = (diameter - lineWidth) / 2
            let ink = NSColor.black
            let midY = height / 2
            var x: CGFloat = 0
            for (index, id) in ids.enumerated() {
                let snapshot = snapshots[id]
                let percent: Double? = snapshot?.auth == .signedIn ? snapshot?.toolbarPercent : nil
                let center = CGPoint(x: x + diameter / 2, y: midY)

                ctx.saveGState()
                ctx.setLineWidth(lineWidth)
                ctx.setLineCap(.round)
                ctx.setStrokeColor(ink.withAlphaComponent(0.4).cgColor)
                ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                ctx.strokePath()

                if let percent {
                    let fraction = min(max(CGFloat(percent) / 100, 0), 1)
                    if fraction > 0 {
                        ctx.setStrokeColor(ink.cgColor)
                        if fraction >= 1 {
                            ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
                        } else {
                            let start = CGFloat.pi / 2
                            ctx.addArc(
                                center: center,
                                radius: radius,
                                startAngle: start,
                                endAngle: start - 2 * .pi * fraction,
                                clockwise: true
                            )
                        }
                        ctx.strokePath()
                    }
                }
                ctx.restoreGState()

                let name = id.displayName
                let textSize = nameSizes[index]
                name.draw(
                    at: NSPoint(x: x + diameter + ringTextGap, y: midY - textSize.height / 2),
                    withAttributes: attrs
                )
                x += itemWidths[index] + itemGap
            }
        }

        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }
}

struct MenuContent: View {
    @EnvironmentObject private var store: UsageStore
    @State private var pane: Pane = .usage
    @State private var refreshHovered = false

    private enum Pane {
        case usage
        case providers
    }

    private var lastSyncText: String {
        let dates = store.orderedEnabled.compactMap { store.snapshots[$0]?.updatedAt }
        guard let date = dates.max() else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pane == .usage {
                header
                ForEach(store.orderedEnabled) { id in
                    ProviderRow(id: id)
                }
            } else {
                providersHeader
                ForEach(ProviderID.allCases) { id in
                    ProviderToggleRow(id: id)
                }
            }
            footer
        }
        .frame(width: 306)
        .background {
            ZStack {
                PanelBackdrop()
                Color.scripPanel.opacity(0.72)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.scripBorderSub, lineWidth: 1)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Scrip")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.scripText)
            Spacer()
            Text(lastSyncText)
                .font(.system(size: 11).monospaced())
                .foregroundStyle(Color.scripMuted)
            Button {
                Task { await store.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.scripText)
                    .frame(width: 20, height: 20)
                    .background(Color.scripElement)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(refreshHovered ? Color.scripBorderAct : Color.scripBorderSub, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .onHover { refreshHovered = $0 }
        }
        .padding(.top, 11)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var providersHeader: some View {
        HStack(spacing: 8) {
            Text("Providers")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.scripText)
            Spacer()
            HoverLink("Back") { pane = .usage }
        }
        .padding(.top, 11)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            Text("0.1.0")
                .font(.system(size: 11).monospaced())
                .foregroundStyle(Color.scripMuted)
            Spacer()
            HStack(spacing: 12) {
                if pane == .usage {
                    HoverLink("Providers…") { pane = .providers }
                }
                HoverLink("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
        .background(Color.scripFooter.opacity(0.72))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.scripTrack)
                .frame(height: 1)
        }
    }
}

struct ProviderToggleRow: View {
    let id: ProviderID
    @EnvironmentObject private var store: UsageStore
    @State private var rowHovered = false

    private var isOn: Bool { store.enabled.contains(id) }
    private var lastOn: Bool { isOn && store.enabled.count == 1 }

    var body: some View {
        HStack(spacing: 10) {
            Text(id.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.scripText)
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { on in
                    store.setEnabled(on, id: id)
                    if on {
                        Task { await store.refresh(id) }
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .disabled(lastOn)
            .opacity(lastOn ? 0.55 : 1)
        }
        .padding(.top, 10)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowHovered ? Color.scripRowHover.opacity(0.9) : Color.clear)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.scripTrack)
                .frame(height: 1)
        }
        .onHover { rowHovered = $0 }
    }
}

struct ProviderRow: View {
    let id: ProviderID
    @EnvironmentObject private var store: UsageStore
    @Environment(\.openWindow) private var openWindow
    @State private var rowHovered = false
    @State private var menuHovered = false

    var body: some View {
        let snapshot = store.snapshots[id] ?? .empty(id)
        let busy = store.refreshing.contains(id)
        let primary = snapshot.orderedMetrics.first
        let secondary = Array(snapshot.orderedMetrics.dropFirst().filter { $0.percent != nil }.prefix(2))

        VStack(alignment: .leading, spacing: 0) {
            titleLine(primary: primary, busy: busy, snapshot: snapshot)
            if let primary, let percent = primary.percent {
                UsageBar(fraction: min(max(percent / 100, 0), 1), height: 6, minFill: 3)
                    .padding(.top, 9)
                    .padding(.bottom, 6)
                if let reset = resetPhrase(for: primary) {
                    Text(reset)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.scripMuted)
                        .lineLimit(1)
                }
                if !secondary.isEmpty {
                    secondaryBlock(secondary)
                }
            } else {
                emptyState(snapshot)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowHovered ? Color.scripRowHover.opacity(0.9) : Color.clear)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.scripTrack)
                .frame(height: 1)
        }
        .onHover { rowHovered = $0 }
    }

    private func titleLine(primary: UsageMetric?, busy: Bool, snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 8) {
            Text(id.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.scripText)
            Spacer()
            if let primary {
                Text(primary.label)
                    .font(.system(size: 11).monospaced())
                    .foregroundStyle(Color.scripMuted)
                    .lineLimit(1)
                if let percent = primary.percent {
                    Text("\(Int(percent.rounded()))%")
                        .font(.system(size: 11, weight: .semibold).monospaced())
                        .foregroundStyle(Color.scripPercent)
                        .monospacedDigit()
                }
            }
            menuButton(busy: busy, snapshot: snapshot)
        }
    }

    private func menuButton(busy: Bool, snapshot: UsageSnapshot) -> some View {
        let signedIn = snapshot.auth == .signedIn || snapshot.auth == .needsReauth
        let glyph: Color = (menuHovered || busy) ? .scripText : .scripMuted
        return Menu {
            Button("Refresh now") { Task { await store.refresh(id) } }
            Button("Open usage page") { openLogin() }
            Divider()
            Button(signedIn ? "Sign out" : "Sign in…") {
                if signedIn {
                    Task { await store.signOut(id) }
                } else {
                    openLogin()
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11))
                .foregroundStyle(glyph)
                .frame(width: 19, height: 19)
                .background(Color.scripElement)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(menuHovered ? Color.scripBorderAct : Color.scripBorderSub, lineWidth: 1)
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(width: 19, height: 19)
        .onHover { menuHovered = $0 }
    }

    private func secondaryBlock(_ metrics: [UsageMetric]) -> some View {
        VStack(spacing: 6) {
            ForEach(metrics) { metric in
                HStack(spacing: 8) {
                    Text(metric.label)
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(Color.scripMuted)
                        .fixedSize()
                    if let percent = metric.percent {
                        UsageBar(fraction: min(max(percent / 100, 0), 1), height: 3, minFill: 2)
                            .frame(maxWidth: .infinity)
                        Text("\(Int(percent.rounded()))%")
                            .font(.system(size: 11).monospaced())
                            .foregroundStyle(Color.scripPercent)
                            .monospacedDigit()
                            .fixedSize()
                    }
                    if let reset = resetPhrase(for: metric) {
                        Text(reset)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.scripMuted)
                            .fixedSize()
                    }
                }
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.scripBorderSub)
                .frame(width: 1)
        }
        .padding(.top, 9)
    }

    private func emptyState(_ snapshot: UsageSnapshot) -> some View {
        let (note, action): (String, String) = {
            switch snapshot.auth {
            case .signedOut:
                ("Sign in once; the session stays on this Mac", "Sign in…")
            case .needsReauth:
                ("Session expired on the usage page", "Reconnect")
            case .blocked:
                ("Bot check on the usage page", "Open page")
            case .signedIn:
                if let error = snapshot.error {
                    (error, "Open page")
                } else {
                    ("Signed in, but no usage numbers were on the page", "Open page")
                }
            }
        }()
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(Color.scripMuted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action) { openLogin() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.scripBlueHi)
                .fixedSize()
        }
        .padding(.top, 7)
    }

    private func openLogin() {
        NSApp.activate()
        openWindow(id: "login", value: id)
    }
}

private struct PanelBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct UsageBar: View {
    let fraction: Double
    let height: CGFloat
    let minFill: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.scripTrack)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.scripBlue)
                        .frame(width: max(minFill, geo.size.width * fraction))
                }
            }
    }
}

private struct HoverLink: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(hovered ? Color.scripBlueHi : Color.scripText)
            .onHover { hovered = $0 }
    }
}

private func resetPhrase(for metric: UsageMetric) -> String? {
    if let date = metric.resetsAt {
        return "resets \(formatReset(date, hasTime: metric.resetHasTime ?? true))"
    }
    if let detail = metric.detail, let parsed = ResetParser.parse(detail) {
        return "resets \(formatReset(parsed.date, hasTime: parsed.hasTime))"
    }
    return nil
}

private func formatReset(_ date: Date, hasTime: Bool) -> String {
    let cal = Calendar.current
    let days = cal.dateComponents(
        [.day],
        from: cal.startOfDay(for: Date()),
        to: cal.startOfDay(for: date)
    ).day ?? Int.max
    if hasTime {
        if cal.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        let time = date.formatted(date: .omitted, time: .shortened)
        if days > 0 && days <= 6 {
            let weekday = date.formatted(.dateTime.weekday(.abbreviated))
            return "\(weekday), \(time)"
        }
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        return "\(day), \(time)"
    }
    if cal.isDateInToday(date) { return "today" }
    if days > 0 && days <= 6 {
        return date.formatted(.dateTime.weekday(.abbreviated))
    }
    return date.formatted(.dateTime.month(.abbreviated).day())
}

struct LoginView: View {
    let providerID: ProviderID
    @EnvironmentObject private var runtime: AppRuntime

    var body: some View {
        LoginChrome(providerID: providerID, session: runtime.session(for: providerID))
    }
}

struct LoginChrome: View {
    let providerID: ProviderID
    @ObservedObject var session: ProviderWebSession
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        WebViewHost(webView: session.webView)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                store.loginOpen.insert(providerID)
                session.loadHomeIfNeeded()
            }
            .onDisappear {
                store.loginOpen.remove(providerID)
            }
            .background(
                LoginWindowChrome(
                    title: providerID.displayName,
                    bar: LoginButtonBar(providerID: providerID, session: session, store: store)
                )
            )
    }
}

private struct LoginButtonBar: View {
    let providerID: ProviderID
    @ObservedObject var session: ProviderWebSession
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button("Back") { session.goBack() }
                .disabled(!session.canGoBack)
                .keyboardShortcut("[", modifiers: .command)
            Button("Forward") { session.goForward() }
                .disabled(!session.canGoForward)
                .keyboardShortcut("]", modifiers: .command)
            Button("Reload") { session.reloadPage() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Home") { session.loadHome() }
            Spacer(minLength: 8)
            Button("Refresh usage") {
                Task { await store.refresh(providerID) }
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.bar)
    }
}

private struct LoginWindowChrome<Bar: View>: NSViewRepresentable {
    let title: String
    let bar: Bar

    func makeNSView(context: Context) -> ChromeView {
        let view = ChromeView(title: title, bar: bar)
        return view
    }

    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.title = title
        nsView.hosting.rootView = bar
        nsView.attach()
    }

    static func dismantleNSView(_ nsView: ChromeView, coordinator: ()) {
        nsView.detach()
    }

    final class ChromeView: NSView {
        var title: String
        let hosting: NSHostingView<Bar>
        private var accessory: NSTitlebarAccessoryViewController?

        init(title: String, bar: Bar) {
            self.title = title
            self.hosting = NSHostingView(rootView: bar)
            super.init(frame: .zero)
            hosting.frame = NSRect(x: 0, y: 0, width: 920, height: 44)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        func attach() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.title = self.title
                window.titleVisibility = .visible
                window.titlebarAppearsTransparent = false
                window.styleMask.remove(.fullSizeContentView)
                window.toolbar = nil
                if self.accessory == nil {
                    let accessory = NSTitlebarAccessoryViewController()
                    accessory.layoutAttribute = .bottom
                    accessory.view = self.hosting
                    window.addTitlebarAccessoryViewController(accessory)
                    self.accessory = accessory
                }
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
                 window.isRestorable = false
                 window.orderFrontRegardless()
            }
        }

        func detach() {
            guard let accessory else { return }
            if let window, let index = window.titlebarAccessoryViewControllers.firstIndex(of: accessory) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            self.accessory = nil
        }
    }
}
