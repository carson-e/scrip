import Foundation

public enum UsageParser {
    public static func snapshot(provider: ProviderID, page: PageSnapshot) -> UsageSnapshot {
        if page.blocked || page.error == .blocked {
            return UsageSnapshot(
                provider: provider,
                auth: .blocked,
                rawLines: page.lines,
                error: "Blocked by the site"
            )
        }
        if !page.loggedIn {
            return UsageSnapshot(
                provider: provider,
                auth: .signedOut,
                rawLines: page.lines,
                error: page.error?.rawValue
            )
        }

        switch provider {
        case .cursor:
            return cursorSnapshot(from: page)
        case .claude:
            return claudeSnapshot(from: page)
        case .grok:
            return grokSnapshot(from: page)
        }
    }

    public static func hasStructuredUsage(provider: ProviderID, page: PageSnapshot) -> Bool {
        let snap = snapshot(provider: provider, page: page)
        return snap.auth == .signedIn
            && snap.metrics.contains { $0.percent != nil || $0.amountUSD != nil }
    }

    public static func hasResetDate(provider: ProviderID, page: PageSnapshot) -> Bool {
        switch provider {
        case .cursor:
            return cursorCycleReset(from: page) != nil
        default:
            return true
        }
    }

    private static func grokSnapshot(from page: PageSnapshot) -> UsageSnapshot {
        let split = grokSplit(from: page)
        var metrics: [UsageMetric] = []
        if split.weekly != nil || split.weeklyReset != nil {
            let parsed = ResetParser.parse(split.weeklyReset ?? "")
            metrics.append(
                UsageMetric(
                    id: "weekly",
                    label: "Weekly SuperGrok",
                    percent: split.weekly,
                    resetsAt: parsed?.date,
                    detail: split.weeklyReset,
                    resetHasTime: parsed?.hasTime
                )
            )
        }
        if let credits = split.credits {
            metrics.append(
                UsageMetric(
                    id: "credits",
                    label: "Extra credits",
                    amountUSD: credits,
                    detail: "Additional Credits"
                )
            )
        }
        return UsageSnapshot(
            provider: .grok,
            auth: .signedIn,
            metrics: metrics,
            rawLines: page.lines
        )
    }

    private static func claudeSnapshot(from page: PageSnapshot) -> UsageSnapshot {
        let split = claudeSplit(from: page)
        var metrics: [UsageMetric] = []
        if split.session != nil || split.sessionReset != nil {
            let parsed = ResetParser.parse(split.sessionReset ?? "")
            metrics.append(
                UsageMetric(
                    id: "session",
                    label: "5-hour",
                    percent: split.session,
                    resetsAt: parsed?.date,
                    detail: split.sessionReset,
                    resetHasTime: parsed?.hasTime
                )
            )
        }
        if split.weekly != nil || split.weeklyReset != nil {
            let parsed = ResetParser.parse(split.weeklyReset ?? "")
            metrics.append(
                UsageMetric(
                    id: "weekly",
                    label: "Weekly",
                    percent: split.weekly,
                    resetsAt: parsed?.date,
                    detail: split.weeklyReset,
                    resetHasTime: parsed?.hasTime
                )
            )
        }
        return UsageSnapshot(
            provider: .claude,
            auth: .signedIn,
            metrics: metrics,
            rawLines: page.lines
        )
    }

    private static func cursorSnapshot(from page: PageSnapshot) -> UsageSnapshot {
        let split = cursorSplit(from: page)
        let cycle = cursorCycleReset(from: page)
        var metrics: [UsageMetric] = []
        if let api = split.api {
            metrics.append(
                UsageMetric(
                    id: "api",
                    label: "API",
                    percent: api,
                    resetsAt: cycle?.date,
                    detail: "Other Models",
                    resetHasTime: cycle?.hasTime
                )
            )
        }
        if let included = split.included {
            metrics.append(
                UsageMetric(
                    id: "included",
                    label: "Included",
                    percent: included,
                    resetsAt: cycle?.date,
                    detail: "Cursor Models",
                    resetHasTime: cycle?.hasTime
                )
            )
        }
        return UsageSnapshot(
            provider: .cursor,
            auth: .signedIn,
            metrics: metrics,
            rawLines: page.lines
        )
    }

