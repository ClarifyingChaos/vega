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
    static let maxStoredEdge: CGFloat = 256

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

    /// The largest roughly square icon among the page's `<link>` tags and its web manifest.
    static func bestIcon(for url: URL) async -> PlatformImage? {
        var candidates: [FaviconURL] = []
        for source in [FaviconSourceType.html, .webApplicationManifestFile] {
            let finder = FaviconFinder(url: url, configuration: .init(preferredSource: source))
            candidates += (try? await finder.fetchFaviconURLs()) ?? []
        }
        // Declared size first; icons with no size attribute come last but still get a chance.
        var seen = Set<URL>()
        let ordered = candidates
            .filter { seen.insert($0.source).inserted }
            .sorted { ($0.size?.dimension ?? 0) > ($1.size?.dimension ?? 0) }
            .prefix(4)
        var best: (image: PlatformImage, edge: CGFloat)?
        for candidate in ordered {
            guard let image = try? await candidate.download().image?.image else { continue }
            let (w, h) = image.pixelSize
            // A banner or a sliver is not an app icon.
            guard w > 0, h > 0, max(w, h) / min(w, h) <= 1.25 else { continue }
            if best == nil || max(w, h) > best!.edge { best = (image, max(w, h)) }
        }
        return best.map { $0.image.downscaled(toEdge: maxStoredEdge) }
    }
}

private actor FaviconFetches {
    static let shared = FaviconFetches()
    private var inFlight = Set<String>()
    /// False when another call is already fetching `key`.
    func begin(_ key: String) -> Bool { inFlight.insert(key).inserted }
    func end(_ key: String) { inFlight.remove(key) }
}

extension NSImage {
    /// Size of the largest bitmap representation, in pixels; `size` is in points and understates retina art.
    var pixelSize: (CGFloat, CGFloat) {
        let reps = representations
        let w = reps.map { CGFloat($0.pixelsWide) }.max() ?? 0
        let h = reps.map { CGFloat($0.pixelsHigh) }.max() ?? 0
        return (w > 0 ? w : size.width, h > 0 ? h : size.height)
    }

    /// A copy no larger than `edge` pixels on the long side; the image itself when already smaller.
    func downscaled(toEdge edge: CGFloat) -> NSImage {
        let (w, h) = pixelSize
        guard max(w, h) > edge, w > 0, h > 0 else { return self }
        let scale = edge / max(w, h)
        let target = NSSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return self }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: target)
        out.addRepresentation(rep)
        return out
    }
}
#endif
