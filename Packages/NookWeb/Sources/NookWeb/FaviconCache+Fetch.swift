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
    /// Icons at least this many pixels wide stay sharp at tile size on a 2x display.
    static let sharpEdge: CGFloat = 64
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

/// Orders candidate icons like Chromium does: the site's own favicon beats an apple-touch icon even
/// when smaller, since a touch icon is an opaque padded square (Cosmos's round mark becomes a white
/// tile). Among the same kind, one sharp at tile size beats a blurry one; among the sharp, the
/// smallest, since it is shrunk the least; among the blurry, the largest.
struct IconRank: Comparable {
    let usable: Bool
    private let key: (Int, Int, CGFloat)

    init(_ image: NSImage, touchIcon: Bool) {
        let (w, h) = image.pixelSize
        // A banner or a sliver is not an app icon.
        usable = w > 0 && h > 0 && max(w, h) / min(w, h) <= 1.25
        let edge = max(w, h)
        let sharp = edge >= FaviconCache.sharpEdge
        key = (touchIcon ? 0 : 1, sharp ? 1 : 0, sharp ? -edge : edge)
    }

    static func < (a: IconRank, b: IconRank) -> Bool { a.key < b.key }
    static func == (a: IconRank, b: IconRank) -> Bool { a.key == b.key }
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

    /// True when no pixel is visibly opaque: an SVG rendered with no size, or a failed decode.
    var isBlank: Bool {
        guard let src = cgImage(forProposedRect: nil, context: nil, hints: nil), src.width > 0, src.height > 0,
              let ctx = CGContext(data: nil, width: src.width, height: src.height, bitsPerComponent: 8, bytesPerRow: src.width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return true }
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: src.width, height: src.height))
        let px = data.assumingMemoryBound(to: UInt8.self)
        return !(0..<(src.width * src.height)).contains { px[$0 * 4 + 3] > 16 }
    }

    /// A square copy with the transparent margin cropped off, so every icon's artwork fills the same
    /// box at tile size. Apple-touch icons and many favicons leave 15 to 30% empty around the mark,
    /// which made one site's logo look half the size of the next. Opaque icons come back unchanged.
    public func trimmedToContent() -> NSImage {
        guard let src = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return self }
        let w = src.width, h = src.height
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: info),
              let data = ctx.data else { return self }
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.assumingMemoryBound(to: UInt8.self)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where px[(y * w + x) * 4 + 3] > 16 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX else { return self }
        let boxW = maxX - minX + 1, boxH = maxY - minY + 1
        // Already fills the frame: leave it alone.
        guard boxW * 100 < w * 92 || boxH * 100 < h * 92 else { return self }
        let side = max(boxW, boxH)
        guard let cropped = src.cropping(to: CGRect(x: minX, y: minY, width: boxW, height: boxH)),
              let out = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info) else { return self }
        out.interpolationQuality = .high
        out.draw(cropped, in: CGRect(x: (side - boxW) / 2, y: (side - boxH) / 2, width: boxW, height: boxH))
        guard let image = out.makeImage() else { return self }
        return NSImage(cgImage: image, size: NSSize(width: side, height: side))
    }

    /// A copy resampled to exactly `pixels` device pixels on the long side, `scale` pixels per point,
    /// so the view draws it 1:1. Shrinking a large icon in the view, in one step, aliases at 1x.
    public func resampled(pixels: Int, scale: CGFloat) -> NSImage {
        let (w, h) = pixelSize
        guard pixels > 0, w > 0, h > 0, let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int((w >= h ? CGFloat(pixels) : CGFloat(pixels) * w / h).rounded()),
            pixelsHigh: Int((h >= w ? CGFloat(pixels) : CGFloat(pixels) * h / w).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return self }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: NSSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale))
        out.addRepresentation(rep)
        return out
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
