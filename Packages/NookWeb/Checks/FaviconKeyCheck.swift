// Licensed under GPL-3.0. See LICENSE.
//
//  FaviconKeyCheck.swift
//  Nook
//
//  Favicon cache key check. Compiles the shipped source directly:
//
//    swiftc Packages/NookWeb/Sources/NookWeb/FaviconCache.swift \
//           Packages/NookWeb/Checks/FaviconKeyShim.swift \
//           Packages/NookWeb/Checks/FaviconKeyCheck.swift -o /tmp/favicon-key-check && /tmp/favicon-key-check
//

import AppKit
import Foundation

@main
struct FaviconKeyCheck {
    static func key(_ s: String) -> String? { FaviconCache.key(for: URL(string: s)!) }

    static func main() {
        precondition(key("http://h") == "h")
        precondition(key("http://h:80") == "h")
        precondition(key("https://h:443") == "h")
        precondition(key("https://h") == "h")
        precondition(key("http://h:8080") == "h_8080")
        precondition(key("https://h:8443") == "h_8443")
        precondition(key("http://h:443") == "h_443")
        precondition(key("http://[::1]:8080") == "::1_8080")
        precondition(key("mailto:a@b") == nil)

        for k in ["::1_8080", "a/b", "h_8080", "x.y-z"] {
            let name = FaviconCache.shared.fileName(k)
            precondition(name.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil, name)
        }
        precondition(FaviconCache.shared.fileName("::1_8080") == "__1_8080.png")
        precondition(FaviconCache.shared.fileName("example.com") == "example.com.png")
        // Background fetches go to public https hosts only.
        func pub(_ s: String) -> Bool { FaviconCache.isPublicHTTPS(URL(string: s)!) }
        precondition(pub("https://example.com/x"))
        precondition(!pub("http://example.com"), "plain http")
        precondition(!pub("https://localhost:3000"))
        precondition(!pub("https://192.168.1.1"), "IP address")
        precondition(!pub("https://[::1]"), "IPv6")
        precondition(!pub("https://printer.local"))
        precondition(!pub("https://intranet"), "no dot")

        // Reading counts as use: a read key outlives the keys stored after it.
        let cache = FaviconCache.shared
        let icon = NSImage(size: NSSize(width: 4, height: 4))
        cache.store(icon, for: "keep.example", toDisk: false)
        for i in 0..<(FaviconCache.maxMemoryEntries - 1) { cache.store(icon, for: "fill\(i).example", toDisk: false) }
        _ = cache.image(for: "keep.example")                        // used, so now the newest
        for i in 0..<30 { cache.store(icon, for: "later\(i).example", toDisk: false) }
        precondition(cache.image(for: "keep.example") != nil, "a read entry is kept")
        precondition(cache.image(for: "fill0.example") == nil, "the least recently used goes first")
        print("FaviconKeyCheck ok")
    }
}
