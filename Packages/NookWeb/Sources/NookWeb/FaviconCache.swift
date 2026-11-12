// Licensed under GPL-3.0. See LICENSE.
//
//  FaviconCache.swift
//  Nook
//
//  Global favicon cache, shared across profiles by design to raise the hit rate and avoid
//  duplicate downloads. Memory LRU of 200 entries plus a disk cache at
//  ~/Library/Caches/FaviconCache/{key}.png that survives relaunch. Disk I/O runs on a
//  background queue.
//

import Foundation
import SwiftUI

public final class FaviconCache: @unchecked Sendable {
    public static let shared = FaviconCache()

    public static let maxMemoryEntries = 200

    private struct Entry {
        let nsImage: PlatformImage
        let image: SwiftUI.Image
    }

    private var memory: [String: Entry] = [:]
    /// Insertion order for LRU eviction.
    private var order: [String] = []
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "favicon.cache", attributes: .concurrent)

    public let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("FaviconCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    /// Cache key for a page: the host, plus `_port` when the port is not the scheme's default.
    public static func key(for url: URL) -> String? {
        guard let host = url.host else { return nil }
        guard let port = url.port, port != (url.scheme == "https" ? 443 : 80) else { return host }
        return "\(host)_\(port)"
    }

    /// https, with a dotted host name that is not an IP address, `localhost` or `.local`.
    static func isPublicHTTPS(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), host.contains("."),
              !host.hasSuffix(".local"), !host.contains(":"),
              host.contains(where: { $0.isLetter }) else { return false }
        return true
    }

    // MARK: - Lookup

    /// Memory cache only, synchronous. A read counts as use, so the entries evicted first are the
    /// ones nobody looks at, not the ones stored first (favorites are stored first).
    public func image(for key: String) -> PlatformImage? {
        lock.withLock { touch(key)?.nsImage }
    }

    /// Memory cache only, as a SwiftUI image.
    public func swiftUIImage(for key: String) -> SwiftUI.Image? {
        lock.withLock { touch(key)?.image }
    }

    /// Caller holds `lock`.
    private func touch(_ key: String) -> Entry? {
        guard let entry = memory[key] else { return nil }
        if let index = order.lastIndex(of: key), index != order.count - 1 {
            order.remove(at: index)
            order.append(key)
        }
        return entry
    }

    /// Memory first, then disk off the main thread. A disk hit is promoted to memory.
    public func cachedImage(for key: String) async -> PlatformImage? {
        if let hit = image(for: key) { return hit }
        return await withCheckedContinuation { continuation in
            queue.async {
                let image = self.readFromDisk(key)
                if let image { self.insert(Entry(nsImage: image, image: SwiftUI.Image(platformImage: image)), for: key) }
                continuation.resume(returning: image)
            }
        }
    }

    /// Synchronous disk read with promotion to memory. For startup restore of a few visible rows.
    public func imageFromDiskSync(for key: String) -> PlatformImage? {
        guard let image = readFromDisk(key) else { return nil }
        insert(Entry(nsImage: image, image: SwiftUI.Image(platformImage: image)), for: key)
        return image
    }

    /// How long a stored favicon is trusted before a visit fetches it again.
    public static let maxAge: TimeInterval = 24 * 60 * 60

    /// True when the disk copy is older than `maxAge`. Memory-only entries (private pages) are never stale.
    public func isStale(_ key: String) async -> Bool {
        let url = fileURL(key)
        return await withCheckedContinuation { continuation in
            queue.async {
                let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
                continuation.resume(returning: modified.map { -$0.timeIntervalSinceNow > Self.maxAge } ?? false)
            }
        }
    }

    // MARK: - Store

    /// Stores in memory and writes a PNG to disk.
    public func store(_ image: PlatformImage, for key: String) {
        store(image, for: key, toDisk: true)
    }

    func store(_ image: PlatformImage, for key: String, toDisk: Bool) {
        insert(Entry(nsImage: image, image: SwiftUI.Image(platformImage: image)), for: key)
        guard toDisk else { return }
        // PNG encoding is CPU work, not I/O; do it on the caller.
        guard let png = image.pngData() else { return }
        let url = fileURL(key)
        queue.async(flags: .barrier) {
            // Atomic, so a crash mid-write cannot leave a cut-off PNG.
            try? png.write(to: url, options: .atomic)
            self.storesSinceTrim += 1
            if self.storesSinceTrim >= 50 { self.storesSinceTrim = 0; self.trimDisk() }
        }
    }

    // MARK: - Maintenance

    public func clear() {
        lock.withLock {
            memory.removeAll()
            order.removeAll()
        }
        let dir = directory
        queue.async(flags: .barrier) {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Entry counts in memory and on disk.
    public func stats() -> (memory: Int, disk: Int) {
        let memoryCount = lock.withLock { memory.count }
        let diskCount = (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
        return (memoryCount, diskCount)
    }

    /// Keys currently in memory.
    public var memoryKeys: [String] {
        lock.withLock { Array(memory.keys) }
    }

    // MARK: - Private

    /// How many icons the disk keeps. Memory holds fewer; leaving memory no longer deletes a file.
    public static let maxDiskEntries = 1000
    private var storesSinceTrim = 0

    /// Deletes the oldest-written files beyond the cap. Runs on `queue` with the barrier.
    private func trimDisk() {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys),
              files.count > Self.maxDiskEntries else { return }
        func written(_ url: URL) -> Date { (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? .distantPast }
        for url in files.sorted(by: { written($0) < written($1) }).prefix(files.count - Self.maxDiskEntries + 50) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func insert(_ entry: Entry, for key: String) {
        lock.withLock {
            memory[key] = entry
            order.removeAll { $0 == key }
            order.append(key)
            if memory.count > Self.maxMemoryEntries {
                let count = memory.count - Self.maxMemoryEntries + 20
                for old in order.prefix(count) { memory.removeValue(forKey: old) }
                order.removeFirst(min(count, order.count))
            }
        }
    }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent(fileName(key))
    }

    /// Only [A-Za-z0-9._-] survive; the rest (IPv6 colons, slashes) become `_`.
    func fileName(_ key: String) -> String {
        let safe = key.unicodeScalars.map { c -> Character in
            let ok = c.isASCII && (c.properties.isAlphabetic || ("0"..."9").contains(c) || "._-".unicodeScalars.contains(c))
            return ok ? Character(c) : "_"
        }
        return String(safe) + ".png"
    }

    private func readFromDisk(_ key: String) -> PlatformImage? {
        guard let data = try? Data(contentsOf: fileURL(key)) else { return nil }
        return PlatformImage(data: data)
    }
}
