import Foundation

public protocol SnapshotCache: AnyObject {
    func load() -> [ProviderID: UsageSnapshot]
    func save(_ snapshot: UsageSnapshot)
    func remove(_ id: ProviderID)
}

public final class UserDefaultsSnapshotCache: SnapshotCache {
    public static let keyPrefix = "scrip.snapshot."

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [ProviderID: UsageSnapshot] {
        var loaded: [ProviderID: UsageSnapshot] = [:]
        for id in ProviderID.allCases {
            guard let data = defaults.data(forKey: Self.keyPrefix + id.rawValue),
                  let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
            else { continue }
            loaded[id] = snapshot
        }
        return loaded
    }

    public func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.keyPrefix + snapshot.provider.rawValue)
    }

    public func remove(_ id: ProviderID) {
        defaults.removeObject(forKey: Self.keyPrefix + id.rawValue)
    }
}

public final class MemorySnapshotCache: SnapshotCache {
    public var storage: [ProviderID: UsageSnapshot] = [:]

    public init(storage: [ProviderID: UsageSnapshot] = [:]) {
        self.storage = storage
    }

    public func load() -> [ProviderID: UsageSnapshot] { storage }

    public func save(_ snapshot: UsageSnapshot) {
        storage[snapshot.provider] = snapshot
    }

    public func remove(_ id: ProviderID) {
        storage.removeValue(forKey: id)
    }
}

public protocol EnabledProviderCache: AnyObject {
    func load() -> Set<ProviderID>?
    func save(_ enabled: Set<ProviderID>)
}

public final class UserDefaultsEnabledProviderCache: EnabledProviderCache {
    public static let key = "scrip.enabledProviders"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Set<ProviderID>? {
        guard let raw = defaults.array(forKey: Self.key) as? [String] else { return nil }
        let parsed = Set(raw.compactMap(ProviderID.init(rawValue:)))
        return parsed
    }

    public func save(_ enabled: Set<ProviderID>) {
        defaults.set(ProviderID.allCases.filter { enabled.contains($0) }.map(\.rawValue), forKey: Self.key)
    }
}

public final class MemoryEnabledProviderCache: EnabledProviderCache {
    public var storage: Set<ProviderID>?

    public init(storage: Set<ProviderID>? = nil) {
        self.storage = storage
    }

    public func load() -> Set<ProviderID>? { storage }

    public func save(_ enabled: Set<ProviderID>) {
        storage = enabled
    }
}
