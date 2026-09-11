import Combine
import Foundation

@MainActor
public final class UsageStore: ObservableObject {
    @Published public var snapshots: [ProviderID: UsageSnapshot]
    @Published public var refreshing: Set<ProviderID> = []
    @Published public var loginOpen: Set<ProviderID> = []
    @Published public var enabled: Set<ProviderID>

    private let fetchers: [ProviderID: any UsageFetching]
    private let cache: SnapshotCache
    private let enabledCache: any EnabledProviderCache
    private var timerTask: Task<Void, Never>?
    private var inFlight: [ProviderID: Task<Void, Never>] = [:]

    public var orderedEnabled: [ProviderID] {
        ProviderID.allCases.filter { enabled.contains($0) }
    }

    public init(
        fetchers: [ProviderID: any UsageFetching],
        cache: SnapshotCache = UserDefaultsSnapshotCache(),
        enabledCache: any EnabledProviderCache = UserDefaultsEnabledProviderCache(),
        startTimer: Bool = true,
        refreshOnLaunch: Bool = true
    ) {
        self.fetchers = fetchers
        self.cache = cache
        self.enabledCache = enabledCache
        var snapshots: [ProviderID: UsageSnapshot] = [:]
        for id in ProviderID.allCases {
            snapshots[id] = UsageSnapshot.empty(id)
        }
        let loaded = cache.load()
        for (id, snapshot) in loaded {
            snapshots[id] = snapshot
        }
        self.snapshots = snapshots
        let stored = enabledCache.load()
        if let stored, !stored.isEmpty {
            self.enabled = stored
        } else {
            self.enabled = Set(ProviderID.allCases)
        }
        if startTimer {
            self.startTimer()
        }
        if refreshOnLaunch {
            Task { await self.refreshAll() }
        }
    }

    public func fetcher(for id: ProviderID) -> (any UsageFetching)? {
        fetchers[id]
    }

    public func setEnabled(_ on: Bool, id: ProviderID) {
        if on {
            enabled.insert(id)
        } else if enabled.count > 1 {
            enabled.remove(id)
        } else {
            return
        }
        enabledCache.save(enabled)
    }

    public func refreshAll() async {
        for id in orderedEnabled {
            await refresh(id)
        }
    }

    public func refresh(_ id: ProviderID) async {
        guard enabled.contains(id) else { return }
        if let existing = inFlight[id] {
            await existing.value
            return
        }
        let task = Task { @MainActor in
            await self.performRefresh(id)
        }
        inFlight[id] = task
        await task.value
        inFlight[id] = nil
    }

    public func signOut(_ id: ProviderID) async {
        await fetchers[id]?.signOut()
        snapshots[id] = UsageSnapshot.empty(id)
        cache.remove(id)
    }

    private func performRefresh(_ id: ProviderID) async {
        guard let fetcher = fetchers[id] else { return }
        refreshing.insert(id)
        defer { refreshing.remove(id) }
        let allowNavigation = !loginOpen.contains(id)
        let page = await fetcher.fetchSnapshot(allowNavigation: allowNavigation)
        var snapshot = UsageParser.snapshot(provider: id, page: page)
        snapshot.updatedAt = Date()
        apply(snapshot, page: page, id: id)
    }

    private func apply(_ incoming: UsageSnapshot, page: PageSnapshot, id: ProviderID) {
        let current = snapshots[id]
        if let current, current.auth == .signedIn, shouldKeep(current, incoming: incoming, page: page) {
            var kept = current
            if incoming.auth == .signedOut {
                kept.auth = .needsReauth
            }
            kept.error = incoming.error ?? page.error?.rawValue
            snapshots[id] = kept
            return
        }
        snapshots[id] = incoming
        if incoming.auth == .signedOut || incoming.auth == .blocked {
            cache.remove(id)
        } else {
            cache.save(incoming)
        }
    }

    private func shouldKeep(_ current: UsageSnapshot, incoming: UsageSnapshot, page: PageSnapshot) -> Bool {
        if page.error == .jsThrew || page.error == .emptyDocument || page.error == .timeout {
            return true
        }
        if incoming.auth == .signedOut, page.text.isEmpty, page.lines.isEmpty {
            return true
        }
        if incoming.auth == .signedOut, page.error != nil {
            return true
        }
        if incoming.auth == .signedIn, incoming.metrics.isEmpty, !current.metrics.isEmpty {
            return true
        }
        if incoming.auth == .signedIn, incoming.metrics.isEmpty, incoming.rawLines.isEmpty {
            return true
        }
        _ = current
        return false
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    break
                }
                await self?.refreshAll()
            }
        }
    }

    deinit {
        timerTask?.cancel()
    }
}
