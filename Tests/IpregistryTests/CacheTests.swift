import Foundation
import Testing

@testable import Ipregistry

@Suite("In-memory cache")
struct CacheTests {
    private func info(_ ip: String) -> IPInfo {
        IPInfo(ip: ip)
    }

    @Test func storesAndReturnsValues() async {
        let cache = InMemoryCache()

        await cache.set("a", info("1.1.1.1"))

        #expect(await cache.get("a")?.ip == "1.1.1.1")
        #expect(await cache.get("missing") == nil)
    }

    @Test func evictsLeastRecentlyUsedEntryWhenFull() async {
        let cache = InMemoryCache(maxSize: 2)

        await cache.set("a", info("1.1.1.1"))
        await cache.set("b", info("2.2.2.2"))
        // Touch "a" so "b" becomes the least recently used entry.
        _ = await cache.get("a")
        await cache.set("c", info("3.3.3.3"))

        #expect(await cache.get("a") != nil)
        #expect(await cache.get("b") == nil)
        #expect(await cache.get("c") != nil)
        #expect(await cache.count == 2)
    }

    @Test func expiresEntriesAfterTimeToLive() async {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 0))
        let cache = InMemoryCache(maxSize: 16, timeToLive: 60, now: { clock.now })

        await cache.set("a", info("1.1.1.1"))
        clock.now = Date(timeIntervalSince1970: 59)
        #expect(await cache.get("a") != nil)

        clock.now = Date(timeIntervalSince1970: 61)
        #expect(await cache.get("a") == nil)
        #expect(await cache.count == 0)
    }

    @Test func settingAnExistingKeyRefreshesValueAndExpiration() async {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 0))
        let cache = InMemoryCache(maxSize: 16, timeToLive: 60, now: { clock.now })

        await cache.set("a", info("1.1.1.1"))
        clock.now = Date(timeIntervalSince1970: 50)
        await cache.set("a", info("9.9.9.9"))

        clock.now = Date(timeIntervalSince1970: 100)
        #expect(await cache.get("a")?.ip == "9.9.9.9")
        #expect(await cache.count == 1)
    }

    @Test func invalidateRemovesSingleEntry() async {
        let cache = InMemoryCache()

        await cache.set("a", info("1.1.1.1"))
        await cache.set("b", info("2.2.2.2"))
        await cache.invalidate("a")

        #expect(await cache.get("a") == nil)
        #expect(await cache.get("b") != nil)
        #expect(await cache.count == 1)
    }

    @Test func invalidateAllRemovesEveryEntry() async {
        let cache = InMemoryCache()

        for index in 0..<100 {
            await cache.set("key-\(index)", info("10.0.0.\(index)"))
        }
        await cache.invalidateAll()

        #expect(await cache.count == 0)
        #expect(await cache.get("key-0") == nil)

        // The cache remains usable after a full invalidation.
        await cache.set("a", info("1.1.1.1"))
        #expect(await cache.get("a") != nil)
    }

    @Test func outOfRangeParametersFallBackToDefaults() async {
        let cache = InMemoryCache(maxSize: 0, timeToLive: -5)

        await cache.set("a", info("1.1.1.1"))
        #expect(await cache.get("a") != nil)
    }
}

/// A deterministic, manually advanced clock.
private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(now: Date) {
        _now = now
    }

    var now: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _now
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _now = newValue
        }
    }
}
