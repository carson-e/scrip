import Foundation

public struct ParsedReset: Equatable, Sendable {
    public var date: Date
    public var hasTime: Bool

    public init(date: Date, hasTime: Bool) {
        self.date = date
        self.hasTime = hasTime
    }
}

public enum ResetParser {
    public static func parse(
        _ raw: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ParsedReset? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let value = parseCountdown(trimmed, now: now) { return value }
        if isUsageFilter(trimmed) { return nil }
        if let value = parseRange(trimmed, now: now, calendar: calendar) { return value }
        if let value = parseNumericRange(trimmed, now: now, calendar: calendar) { return value }
        if let value = parseDate(trimmed, now: now, calendar: calendar) { return value }
        if let value = parseWeekday(trimmed, now: now, calendar: calendar) { return value }
        if let value = parseTime(trimmed, now: now, calendar: calendar) { return value }
        return nil
    }

    private static let monthPattern =
        "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?"

    private static let weekdayNames: [(String, Int)] = [
        ("sunday", 1), ("sun", 1),
        ("monday", 2), ("mon", 2),
        ("tuesday", 3), ("tue", 3), ("tues", 3),
        ("wednesday", 4), ("wed", 4),
        ("thursday", 5), ("thu", 5), ("thur", 5), ("thurs", 5),
        ("friday", 6), ("fri", 6),
        ("saturday", 7), ("sat", 7),
    ]

    private static let months: [String: Int] = [
        "jan": 1, "january": 1,
        "feb": 2, "february": 2,
        "mar": 3, "march": 3,
        "apr": 4, "april": 4,
        "may": 5,
        "jun": 6, "june": 6,
        "jul": 7, "july": 7,
        "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10,
        "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]

    private static func isUsageFilter(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("showing") || lower.contains("filter") || lower.contains("token usage")
    }

    private static func parseNumericRange(_ raw: String, now: Date, calendar: Calendar) -> ParsedReset? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(\d{1,2})/(\d{1,2})/(\d{4})\s*(?:[-–—]|to)\s*(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(?:at\s+)?(\d{1,2}:\d{2}\s*(?:am|pm)))?"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let ns = NSRange(raw.startIndex..., in: raw)
        guard let match = regex.firstMatch(in: raw, range: ns),
              let startMonth = group(match, 1, in: raw).flatMap(Int.init),
              let startDay = group(match, 2, in: raw).flatMap(Int.init),
              let startYear = group(match, 3, in: raw).flatMap(Int.init),
              let endMonth = group(match, 4, in: raw).flatMap(Int.init),
              let endDay = group(match, 5, in: raw).flatMap(Int.init),
              let endYear = group(match, 6, in: raw).flatMap(Int.init)
        else { return nil }
        let clock = group(match, 7, in: raw).flatMap(parseClock)
        guard let start = makeDate(calendar: calendar, year: startYear, month: startMonth, day: startDay, clock: nil),
              let end = makeDate(calendar: calendar, year: endYear, month: endMonth, day: endDay, clock: clock)
        else { return nil }
        let span = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        let endDayStart = calendar.startOfDay(for: end)
        let today = calendar.startOfDay(for: now)
        if span < 20 && endDayStart <= today { return nil }
        return ParsedReset(date: end, hasTime: clock != nil)
    }

    private static func parseCountdown(_ raw: String, now: Date) -> ParsedReset? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\bin\s+((?:\d+\s*(?:days?|hrs?|hours?|mins?|minutes?)\s*)+)"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let ns = NSRange(raw.startIndex..., in: raw)
        guard let match = regex.firstMatch(in: raw, range: ns),
              let span = Range(match.range(at: 1), in: raw)
        else { return nil }
        let body = String(raw[span])
        guard let tokenRegex = try? NSRegularExpression(
            pattern: #"(\d+)\s*(days?|hrs?|hours?|mins?|minutes?)"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let tokens = tokenRegex.matches(in: body, range: NSRange(body.startIndex..., in: body))
        guard !tokens.isEmpty else { return nil }
        var interval: TimeInterval = 0
        for token in tokens {
            guard let nRange = Range(token.range(at: 1), in: body),
                  let uRange = Range(token.range(at: 2), in: body),
                  let value = Double(body[nRange])
            else { continue }
            let unit = body[uRange].lowercased()
            if unit.hasPrefix("day") { interval += value * 86_400 }
            else if unit.hasPrefix("hr") || unit.hasPrefix("hour") { interval += value * 3_600 }
            else { interval += value * 60 }
        }
        guard interval > 0 else { return nil }
        return ParsedReset(date: now.addingTimeInterval(interval), hasTime: true)
    }

