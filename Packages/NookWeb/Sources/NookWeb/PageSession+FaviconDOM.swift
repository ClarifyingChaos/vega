// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+FaviconDOM.swift
//  NookWeb
//
//  Icon discovery from the loaded page's own <link> tags. Sites that answer a script's request
//  with 403 (Behance, Crunchyroll and others) still show the page, and its icon links, to the
//  web view, and the icon files themselves are rarely blocked.
//

#if os(macOS)
import Foundation
import WebKit
import SwiftUI

extension PageSession {
    private static let iconLinksScript = """
    Array.from(document.querySelectorAll('link[rel~="icon"],link[rel^="apple-touch-icon"]'))
      .map(l => ({href: l.href, rel: l.rel, sizes: l.sizes ? l.sizes.value : '', type: l.type || ''}))
    """

    /// Stores and shows the best icon the loaded page declares. False when the page has none
    /// we can use (not loaded yet, only SVG, download blocked).
    @MainActor
    func fetchFaviconFromDOM(for pageURL: URL) async -> Bool {
        guard let webView = primaryWebView,
              let raw = try? await webView.evaluateJavaScript(Self.iconLinksScript) as? [[String: String]] else { return false }
        var seen = Set<URL>()
        let links: [(url: URL, edge: Int, touch: Bool)] = raw.compactMap { entry in
            guard let href = entry["href"], let url = URL(string: href),
                  url.scheme == "https" || url.scheme == "http",
                  !href.lowercased().contains(".svg"), entry["type"] != "image/svg+xml",
                  seen.insert(url).inserted else { return nil }
            // "180x180" or "16x16 32x32": the biggest declared edge; undeclared sorts last.
            let edge = (entry["sizes"] ?? "").split(separator: " ")
                .compactMap { Int($0.split(separator: "x").first ?? "") }.max() ?? 0
            return (url, edge, (entry["rel"] ?? "").hasPrefix("apple-touch-icon"))
        }
        var best: (image: PlatformImage, rank: IconRank)?
        for link in links.sorted(by: { $0.edge > $1.edge }).prefix(4) {
            guard let image = await Self.downloadImage(from: link.url, isPrivate: isPrivate) else { continue }
            let rank = IconRank(image, touchIcon: link.touch)
            if rank.usable, !image.isBlank, best == nil || rank > best!.rank { best = (image, rank) }
        }
        guard let icon = best?.image.trimmedToContent().downscaled(toEdge: FaviconCache.maxStoredEdge),
              let key = FaviconCache.key(for: pageURL) else { return false }
        // A private page's host must not reach ~/Library/Caches/FaviconCache.
        FaviconCache.shared.store(icon, for: key, toDisk: !isPrivate)
        favicon = SwiftUI.Image(platformImage: FaviconCache.shared.image(for: key) ?? icon)
        hasFavicon = true
        return true
    }
}
#endif
