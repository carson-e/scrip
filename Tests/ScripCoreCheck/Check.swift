import Foundation
import ScripCore

@main
struct ScripCoreCheck {
    static func main() async {
        var failures = 0

        func expect(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) {
            if !condition {
                failures += 1
                fputs("FAIL \(file):\(line) \(message)\n", stderr)
            }
        }

        do {
            let snap = UsageParser.snapshot(provider: .grok, page: FixtureLoader.page("grok-signed-in"))
            expect(snap.auth == .signedIn, "grok auth")
            expect(snap.metrics.first(where: { $0.id == "weekly" })?.percent == 42, "grok weekly")
            expect(snap.metrics.first(where: { $0.id == "credits" })?.amountUSD == 5, "grok credits")
            expect(snap.toolbarPercent == 42, "grok toolbar")
            expect(snap.orderedMetrics.first?.id == "weekly", "grok weekly leads")
            expect(snap.metrics.first(where: { $0.id == "weekly" })?.detail?.localizedCaseInsensitiveContains("resets") == true, "grok reset")
            expect(snap.metrics.first(where: { $0.id == "weekly" })?.resetsAt != nil, "grok weekly resetsAt")
            expect(snap.metrics.first(where: { $0.id == "weekly" })?.resetHasTime == false, "grok weekly no time")
        }

        do {
            let snap = UsageParser.snapshot(provider: .grok, page: FixtureLoader.page("grok-usage-buried"))
            expect(snap.metrics.first(where: { $0.id == "weekly" })?.percent == 7, "grok buried weekly")
        }

        do {
            let snap = UsageParser.snapshot(provider: .grok, page: FixtureLoader.page("grok-signed-in-no-percent"))
            expect(snap.auth == .signedIn, "grok no-usage auth")
            expect(snap.metrics.first(where: { $0.id == "weekly" })?.percent == nil, "grok no invented percent")
            expect(snap.metrics.first(where: { $0.id == "credits" }) == nil, "grok no invented credits")
            expect(snap.toolbarPercent == nil, "grok no toolbar")
        }

        do {
            let snap = UsageParser.snapshot(provider: .claude, page: FixtureLoader.page("claude-settings-usage"))
            expect(snap.metrics.first(where: { $0.id == "session" })?.percent == 12, "claude session")
            expect(snap.metrics.first(where: { $0.id == "weekly" })?.percent == 40, "claude weekly")
            expect(snap.toolbarPercent == 40, "claude toolbar")
            expect(snap.orderedMetrics.first?.id == "session", "claude shortest window first")
            expect(snap.metrics.first(where: { $0.id == "session" })?.resetsAt != nil, "claude session resetsAt")
            expect(snap.metrics.first(where: { $0.id == "session" })?.resetHasTime == true, "claude session has time")
            expect(snap.metrics.first(where: { $0.id == "weekly" })?.resetsAt != nil, "claude weekly resetsAt")
            expect(snap.metrics.first(where: { $0.id == "weekly" })?.resetHasTime == false, "claude weekly weekday")
        }

        do {
            let snap = UsageParser.snapshot(provider: .claude, page: FixtureLoader.page("claude-settings-usage-boost"))
            expect(snap.metrics.first(where: { $0.id == "session" })?.percent == 18, "claude boost session")
            expect(snap.metrics.first(where: { $0.id == "weekly" })?.percent == 55, "claude boost weekly")
            expect(!snap.metrics.contains { $0.percent == 90 || $0.percent == 99 }, "claude ignores boost")
        }

        do {
            let snap = UsageParser.snapshot(provider: .cursor, page: FixtureLoader.page("cursor-dashboard"))
            expect(snap.metrics.first(where: { $0.id == "included" })?.percent == 23, "cursor included")
            expect(snap.metrics.first(where: { $0.id == "api" })?.percent == 71, "cursor api")
            expect(snap.toolbarPercent == 71, "cursor toolbar")
            let includedReset = snap.metrics.first(where: { $0.id == "included" })?.resetsAt
            let apiReset = snap.metrics.first(where: { $0.id == "api" })?.resetsAt
            expect(includedReset != nil, "cursor included resetsAt")
            expect(includedReset == apiReset, "cursor metrics share cycle end")
            expect(snap.metrics.first(where: { $0.id == "included" })?.resetHasTime == false, "cursor range has no time")
            if let date = includedReset {
                let cal = Calendar.current
                expect(cal.component(.month, from: date) == 10, "cursor end month")
                expect(cal.component(.day, from: date) == 3, "cursor end day")
            }
        }

        do {
            let page = PageSnapshot(
                loggedIn: true,
                blocked: false,
                lines: ["Sep 3, 2026 - Oct 3, 2026", "Sep 11 at 07:13 PM", "Included"],
                text: "Included Usage\nSep 3, 2026 - Oct 3, 2026\nCursor Models 15M tokens 1.8%\nOther Models 30.3M tokens 15.1%",
                candidates: ScrapeCandidates()
            )
            let snap = UsageParser.snapshot(provider: .cursor, page: page)
            expect(snap.metrics.first(where: { $0.id == "included" })?.percent == 1.8, "cursor percents from text")
            expect(snap.metrics.first(where: { $0.id == "api" })?.percent == 15.1, "cursor api from text")
            expect(snap.metrics.first(where: { $0.id == "included" })?.resetsAt != nil, "cursor cycle from crowded lines")
        }

        do {
            let page = PageSnapshot(
                loggedIn: true,
                blocked: false,
                lines: ["Included Usage", "Sep 3, 2026", "Oct 3, 2026", "Cursor Models 10%"],
                text: "Included Usage\nSep 3, 2026\nOct 3, 2026\nCursor Models 10%",
                candidates: ScrapeCandidates(percents: [LabeledNumber(label: "Cursor Models 10%", value: 10)])
            )
            let snap = UsageParser.snapshot(provider: .cursor, page: page)
            let date = snap.metrics.first(where: { $0.id == "included" })?.resetsAt
            expect(date != nil, "cursor split dates resetsAt")
            if let date {
                expect(Calendar.current.component(.month, from: date) == 10, "cursor split end month")
                expect(Calendar.current.component(.day, from: date) == 3, "cursor split end day")
            }
        }

        do {
            let snap = UsageParser.snapshot(provider: .claude, page: FixtureLoader.page("claude-settings-usage-countdown"))
            let session = snap.metrics.first(where: { $0.id == "session" })
            let weekly = snap.metrics.first(where: { $0.id == "weekly" })
            expect(session?.percent == 98, "claude countdown session")
            expect(weekly?.percent == 49, "claude countdown weekly")
            expect(session?.resetHasTime == true, "claude countdown session has time")
            expect(weekly?.resetHasTime == true, "claude countdown weekly has time")
            if let sessionAt = session?.resetsAt, let weeklyAt = weekly?.resetsAt {
                let sessionDelta = sessionAt.timeIntervalSinceNow
                let weeklyDelta = weeklyAt.timeIntervalSinceNow
                expect(abs(sessionDelta - (3 * 3600 + 42 * 60)) < 5, "claude session countdown interval")
                expect(abs(weeklyDelta - (12 * 3600 + 12 * 60)) < 5, "claude weekly countdown interval")
                expect(weeklyAt > sessionAt, "claude weekly later than session")
            } else {
                expect(false, "claude countdown missing resetsAt")
            }
        }

        do {
            let snap = UsageParser.snapshot(provider: .cursor, page: FixtureLoader.page("cursor-dashboard-no-usage"))
            expect(snap.auth == .signedIn, "cursor missing auth")
            expect(snap.metrics.isEmpty, "cursor missing is not 0%")
            expect(snap.toolbarPercent == nil, "cursor missing toolbar")
        }

        do {
            let snap = UsageParser.snapshot(provider: .grok, page: FixtureLoader.page("blocked"))
            expect(snap.auth == .blocked, "blocked auth")
            expect(snap.error == "Blocked by the site", "blocked error")
        }

        do {
            let snap = UsageParser.snapshot(provider: .grok, page: FixtureLoader.page("signed-out"))
            expect(snap.auth == .signedOut, "signed out")
            expect(snap.metrics.isEmpty, "signed out metrics")
        }

        expect(UsageParser.hasStructuredUsage(provider: .grok, page: FixtureLoader.page("grok-signed-in")), "has usage grok")
        expect(!UsageParser.hasStructuredUsage(provider: .grok, page: FixtureLoader.page("grok-signed-in-no-percent")), "no usage grok")
        expect(!UsageParser.hasStructuredUsage(provider: .cursor, page: FixtureLoader.page("cursor-dashboard-no-usage")), "no usage cursor")
        expect(UsageParser.hasStructuredUsage(provider: .cursor, page: FixtureLoader.page("cursor-dashboard")), "has usage cursor")

        failures += runResetParserChecks()
        failures += await runStoreChecks()

        if failures > 0 {
            fputs("\(failures) failed\n", stderr)
            exit(1)
        }
        print("All checks passed")
    }
}