    private static func grokSplit(from page: PageSnapshot) -> (
        weekly: Double?,
        weeklyReset: String?,
        credits: Double?
    ) {
        let blob = page.text.isEmpty ? page.lines.joined(separator: "\n") : page.text
        let weekly = grokWeekly(from: page, blob: blob)
        var weeklyReset = page.candidates.resets.first
            ?? firstMatch(in: blob, pattern: #"(Resets\s+[^\n]+)"#)
            ?? firstReset(in: page.lines, from: 0)
        if let reset = weeklyReset, !reset.lowercased().hasPrefix("resets") {
            weeklyReset = "Resets \(reset)"
        }
        let credits = grokCredits(from: page, blob: blob)
        return (weekly, weeklyReset, credits)
    }

    private static func grokWeekly(from page: PageSnapshot, blob: String) -> Double? {
        if let match = page.candidates.percents.first(where: {
            let lower = $0.label.lowercased()
            return lower.contains("used") || lower.contains("supergrok")
        }) {
            return match.value
        }
        if let value = firstMatchDouble(in: blob, pattern: #"(?i)weekly\s+supergrok[\s\S]{0,500}?(\d+(?:\.\d+)?)\s*%"#) {
            return value
        }
        if let value = firstMatchDouble(in: blob, pattern: #"(\d+(?:\.\d+)?)\s*%\s*used"#) {
            return value
        }
        return nil
    }

    private static func grokCredits(from page: PageSnapshot, blob: String) -> Double? {
        if let match = page.candidates.dollars.first(where: {
            let lower = $0.label.lowercased()
            return lower.contains("credit") || lower.contains("additional")
        }) {
            return match.value
        }
        if let range = blob.range(of: #"(?i)(?:additional\s+credits|extra\s+credits|credits)[\s\S]{0,80}\$(\d+(?:\.\d+)?)"#, options: .regularExpression) {
            let slice = String(blob[range])
            return firstMatchDouble(in: slice, pattern: #"\$(\d+(?:\.\d+)?)"#)
        }
        return nil
    }

    private static func claudeSplit(from page: PageSnapshot) -> (
        session: Double?,
        sessionReset: String?,
        weekly: Double?,
        weeklyReset: String?
    ) {
        let blob = page.text.isEmpty ? page.lines.joined(separator: "\n") : page.text
        var session = percentNear(labels: ["current session", "5-hour", "5 hour"], in: page, blob: blob)
            ?? firstMatchDouble(in: blob, pattern: #"Current session[\s\S]{0,400}?(\d+(?:\.\d+)?)\s*%\s*used"#)
        var sessionReset = resetNear(labels: ["current session", "5-hour", "5 hour"], in: page, blob: blob)
            ?? firstMatch(in: blob, pattern: #"Current session[\s\S]{0,200}?Resets\s+([^\n]+)"#)
        var weekly = percentNear(labels: ["all models", "weekly"], in: page, blob: blob)
            ?? firstMatchDouble(in: blob, pattern: #"All models[\s\S]{0,400}?(\d+(?:\.\d+)?)\s*%\s*used"#)
        var weeklyReset = resetNear(labels: ["all models", "weekly"], in: page, blob: blob)
            ?? firstMatch(in: blob, pattern: #"All models[\s\S]{0,200}?Resets\s+([^\n]+)"#)

        let lines = page.lines
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            if lower.contains("boost") || lower.contains("higher") { continue }
            if session == nil, lower.contains("current session") || lower.contains("5-hour") {
                session = firstPercent(in: lines, from: index)
                if sessionReset == nil { sessionReset = firstReset(in: lines, from: index) }
            }
            if weekly == nil, lower.contains("all models") {
                weekly = firstPercent(in: lines, from: index)
                if weeklyReset == nil { weeklyReset = firstReset(in: lines, from: index) }
            }
        }
        if let reset = sessionReset, !reset.lowercased().hasPrefix("resets") {
            sessionReset = "Resets \(reset)"
        }
        if let reset = weeklyReset, !reset.lowercased().hasPrefix("resets") {
            weeklyReset = "Resets \(reset)"
        }
        return (session, sessionReset, weekly, weeklyReset)
    }

    private static func cursorSplit(from page: PageSnapshot) -> (api: Double?, included: Double?) {
        let blob = page.text.isEmpty ? page.lines.joined(separator: "\n") : page.text
        let rows = page.lines + page.bars.map(\.label) + page.candidates.labeledRows + page.candidates.percents.map(\.label)
        let included = page.candidates.percents.first(where: { $0.label.lowercased().contains("cursor models") })?.value
            ?? rows.compactMap { row -> Double? in
                let lower = row.lowercased()
                guard lower.contains("cursor models") else { return nil }
                return percent(in: row)
            }.first
            ?? firstMatchDouble(in: blob, pattern: #"(?i)cursor models[\s\S]{0,80}?(\d+(?:\.\d+)?)\s*%"#)
        let api = page.candidates.percents.first(where: { $0.label.lowercased().contains("other models") })?.value
            ?? rows.compactMap { row -> Double? in
                let lower = row.lowercased()
                guard lower.contains("other models") else { return nil }
                return percent(in: row)
            }.first
            ?? firstMatchDouble(in: blob, pattern: #"(?i)other models[\s\S]{0,80}?(\d+(?:\.\d+)?)\s*%"#)
        return (api, included)
    }

    private static func percentNear(labels: [String], in page: PageSnapshot, blob: String) -> Double? {
        if let match = page.candidates.percents.first(where: { item in
            let lower = item.label.lowercased()
            return labels.contains { lower.contains($0) }
        }) {
            return match.value
        }
        return nil
    }

    private static func resetNear(labels: [String], in page: PageSnapshot, blob: String) -> String? {
        page.candidates.resets.first { reset in
            let lower = reset.lowercased()
            return labels.contains { lower.contains($0) }
        }
    }

    private static func cursorCycleReset(from page: PageSnapshot) -> ParsedReset? {
        let blob = page.text.isEmpty ? page.lines.joined(separator: "\n") : page.text
        let chunks = page.candidates.resets
            + page.lines
            + page.candidates.labeledRows
            + blob.split(whereSeparator: \.isNewline).map(String.init)
            + monthNameRanges(in: blob)
        for chunk in chunks {
            let lower = chunk.lowercased()
            let hasReset = lower.contains("reset")
            guard hasReset || looksLikeDateRange(chunk) else { continue }
            if let parsed = ResetParser.parse(chunk) { return parsed }
        }
        let dates = monthNameDates(in: blob + "\n" + chunks.joined(separator: "\n")).compactMap { raw -> ParsedReset? in
            guard let parsed = ResetParser.parse(raw), !parsed.hasTime else { return nil }
            return parsed
        }
        let now = Date()
        let future = dates.filter { $0.date >= Calendar.current.startOfDay(for: now) }
        return future.max(by: { $0.date < $1.date }) ?? dates.max(by: { $0.date < $1.date })
    }

    private static func monthNameRanges(in text: String) -> [String] {
        let pattern = #"(?i)(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:,\s*\d{4})?\s*[-–—]\s*(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}(?:,\s*\d{4})?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: ns).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static func monthNameDates(in text: String) -> [String] {
        let pattern = #"(?i)(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2},?\s*\d{4}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: ns).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]) }
        }
    }

    private static func looksLikeDateRange(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        if lower.contains(" to ") { return true }
        if raw.contains("–") || raw.contains("—") { return true }
        return raw.range(
            of: #"(?i)(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}.+[-–—]\s*(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)"#,
            options: .regularExpression
        ) != nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[capture]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatchDouble(in text: String, pattern: String) -> Double? {
        guard let raw = firstMatch(in: text, pattern: pattern) else { return nil }
        return Double(raw)
    }

    private static func firstPercent(in lines: [String], from index: Int) -> Double? {
        let end = min(index + 8, lines.count)
        for line in lines[index..<end] {
            let lower = line.lowercased()
            if lower.contains("higher") || lower.contains("boost") { continue }
            if let value = percent(in: line) { return value }
        }
        return nil
    }

    private static func firstReset(in lines: [String], from index: Int) -> String? {
        let end = min(index + 8, lines.count)
        for line in lines[index..<end] {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().contains("reset") {
                return trimmed
            }
        }
        return nil
    }

    private static func percent(in line: String) -> Double? {
        guard let match = line.range(of: #"(\d+(?:\.\d+)?)\s*%"#, options: .regularExpression) else {
            return nil
        }
        let number = line[match].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        return Double(number)
    }
}
