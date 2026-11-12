// Licensed under GPL-3.0. See LICENSE.
//
//  FaviconCache+Fetch.swift
//  NookWeb
//
//  Fetching icons for items with no live page (unloaded favorites and pinned tabs), and
//  choosing the sharpest icon a site offers instead of the first one FaviconFinder returns.
//

#if os(macOS)
import Foundation
import FaviconFinder
import AppKit

extension FaviconCache {
    /// Stored icons are scaled down to this many pixels on the long edge: sharp at tile size on
    /// a 2x display, and 200 of them stay small in memory.
    static let maxStoredEdge: CGFloat = 128

    /// The cached icon for `url`'s host, fetched and stored when missing or older than `maxAge`.
    /// Nil when the site offers none. Concurrent calls for one host share one request.
    public func loadOrFetch(for url: URL) async -> PlatformImage? {
        guard let key = Self.key(for: url) else { return nil }
        let cached = await cachedImage(for: key)
        if cached != nil, !(await isStale(key)) { return cached }
        // A background fetch for a row nobody opened: public https hosts only, so launching never
        // contacts a router page or a dev server, and a site with no icon is not retried for a day.
        guard Self.isPublicHTTPS(url), await FaviconFetches.shared.begin(key) else { return cached }
        defer { Task { await FaviconFetches.shared.end(key) } }
        guard let fresh = await Self.bestIcon(for: url) else {
            await FaviconFetches.shared.markFailed(key)
            return cached
        }
        store(fresh, for: key)
        return image(for: key) ?? fresh
    }

    /// The best roughly square icon among the page's `<link>` tags, its web manifest and /favicon.ico.
    static func bestIcon(for url: URL) async -> PlatformImage? {
        var candidates: [FaviconURL] = []
        for source in [FaviconSourceType.html, .webApplicationManifestFile, .ico] {
            let finder = FaviconFinder(url: url, configuration: .init(preferredSource: source))
            candidates += (try? await finder.fetchFaviconURLs()) ?? []
        }
        // Declared size first; icons with no size attribute come last but still get a chance.
        var seen = Set<URL>()
        let ordered = candidates
            .filter { !$0.source.path.lowercased().hasSuffix(".svg") && seen.insert($0.source).inserted }
            .sorted { ($0.size?.dimension ?? 0) > ($1.size?.dimension ?? 0) }
            .prefix(4)
        var best: (image: PlatformImage, rank: IconRank)?
        for candidate in ordered {
            guard let image = try? await candidate.download().image?.image else { continue }
            let rank = IconRank(image, touchIcon: candidate.format == .appleTouchIcon || candidate.format == .appleTouchIconPrecomposed)
            if rank.usable, !image.isBlank, best == nil || rank > best!.rank { best = (image, rank) }
        }
        return best.map { $0.image.trimmedToContent().downscaled(toEdge: maxStoredEdge) }
    }
}

private actor FaviconFetches {
    static let shared = FaviconFetches()
    private var inFlight = Set<String>()
    private var failedUntil: [String: Date] = [:]
    /// False when another call is already fetching `key`, or a fetch for it failed in the last day.
    func begin(_ key: String) -> Bool {
        if let until = failedUntil[key], until > Date() { return false }
        return inFlight.insert(key).inserted
    }
    func end(_ key: String) { inFlight.remove(key) }
    func markFailed(_ key: String) { failedUntil[key] = Date().addingTimeInterval(24 * 60 * 60) }
}

#endif