func runResetParserChecks() -> Int {
    var failures = 0
    func expect(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) {
        if !condition {
            failures += 1
            fputs("FAIL \(file):\(line) \(message)\n", stderr)
        }
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 11, hour: 14, minute: 0))!

    if let parsed = ResetParser.parse("Resets in 3 hr 42 min", now: now, calendar: calendar) {
        expect(parsed.hasTime, "countdown has time")
        expect(abs(parsed.date.timeIntervalSince(now) - (3 * 3600 + 42 * 60)) < 1, "countdown interval")
    } else {
        expect(false, "countdown parse")
    }

    if let parsed = ResetParser.parse("Resets 3:00 PM", now: now, calendar: calendar) {
        expect(parsed.hasTime, "clock has time")
        expect(calendar.component(.hour, from: parsed.date) == 15, "clock hour")
        expect(calendar.isDate(parsed.date, inSameDayAs: now), "clock today")
    } else {
        expect(false, "clock parse")
    }

    if let parsed = ResetParser.parse("Resets Sunday", now: now, calendar: calendar) {
        expect(!parsed.hasTime, "weekday no time")
        expect(calendar.component(.weekday, from: parsed.date) == 1, "weekday sunday")
        expect(calendar.startOfDay(for: parsed.date) > calendar.startOfDay(for: now), "weekday upcoming")
    } else {
        expect(false, "weekday parse")
    }

    if let parsed = ResetParser.parse("Sep 3, 2026 - Oct 3, 2026", now: now, calendar: calendar) {
        expect(!parsed.hasTime, "cursor billing no time")
        expect(calendar.component(.month, from: parsed.date) == 10, "cursor billing month")
        expect(calendar.component(.day, from: parsed.date) == 3, "cursor billing day")
        expect(calendar.component(.year, from: parsed.date) == 2026, "cursor billing year")
    } else {
        expect(false, "cursor billing range parse")
    }

    if let parsed = ResetParser.parse("Sep 11 – Oct 11", now: now, calendar: calendar) {
        expect(!parsed.hasTime, "range no time")
        expect(calendar.component(.month, from: parsed.date) == 10, "range end month")
        expect(calendar.component(.day, from: parsed.date) == 11, "range end day")
        expect(calendar.component(.year, from: parsed.date) == 2026, "range end year")
    } else {
        expect(false, "range parse")
    }

    expect(ResetParser.parse("Cursor Models", now: now, calendar: calendar) == nil, "ignore non-reset")

    if let parsed = ResetParser.parse("Resets September 15, 2026 at 11:52 AM", now: now, calendar: calendar) {
        expect(parsed.hasTime, "grok absolute has time")
        expect(calendar.component(.year, from: parsed.date) == 2026, "grok year")
        expect(calendar.component(.month, from: parsed.date) == 9, "grok month")
        expect(calendar.component(.day, from: parsed.date) == 15, "grok day")
        expect(calendar.component(.hour, from: parsed.date) == 11, "grok hour")
        expect(calendar.component(.minute, from: parsed.date) == 52, "grok minute")
    } else {
        expect(false, "grok absolute parse")
    }

    if let parsed = ResetParser.parse("Showing token usage and costs from 9/5/2026 to 9/11/2026.", now: now, calendar: calendar) {
        expect(false, "should ignore cursor filter range, got \(parsed.date)")
    }

    return failures
}