    private static func parseRange(_ raw: String, now: Date, calendar: Calendar) -> ParsedReset? {
        let pattern = "(?i)(\(monthPattern))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s*(\\d{4}))?(?:\\s+(?:at\\s+)?(\\d{1,2}:\\d{2}\\s*(?:am|pm)))?\\s*(?:[-–—]|\\bto\\b)\\s*(\(monthPattern))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s*(\\d{4}))?(?:\\s+(?:at\\s+)?(\\d{1,2}:\\d{2}\\s*(?:am|pm)))?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = NSRange(raw.startIndex..., in: raw)
        guard let match = regex.firstMatch(in: raw, range: ns) else { return nil }
        let endMonth = group(match, 5, in: raw)
        let endDay = group(match, 6, in: raw).flatMap(Int.init)
        let endYear = group(match, 7, in: raw).flatMap(Int.init)
        let endClock = group(match, 8, in: raw).flatMap(parseClock)
        let startMonth = group(match, 1, in: raw)
        let startDay = group(match, 2, in: raw).flatMap(Int.init)
        let startYear = group(match, 3, in: raw).flatMap(Int.init)
        guard let endMonth, let endDay, let startMonth, let startDay,
              let endMonthNum = monthNumber(endMonth),
              let startMonthNum = monthNumber(startMonth)
        else { return nil }

        let nowYear = calendar.component(.year, from: now)
        var resolvedEndYear = endYear ?? startYear ?? nowYear
        var end = makeDate(
            calendar: calendar,
            year: resolvedEndYear,
            month: endMonthNum,
            day: endDay,
            clock: endClock
        )
        if endYear == nil, let date = end, date < calendar.date(byAdding: .day, value: -40, to: now) ?? date {
            resolvedEndYear += 1
            end = makeDate(calendar: calendar, year: resolvedEndYear, month: endMonthNum, day: endDay, clock: endClock)
        }
        if let start = makeDate(
            calendar: calendar,
            year: startYear ?? resolvedEndYear,
            month: startMonthNum,
            day: startDay,
            clock: nil
        ), let date = end, date < start {
            end = makeDate(calendar: calendar, year: resolvedEndYear + 1, month: endMonthNum, day: endDay, clock: endClock)
        }
        guard let end else { return nil }
        return ParsedReset(date: end, hasTime: endClock != nil)
    }

    private static func parseDate(_ raw: String, now: Date, calendar: Calendar) -> ParsedReset? {
        let pattern = "(?i)(\(monthPattern))\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:,?\\s*(\\d{4}))?(?:\\s+(?:at\\s+)?(\\d{1,2}:\\d{2}\\s*(?:am|pm)))?"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = NSRange(raw.startIndex..., in: raw)
        guard let match = regex.firstMatch(in: raw, range: ns) else { return nil }
        guard let monthName = group(match, 1, in: raw),
              let day = group(match, 2, in: raw).flatMap(Int.init),
              let month = monthNumber(monthName)
        else { return nil }
        let year = group(match, 3, in: raw).flatMap(Int.init)
        let clock = group(match, 4, in: raw).flatMap(parseClock)
        let nowYear = calendar.component(.year, from: now)
        var resolvedYear = year ?? nowYear
        var date = makeDate(calendar: calendar, year: resolvedYear, month: month, day: day, clock: clock)
        if year == nil, let value = date, value < calendar.date(byAdding: .day, value: -40, to: now) ?? value {
            resolvedYear += 1
            date = makeDate(calendar: calendar, year: resolvedYear, month: month, day: day, clock: clock)
        }
        guard let date else { return nil }
        return ParsedReset(date: date, hasTime: clock != nil)
    }

