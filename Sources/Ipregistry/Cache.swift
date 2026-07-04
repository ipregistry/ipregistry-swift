// Copyright 2019 Ipregistry (https://ipregistry.co).
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

/// The storage used by an ``IpregistryClient`` to memoize IP lookups.
///
/// Only successful single and batch IP lookups are cached. Origin lookups are
/// never cached, because the requester IP is only known from the response.
/// Keys are derived from the IP address and the lookup options; see
/// ``IpregistryClient/cacheKey(ip:options:)``.
///
/// The built-in implementation is ``InMemoryCache``. Conform your own type to
/// back the client with a different store.
public protocol IpregistryCache: Sendable {
    /// Returns the cached value for `key`, or `nil` when absent.
    func get(_ key: String) async -> IPInfo?

    /// Stores `value` under `key`.
    func set(_ key: String, _ value: IPInfo) async

    /// Removes the entry for `key`, if present.
    func invalidate(_ key: String) async

    /// Removes every entry.
    func invalidateAll() async
}

/// A thread-safe, in-process ``IpregistryCache`` with time-based expiration
/// and a bounded size using least-recently-used eviction.
///
/// ```swift
/// let client = IpregistryClient(
///     apiKey: "YOUR_API_KEY",
///     cache: InMemoryCache(maxSize: 8192, timeToLive: 600)
/// )
/// ```
public actor InMemoryCache: IpregistryCache {
    /// A node of the LRU list. `previous` is weak so the doubly linked list
    /// does not form retain cycles.
    private final class Node {
        let key: String
        var value: IPInfo
        var expiresAt: Date
        weak var previous: Node?
        var next: Node?

        init(key: String, value: IPInfo, expiresAt: Date) {
            self.key = key
            self.value = value
            self.expiresAt = expiresAt
        }
    }

    private let maxSize: Int
    private let timeToLive: TimeInterval
    private let now: @Sendable () -> Date

    private var nodes: [String: Node] = [:]
    /// Most recently used.
    private var head: Node?
    /// Least recently used.
    private var tail: Node?

    /// Creates a cache.
    ///
    /// - Parameters:
    ///   - maxSize: The maximum number of entries held before the least
    ///     recently used entry is evicted. Values below 1 fall back to the
    ///     default of 4096.
    ///   - timeToLive: How long an entry stays valid after being written, in
    ///     seconds. Values of 0 or below fall back to the default of 10
    ///     minutes.
    public init(maxSize: Int = 4096, timeToLive: TimeInterval = 600) {
        self.init(maxSize: maxSize, timeToLive: timeToLive, now: { Date() })
    }

    /// Internal initializer allowing tests to inject a deterministic clock.
    init(maxSize: Int, timeToLive: TimeInterval, now: @escaping @Sendable () -> Date) {
        self.maxSize = maxSize > 0 ? maxSize : 4096
        self.timeToLive = timeToLive > 0 ? timeToLive : 600
        self.now = now
    }

    /// The current number of entries, including entries that have expired but
    /// have not been touched since. Primarily useful in tests.
    public var count: Int {
        nodes.count
    }

    public func get(_ key: String) -> IPInfo? {
        guard let node = nodes[key] else {
            return nil
        }
        if now() > node.expiresAt {
            remove(node)
            return nil
        }
        moveToFront(node)
        return node.value
    }

    public func set(_ key: String, _ value: IPInfo) {
        let expiresAt = now().addingTimeInterval(timeToLive)
        if let node = nodes[key] {
            node.value = value
            node.expiresAt = expiresAt
            moveToFront(node)
            return
        }

        let node = Node(key: key, value: value, expiresAt: expiresAt)
        nodes[key] = node
        insertAtFront(node)

        if nodes.count > maxSize, let oldest = tail {
            remove(oldest)
        }
    }

    public func invalidate(_ key: String) {
        if let node = nodes[key] {
            remove(node)
        }
    }

    public func invalidateAll() {
        // Break the next-chain iteratively so deallocation does not recurse
        // through thousands of nodes.
        var node = head
        while let current = node {
            node = current.next
            current.next = nil
        }
        head = nil
        tail = nil
        nodes.removeAll()
    }

    private func insertAtFront(_ node: Node) {
        node.next = head
        node.previous = nil
        head?.previous = node
        head = node
        if tail == nil {
            tail = node
        }
    }

    private func moveToFront(_ node: Node) {
        guard head !== node else {
            return
        }
        unlink(node)
        insertAtFront(node)
    }

    private func remove(_ node: Node) {
        unlink(node)
        nodes[node.key] = nil
    }

    private func unlink(_ node: Node) {
        node.previous?.next = node.next
        node.next?.previous = node.previous
        if head === node {
            head = node.next
        }
        if tail === node {
            tail = node.previous
        }
        node.next = nil
        node.previous = nil
    }
}
