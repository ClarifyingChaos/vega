// Licensed under GPL-3.0. See LICENSE.
//
//  SitePreferences.swift
//  NookSettings
//
//  FORK: per-site settings kept by host: JavaScript, mobile site, automatic Picture-in-Picture.
//  A missing value means "use the app's default", so a site only stores what was changed.
//

import Foundation
import Observation
import OSLog

public struct SitePrefs: Codable, Equatable, Sendable {
    /// False turns JavaScript off for the site.
    public var javaScript: Bool?
    /// True asks for the mobile version of the site, false for the desktop one.
    public var mobileSite: Bool?
    /// Overrides Settings > General > Keep videos playing in the sidebar for this site.
    public var autoPiP: Bool?

    public init(javaScript: Bool? = nil, mobileSite: Bool? = nil, autoPiP: Bool? = nil) {
        self.javaScript = javaScript
        self.mobileSite = mobileSite
        self.autoPiP = autoPiP
    }

    public var isDefault: Bool { javaScript == nil && mobileSite == nil && autoPiP == nil }
}

@MainActor
@Observable
public final class SitePreferences {
    public static let shared = SitePreferences()

    public private(set) var sites: [String: SitePrefs] = [:]

    @ObservationIgnored private let url: URL
    @ObservationIgnored private let log = Logger(subsystem: "com.vega.browser", category: "SitePreferences")

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.vega.browser")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("site-preferences.json")
        if let data = try? Data(contentsOf: url) {
            do { sites = try JSONDecoder().decode([String: SitePrefs].self, from: data) }
            // A file that does not decode is kept aside, never overwritten.
            catch {
                log.error("site-preferences.json unreadable: \(error.localizedDescription)")
                try? FileManager.default.moveItem(at: url, to: base.appendingPathComponent("site-preferences-unreadable-\(Int(Date().timeIntervalSince1970)).json"))
            }
        }
    }

    /// `www.` is dropped so a site's two spellings share one entry.
    public static func key(for host: String?) -> String? {
        guard var host = host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    public func prefs(for host: String?) -> SitePrefs {
        Self.key(for: host).flatMap { sites[$0] } ?? SitePrefs()
    }

    public func update(_ host: String?, _ change: (inout SitePrefs) -> Void) {
        guard let key = Self.key(for: host) else { return }
        var value = sites[key] ?? SitePrefs()
        change(&value)
        sites[key] = value.isDefault ? nil : value
        save()
    }

    /// Forgets everything stored for the site.
    public func reset(_ host: String?) {
        guard let key = Self.key(for: host), sites[key] != nil else { return }
        sites[key] = nil
        save()
    }

    private func save() {
        do {
            try JSONEncoder().encode(sites).write(to: url, options: .atomic)
        } catch {
            log.error("site preferences save failed: \(error.localizedDescription)")
        }
    }
}