    private static func parseWeekday(_ raw: String, now: Date, calendar: Calendar) -> ParsedReset? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(?:resets?\s+)?(sundays?|sun|mondays?|mon|tuesdays?|tues?|wednesdays?|wed|thursdays?|thurs?|thu|fridays?|fri|saturdays?|sat)\b(?:\s+(\d{1,2}:\d{2}\s*(?:am|pm)))?"#,
            options: []
        ) else { return nil }
        let ns = NSRange(raw.startIndex..., in: raw)
        guard let match = regex.firstMatch(in: raw, range: ns),
              let name = group(match, 1, in: raw)
        else { return nil }
        let weekday = weekdayNumber(name)
        guard weekday > 0 else { return nil }
        let clock = group(match, 2, in: raw).flatMap(parseClock)
        let today = calendar.startOfDay(for: now)
        let todayWeekday = calendar.component(.weekday, from: now)
        var delta = weekday - todayWeekday
        if delta < 0 { delta += 7 }
        if delta == 0, let clock {
            var comps = calendar.dateComponents([.year, .month, .day], from: now)
            comps.hour = clock.hour
            comps.minute = clock.minute
            if let sameDay = calendar.date(from: comps), sameDay <= now {
                delta = 7
            }
        }
        guard let day = calendar.date(byAdding: .day, value: delta, to: today) else { return nil }
        if let clock {
            var comps = calendar.dateComponents([.year, .month, .day], from: day)
            comps.hour = clock.hour
            comps.minute = clock.minute
            guard let date = calendar.date(from: comps) else { return nil }
            return ParsedReset(date: date, hasTime: true)
        }
        return ParsedReset(date: day, hasTime: false)
    }

    private static func parseTime(_ raw: String, now: Date, calendar: Calendar) -> ParsedReset? {
        guard let clock = parseClock(raw) else { return nil }
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = clock.hour
        comps.minute = clock.minute
        comps.second = 0
        guard var date = calendar.date(from: comps) else { return nil }
        if date <= now {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return ParsedReset(date: date, hasTime: true)
    }

    private static func parseClock(_ raw: String) -> (hour: Int, minute: Int)? {
        guard let regex = try? NSRegularExpression(
            pattern: #"(\d{1,2}):(\d{2})\s*(am|pm)"#,
            options: [.caseInsensitive]
        ) else { return nil }
        let ns = NSRange(raw.startIndex..., in: raw)
        guard let match = regex.firstMatch(in: raw, range: ns),
              let hourRange = Range(match.range(at: 1), in: raw),
              let minuteRange = Range(match.range(at: 2), in: raw),
              let ampmRange = Range(match.range(at: 3), in: raw),
              var hour = Int(raw[hourRange]),
              let minute = Int(raw[minuteRange])
        else { return nil }
        let ampm = raw[ampmRange].lowercased()
        if ampm == "pm", hour < 12 { hour += 12 }
        if ampm == "am", hour == 12 { hour = 0 }
        return (hour, minute)
    }

    private static func makeDate(
        calendar: Calendar,
        year: Int,
        month: Int,
        day: Int,
        clock: (hour: Int, minute: Int)?
    ) -> Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = clock?.hour ?? 0
        comps.minute = clock?.minute ?? 0
        comps.second = 0
        return calendar.date(from: comps)
    }

    private static func monthNumber(_ raw: String) -> Int? {
        let key = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return months[key]
    }

    private static func weekdayNumber(_ raw: String) -> Int {
        let key = raw.lowercased()
        if let exact = weekdayNames.first(where: { key == $0.0 })?.1 { return exact }
        let stripped = key.hasSuffix("s") && key.count > 3 ? String(key.dropLast()) : key
        return weekdayNames.first(where: { stripped == $0.0 })?.1 ?? 0
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in raw: String) -> String? {
        guard index < match.numberOfRanges, match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: raw)
        else { return nil }
        return String(raw[range])
    }
}
