import Foundation

public enum ProviderID: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case grok
    case claude
    case cursor

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .grok: "Grok"
        case .claude: "Claude"
        case .cursor: "Cursor"
        }
    }

    public var homeURL: URL {
        switch self {
        case .grok: URL(string: "https://grok.com")!
        case .claude: URL(string: "https://claude.ai/")!
        case .cursor: URL(string: "https://cursor.com/dashboard")!
        }
    }

    public var usageURLs: [URL] {
        switch self {
        case .grok:
            [URL(string: "https://grok.com")!]
        case .claude:
            [
                URL(string: "https://claude.ai/settings/usage")!,
                URL(string: "https://claude.ai/settings")!,
                URL(string: "https://claude.ai/")!,
            ]
        case .cursor:
            [
                URL(string: "https://cursor.com/dashboard/usage")!,
                URL(string: "https://cursor.com/dashboard")!,
                URL(string: "https://cursor.com/settings")!,
                URL(string: "https://www.cursor.com/dashboard")!,
            ]
        }
    }

    public var loginHints: [String] {
        switch self {
        case .grok:
            [
                "Log into your account",
                "Login with Google",
                "Login with 𝕏",
                "Login with Apple",
                "Login with email",
            ]
        case .claude:
            [
                "Continue with Google",
                "Continue with email",
                "Log in to Claude",
                "Sign in to Claude",
            ]
        case .cursor:
            [
                "Sign in to Cursor",
                "Continue with GitHub",
                "Continue with Google",
                "Log in to Cursor",
            ]
        }
    }

    public var cookieHosts: [String] {
        switch self {
        case .grok: ["grok.com", "x.ai"]
        case .claude: ["claude.ai", "anthropic.com"]
        case .cursor: ["cursor.com", "cursor.sh"]
        }
    }

    public var usageKeywords: [String] {
        switch self {
        case .grok:
            ["remaining", "limit", "used", "queries", "messages", "window", "quota", "supergrok", "resets", "credits"]
        case .claude:
            ["remaining", "limit", "used", "session", "weekly", "resets", "quota", "usage", "current", "all models"]
        case .cursor:
            ["remaining", "limit", "used", "fast", "slow", "requests", "spend", "usage", "reset", "included"]
        }
    }

    public func toolbarPercent(from metrics: [UsageMetric]) -> Double? {
        switch self {
        case .grok:
            metrics.first(where: { $0.id == "weekly" })?.percent
        case .claude:
            ["session", "weekly"].compactMap { id in metrics.first(where: { $0.id == id })?.percent }.max()
        case .cursor:
            ["api", "included"].compactMap { id in metrics.first(where: { $0.id == id })?.percent }.max()
        }
    }
}

public struct UsageMetric: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var used: Double?
    public var total: Double?
    public var percent: Double?
    public var amountUSD: Double?
    public var resetsAt: Date?
    public var detail: String?
    public var windowMinutes: Int?
    public var resetHasTime: Bool?

    public init(
        id: String,
        label: String,
        used: Double? = nil,
        total: Double? = nil,
        percent: Double? = nil,
        amountUSD: Double? = nil,
        resetsAt: Date? = nil,
        detail: String? = nil,
        windowMinutes: Int? = nil,
        resetHasTime: Bool? = nil
    ) {
        self.id = id
        self.label = label
        self.used = used
        self.total = total
        self.percent = percent
        self.amountUSD = amountUSD
        self.resetsAt = resetsAt
        self.detail = detail
        self.windowMinutes = windowMinutes
        self.resetHasTime = resetHasTime
    }

    public var displayValue: String {
        if let amountUSD {
            return String(format: "$%.2f", amountUSD)
        }
        if let percent {
            if percent.rounded() == percent {
                return "\(Int(percent))%"
            }
            return String(format: "%.1f%%", percent)
        }
        if let used, let total {
            return "\(format(used)) / \(format(total))"
        }
        if let used {
            return format(used)
        }
        return "—"
    }

    private func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

