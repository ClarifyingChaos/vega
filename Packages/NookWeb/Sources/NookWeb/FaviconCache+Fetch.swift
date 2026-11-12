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
        guard url.scheme == "http" || url.scheme == "https", let key = Self.key(for: url) else { return nil }
        let cached = await cachedImage(for: key)
        if cached != nil, !(await isStale(key)) { return cached }
        guard await FaviconFetches.shared.begin(key) else { return cached }
        defer { Task { await FaviconFetches.shared.end(key) } }
        guard let fresh = await Self.bestIcon(for: url) else { return cached }
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
    /// False when another call is already fetching `key`.
    func begin(_ key: String) -> Bool { inFlight.insert(key).inserted }
    func end(_ key: String) { inFlight.remove(key) }
}

#endif
