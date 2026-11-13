// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+Reader.swift
//  NookWeb
//
//  FORK: reader view. Mozilla's Readability (Apache 2.0, in Resources/page-reader.js) pulls the article out
//  of a copy of the page, and the script lays it over the page in a closed shadow root. The page itself is
//  untouched, so Back, Forward and reload behave as they do for any page. The script and its handler live in
//  the NookReader world, so the page can neither read nor drive them.
//

import Foundation
import WebKit

extension PageSession {
    static let readerWorld = WKContentWorld.world(name: "NookReader")
    static let readerHandlerName = "nookReader"

    private static let readerScript: String = {
        guard let url = Bundle.module.url(forResource: "page-reader", withExtension: "js", subdirectory: "Resources"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return source
    }()

    /// An ordinary web page that is not a PDF.
    public var canShowReader: Bool {
        guard !isDisplayingPDF, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// The one entry point for menus and the address bar.
    public func toggleReader() {
        Task { _ = await callReaderScript(isReaderActive ? "hide()" : "show()") }
    }

    /// Runs `call` in the main frame's NookReader world, installing the script on first use.
    /// Returns the script's answer, or nil when it could not run.
    private func callReaderScript(_ call: String) async -> [String: Any]? {
        guard canShowReader, let webView = primaryWebView, !Self.readerScript.isEmpty else { return nil }
        let body = Self.readerScript + "\nreturn window.__nookReader.\(call);"
        do {
            let result = try await webView.callAsyncJavaScript(body, arguments: [:], in: nil, contentWorld: Self.readerWorld) as? [String: Any]
            // A page with no article in it: say so with the page's own title bar, not a dialog.
            if call.hasPrefix("show"), result?["ok"] as? Bool == false { isReaderActive = false }
            return result
        } catch {
            return nil
        }
    }
}