public extension UsageMetric {
    /// Shortest-window-first sort key. Falls back to a guess from `id`/`label`.
    var sortWindow: Int {
        if let windowMinutes { return windowMinutes }
        let key = (id + " " + label).lowercased()
        if key.contains("5-hour") || key.contains("5 hour") || key.contains("session") { return 300 }
        if key.contains("hour")   { return 60 }
        if key.contains("daily")  || key.contains("day")  { return 1_440 }
        if key.contains("weekly") || key.contains("week") { return 10_080 }
        if key.contains("month")  { return 43_200 }
        return Int.max
    }
}

public enum ProviderAuthState: String, Codable, Sendable {
    case signedOut
    case signedIn
    case needsReauth
    case blocked
}

public struct UsageSnapshot: Codable, Hashable, Sendable {
    public var provider: ProviderID
    public var auth: ProviderAuthState
    public var metrics: [UsageMetric]
    public var rawLines: [String]
    public var updatedAt: Date
    public var error: String?

    public init(
        provider: ProviderID,
        auth: ProviderAuthState,
        metrics: [UsageMetric] = [],
        rawLines: [String] = [],
        updatedAt: Date = Date(),
        error: String? = nil
    ) {
        self.provider = provider
        self.auth = auth
        self.metrics = metrics
        self.rawLines = rawLines
        self.updatedAt = updatedAt
        self.error = error
    }

    public var toolbarPercent: Double? {
        provider.toolbarPercent(from: metrics)
    }

    public var displayMetrics: [UsageMetric] { metrics }

    public var orderedMetrics: [UsageMetric] {
        metrics.sorted { $0.sortWindow < $1.sortWindow }
    }

    public static func empty(_ provider: ProviderID, auth: ProviderAuthState = .signedOut) -> UsageSnapshot {
        UsageSnapshot(provider: provider, auth: auth)
    }
}

public struct PageBar: Codable, Hashable, Sendable {
    public var label: String
    public var value: Double?
    public var max: Double?

    public init(label: String, value: Double? = nil, max: Double? = nil) {
        self.label = label
        self.value = value
        self.max = max
    }
}

public struct LabeledNumber: Codable, Hashable, Sendable {
    public var label: String
    public var value: Double

    public init(label: String, value: Double) {
        self.label = label
        self.value = value
    }
}

public struct ScrapeCandidates: Codable, Hashable, Sendable {
    public var percents: [LabeledNumber]
    public var dollars: [LabeledNumber]
    public var resets: [String]
    public var labeledRows: [String]

    public init(
        percents: [LabeledNumber] = [],
        dollars: [LabeledNumber] = [],
        resets: [String] = [],
        labeledRows: [String] = []
    ) {
        self.percents = percents
        self.dollars = dollars
        self.resets = resets
        self.labeledRows = labeledRows
    }

    public static let empty = ScrapeCandidates()
}

public enum PageError: String, Codable, Sendable {
    case jsThrew
    case emptyDocument
    case timeout
    case blocked
}

public struct PageSnapshot: Codable, Hashable, Sendable {
    public var loggedIn: Bool
    public var blocked: Bool
    public var url: String?
    public var lines: [String]
    public var bars: [PageBar]
    public var text: String
    public var candidates: ScrapeCandidates
    public var error: PageError?

    public init(
        loggedIn: Bool,
        blocked: Bool,
        url: String? = nil,
        lines: [String] = [],
        bars: [PageBar] = [],
        text: String = "",
        candidates: ScrapeCandidates = .empty,
        error: PageError? = nil
    ) {
        self.loggedIn = loggedIn
        self.blocked = blocked
        self.url = url
        self.lines = lines
        self.bars = bars
        self.text = text
        self.candidates = candidates
        self.error = error
    }

    public static let empty = PageSnapshot(loggedIn: false, blocked: false, error: .emptyDocument)
}
