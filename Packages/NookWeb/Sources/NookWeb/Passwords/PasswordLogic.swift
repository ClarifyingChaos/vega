// Licensed under GPL-3.0. See LICENSE.
//
//  PasswordLogic.swift
//  NookWeb
//
//  FORK: the parts of Vega's password manager that need no Keychain or web view: which saved
//  logins a page may use, the in-memory vault the tests run on, and Chrome/Safari CSV import.
//

import Foundation

/// A saved login, without its password: the list never carries secrets.
public struct SavedLogin: Identifiable, Hashable, Sendable {
    public let host: String
    public let username: String
    public var modified: Date
    public var id: String { host + "\u{1F}" + username }

    public init(host: String, username: String, modified: Date = Date()) {
        self.host = host
        self.username = username
        self.modified = modified
    }
}

public protocol PasswordVault: AnyObject {
    func all() -> [SavedLogin]
    func password(host: String, username: String) -> String?
    func save(host: String, username: String, password: String)
    func delete(host: String, username: String)
}

public enum PasswordHosts {
    /// Second-level labels under which the registrable domain has three labels (example.co.uk).
    /// shortcut: a short list instead of the public suffix list; add to it when a site is missed.
    private static let twoPartSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au", "org.au", "co.nz", "co.jp", "co.in",
        "co.za", "com.br", "com.mx", "com.ar", "com.tr", "com.cn", "com.hk", "com.sg", "com.tw", "co.kr",
    ]

    /// Lower case, no "www.", no port, no trailing dot.
    public static func normalized(_ host: String) -> String {
        var h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if h.hasPrefix("www.") { h.removeFirst(4) }
        return h
    }

    /// example.com for login.example.com; an IP address or single label is its own.
    public static func registrable(_ host: String) -> String {
        let h = normalized(host)
        if h.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) { return h }
        let labels = h.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return h }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        return labels.suffix(twoPartSuffixes.contains(lastTwo) ? 3 : 2).joined(separator: ".")
    }

    /// A page may use a login saved for its own site or a sibling subdomain, never another site.
    public static func matches(saved: String, page: String) -> Bool {
        let s = normalized(saved), p = normalized(page)
        return s == p || registrable(s) == registrable(p)
    }

    /// Plain http is trusted for the machine itself only.
    public static func isUsable(scheme: String?, host: String?) -> Bool {
        guard let host else { return false }
        if scheme == "https" { return true }
        return scheme == "http" && (host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".localhost"))
    }
}

public extension PasswordVault {
    func logins(forPageHost page: String) -> [SavedLogin] {
        all().filter { PasswordHosts.matches(saved: $0.host, page: page) }
            .sorted { ($0.host == PasswordHosts.normalized(page) ? 0 : 1, $0.username.lowercased()) < ($1.host == PasswordHosts.normalized(page) ? 0 : 1, $1.username.lowercased()) }
    }
}

/// For tests, and for private windows' nothing.
public final class MemoryVault: PasswordVault {
    private var items: [String: (login: SavedLogin, password: String)] = [:]
    public init() {}
    public func all() -> [SavedLogin] { items.values.map(\.login) }
    public func password(host: String, username: String) -> String? { items[SavedLogin(host: host, username: username).id]?.password }
    public func save(host: String, username: String, password: String) {
        let login = SavedLogin(host: PasswordHosts.normalized(host), username: username)
        items[login.id] = (login, password)
    }
    public func delete(host: String, username: String) { items[SavedLogin(host: PasswordHosts.normalized(host), username: username).id] = nil }
}

public enum PasswordCSV {
    public struct Row: Equatable, Sendable { public var host: String; public var username: String; public var password: String }

    /// Rows of a Chrome or Safari export. Columns are found by name (url, username, password); rows
    /// without all three are skipped, and a url without a scheme is read as https.
    public static func parse(_ text: String) -> (rows: [Row], skipped: Int) {
        let records = records(text)
        guard let header = records.first?.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }),
              let u = header.firstIndex(where: { $0 == "url" || $0 == "origin" || $0 == "website" }),
              let n = header.firstIndex(where: { $0 == "username" || $0 == "login" || $0 == "user" }),
              let p = header.firstIndex(of: "password") else { return ([], max(records.count - 1, 0)) }
        var rows: [Row] = [], skipped = 0
        for record in records.dropFirst() {
            guard record.count > max(u, n, p) else { skipped += 1; continue }
            let raw = record[u].trimmingCharacters(in: .whitespaces)
            let host = (URL(string: raw)?.host ?? URL(string: "https://" + raw)?.host).map(PasswordHosts.normalized)
            guard let host, !host.isEmpty, !record[n].isEmpty, !record[p].isEmpty else { skipped += 1; continue }
            rows.append(Row(host: host, username: record[n], password: record[p]))
        }
        return (rows, skipped)
    }

    /// RFC 4180: quoted fields may hold commas, quotes ("") and line breaks.
    static func records(_ text: String) -> [[String]] {
        var out: [[String]] = [], row: [String] = [], field = "", quoted = false
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n")).makeIterator()
        var next = chars.next()
        while let c = next {
            next = chars.next()
            if quoted {
                if c == "\"" { if next == "\"" { field.append("\""); next = chars.next() } else { quoted = false } } else { field.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == "," { row.append(field); field = "" }
            else if c == "\n" { row.append(field); field = ""; if !(row.count == 1 && row[0].isEmpty) { out.append(row) }; row = [] }
            else { field.append(c) }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); out.append(row) }
        return out
    }
}