@MainActor
func runStoreChecks() async -> Int {
    var failures = 0
    func expect(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) {
        if !condition {
            failures += 1
            fputs("FAIL \(file):\(line) \(message)\n", stderr)
        }
    }

    do {
        let good = UsageParser.snapshot(provider: .grok, page: FixtureLoader.page("grok-signed-in"))
        let cache = MemorySnapshotCache(storage: [.grok: good])
        let fetcher = FakeFetcher(pages: [PageSnapshot(loggedIn: false, blocked: false, error: .jsThrew)])
        let store = UsageStore(fetchers: [.grok: fetcher], cache: cache, startTimer: false, refreshOnLaunch: false)
        store.snapshots[.grok] = good
        await store.refresh(.grok)
        expect(store.snapshots[.grok]?.auth == .needsReauth, "keep last good auth")
        expect(store.snapshots[.grok]?.metrics.first(where: { $0.id == "weekly" })?.percent == 42, "keep last good weekly")
        expect(cache.storage[.grok]?.metrics.first(where: { $0.id == "weekly" })?.percent == 42, "keep cache")
    }

    do {
        let good = UsageParser.snapshot(provider: .claude, page: FixtureLoader.page("claude-settings-usage"))
        let cache = MemorySnapshotCache(storage: [.claude: good])
        let fetcher = FakeFetcher(pages: [.empty])
        let store = UsageStore(fetchers: [.claude: fetcher], cache: cache, startTimer: false, refreshOnLaunch: false)
        store.snapshots[.claude] = good
        await store.refresh(.claude)
        expect(store.snapshots[.claude]?.auth == .needsReauth, "empty doc keep auth")
        expect(store.snapshots[.claude]?.metrics.first(where: { $0.id == "session" })?.percent == 12, "empty doc keep session")
    }

    do {
        let good = UsageParser.snapshot(provider: .grok, page: FixtureLoader.page("grok-signed-in"))
        let cache = MemorySnapshotCache(storage: [.grok: good])
        let fetcher = FakeFetcher(pages: [FixtureLoader.page("signed-out")])
        let store = UsageStore(fetchers: [.grok: fetcher], cache: cache, startTimer: false, refreshOnLaunch: false)
        store.snapshots[.grok] = good
        await store.refresh(.grok)
        expect(store.snapshots[.grok]?.auth == .signedOut, "genuine sign out")
        expect(cache.storage[.grok] == nil, "sign out clears cache")
    }

    do {
        let good = UsageParser.snapshot(provider: .grok, page: FixtureLoader.page("grok-signed-in"))
        let cache = MemorySnapshotCache(storage: [.grok: good])
        let fetcher = FakeFetcher(pages: [FixtureLoader.page("grok-signed-in-no-percent")])
        let store = UsageStore(fetchers: [.grok: fetcher], cache: cache, startTimer: false, refreshOnLaunch: false)
        store.snapshots[.grok] = good
        await store.refresh(.grok)
        expect(store.snapshots[.grok]?.auth == .signedIn, "chat page keep auth")
        expect(store.snapshots[.grok]?.metrics.first(where: { $0.id == "weekly" })?.percent == 42, "chat page keep weekly")
    }

    do {
        let good = UsageParser.snapshot(provider: .grok, page: FixtureLoader.page("grok-signed-in"))
        let cache = MemorySnapshotCache(storage: [.grok: good])
        let fetcher = FakeFetcher(pages: [])
        let store = UsageStore(fetchers: [.grok: fetcher], cache: cache, startTimer: false, refreshOnLaunch: false)
        store.snapshots[.grok] = good
        await store.signOut(.grok)
        expect(fetcher.signOutCount == 1, "signOut called")
        expect(store.snapshots[.grok]?.auth == .signedOut, "signOut snapshot")
        expect(cache.storage[.grok] == nil, "signOut cache")
    }

    do {
        let fetcher = FakeFetcher(pages: [FixtureLoader.page("grok-signed-in"), FixtureLoader.page("signed-out")])
        fetcher.delayNanoseconds = 80_000_000
        let store = UsageStore(fetchers: [.grok: fetcher], cache: MemorySnapshotCache(), startTimer: false, refreshOnLaunch: false)
        async let first: Void = store.refresh(.grok)
        async let second: Void = store.refresh(.grok)
        _ = await (first, second)
        expect(fetcher.fetchCount == 1, "coalesced refresh")
        expect(store.snapshots[.grok]?.auth == .signedIn, "coalesced result")
    }

    do {
        let fetcher = FakeFetcher(pages: [FixtureLoader.page("grok-signed-in")])
        let store = UsageStore(fetchers: [.grok: fetcher], cache: MemorySnapshotCache(), startTimer: false, refreshOnLaunch: false)
        store.loginOpen.insert(.grok)
        await store.refresh(.grok)
        expect(fetcher.lastAllowNavigation == false, "login extract only")
    }

    do {
        let grok = FakeFetcher(pages: [FixtureLoader.page("grok-signed-in")])
        let claude = FakeFetcher(pages: [FixtureLoader.page("claude-settings-usage")])
        let store = UsageStore(fetchers: [.grok: grok, .claude: claude], cache: MemorySnapshotCache(), startTimer: false, refreshOnLaunch: false)
        store.loginOpen.insert(.grok)
        await store.refreshAll()
        expect(grok.fetchCount == 1, "extract during login")
        expect(grok.lastAllowNavigation == false, "login extract only in refreshAll")
        expect(claude.fetchCount == 1, "refresh other providers")
    }

    do {
        let store = UsageStore(
            fetchers: [:],
            cache: MemorySnapshotCache(),
            enabledCache: MemoryEnabledProviderCache(),
            startTimer: false,
            refreshOnLaunch: false
        )
        expect(store.enabled == Set(ProviderID.allCases), "default all on")
    }

    do {
        let enabledCache = MemoryEnabledProviderCache()
        let store = UsageStore(
            fetchers: [:],
            cache: MemorySnapshotCache(),
            enabledCache: enabledCache,
            startTimer: false,
            refreshOnLaunch: false
        )
        store.setEnabled(false, id: .cursor)
        expect(enabledCache.storage == Set([.grok, .claude]), "persist save")
        let loaded = UsageStore(
            fetchers: [:],
            cache: MemorySnapshotCache(),
            enabledCache: enabledCache,
            startTimer: false,
            refreshOnLaunch: false
        )
        expect(loaded.enabled == Set([.grok, .claude]), "persist load")
        expect(loaded.orderedEnabled == [.grok, .claude], "ordered enabled")
    }

    do {
        let store = UsageStore(
            fetchers: [:],
            cache: MemorySnapshotCache(),
            enabledCache: MemoryEnabledProviderCache(),
            startTimer: false,
            refreshOnLaunch: false
        )
        store.setEnabled(false, id: .claude)
        store.setEnabled(false, id: .cursor)
        expect(store.enabled == Set([.grok]), "two off")
        store.setEnabled(false, id: .grok)
        expect(store.enabled == Set([.grok]), "cannot empty")
    }

    do {
        let grok = FakeFetcher(pages: [FixtureLoader.page("grok-signed-in")])
        let claude = FakeFetcher(pages: [FixtureLoader.page("claude-settings-usage")])
        let store = UsageStore(
            fetchers: [.grok: grok, .claude: claude],
            cache: MemorySnapshotCache(),
            enabledCache: MemoryEnabledProviderCache(),
            startTimer: false,
            refreshOnLaunch: false
        )
        store.setEnabled(false, id: .grok)
        await store.refreshAll()
        expect(grok.fetchCount == 0, "skip disabled in refreshAll")
        expect(claude.fetchCount == 1, "refresh enabled")
        await store.refresh(.grok)
        expect(grok.fetchCount == 0, "skip disabled refresh")
        store.setEnabled(true, id: .grok)
        await store.refresh(.grok)
        expect(grok.fetchCount == 1, "refresh after re-enable")
    }

    do {
        let store = UsageStore(
            fetchers: [:],
            cache: MemorySnapshotCache(),
            enabledCache: MemoryEnabledProviderCache(storage: []),
            startTimer: false,
            refreshOnLaunch: false
        )
        expect(store.enabled == Set(ProviderID.allCases), "empty stored defaults all")
    }

    return failures
}

@MainActor
final class FakeFetcher: UsageFetching {
    var pages: [PageSnapshot]
    var signOutCount = 0
    var fetchCount = 0
    var lastAllowNavigation: Bool?
    var delayNanoseconds: UInt64 = 0

    init(pages: [PageSnapshot]) {
        self.pages = pages
    }

    func fetchSnapshot(allowNavigation: Bool) async -> PageSnapshot {
        fetchCount += 1
        lastAllowNavigation = allowNavigation
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if pages.isEmpty { return .empty }
        return pages.removeFirst()
    }

    func signOut() async {
        signOutCount += 1
    }
}
