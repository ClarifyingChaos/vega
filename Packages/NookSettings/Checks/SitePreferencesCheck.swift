// Licensed under GPL-3.0. See LICENSE.
//
//  swiftc Sources/NookSettings/SitePreferences.swift Checks/SitePreferencesCheck.swift -o /tmp/sp && /tmp/sp
//
//  Per-site settings: defaults store nothing, host spellings share an entry, values survive a reload,
//  and an unreadable file is moved aside, not overwritten.

import Foundation

@main
@MainActor
struct SitePreferencesCheck {
    static func main() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("site-prefs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SitePreferences(directory: dir)
        precondition(store.prefs(for: "example.com").isDefault && store.sites.isEmpty)
        precondition(SitePreferences.key(for: "WWW.Example.com") == "example.com" && SitePreferences.key(for: "") == nil && SitePreferences.key(for: nil) == nil)

        store.update("www.example.com") { $0.javaScript = false; $0.mobileSite = true }
        precondition(store.prefs(for: "example.com").javaScript == false && store.prefs(for: "EXAMPLE.com").mobileSite == true)
        precondition(store.prefs(for: "example.com").autoPiP == nil, "untouched values stay unset")
        precondition(store.prefs(for: "other.com").isDefault, "other sites are unaffected")

        // Back to defaults removes the entry.
        store.update("example.com") { $0.javaScript = nil; $0.mobileSite = nil }
        precondition(store.sites.isEmpty)

        store.update("a.com") { $0.autoPiP = true }
        store.update("b.com") { $0.javaScript = false }
        let again = SitePreferences(directory: dir)
        precondition(again.prefs(for: "a.com").autoPiP == true && again.prefs(for: "b.com").javaScript == false, "reloaded from disk")
        again.reset("a.com")
        precondition(again.prefs(for: "a.com").isDefault && again.sites.count == 1)

        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("site-prefs-bad-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bad) }
        try? Data("nope".utf8).write(to: bad.appendingPathComponent("site-preferences.json"))
        let recovered = SitePreferences(directory: bad)
        precondition(recovered.sites.isEmpty)
        precondition(((try? FileManager.default.contentsOfDirectory(atPath: bad.path)) ?? []).contains { $0.hasPrefix("site-preferences-unreadable-") })
        print("SitePreferencesCheck passed")
    }
}
