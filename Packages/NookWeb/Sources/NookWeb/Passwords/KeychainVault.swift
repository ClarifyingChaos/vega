// Licensed under GPL-3.0. See LICENSE.
//
//  KeychainVault.swift
//  NookWeb
//
//  FORK: Vega's saved logins live in the login Keychain as internet passwords: encrypted by the
//  system, not readable by other apps without a prompt. Listing reads attributes only, so it
//  never asks for access; reading a password does.
//

import Foundation
import Security

public final class KeychainVault: PasswordVault {
    public static let shared = KeychainVault()
    /// Marks Vega's items among everything else in the Keychain.
    private static let domain = "com.vega.browser.passwords"

    private init() {}

    private func base(host: String? = nil, username: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrSecurityDomain as String: Self.domain,
        ]
        if let host { query[kSecAttrServer as String] = PasswordHosts.normalized(host) }
        if let username { query[kSecAttrAccount as String] = username }
        return query
    }

    /// When a login last changed, kept in the item itself so a login written from another Mac keeps
    /// that Mac's time; the Keychain's own modification date would be "now" and bounce between Macs.
    private static func encode(_ date: Date) -> Data { Data(String(date.timeIntervalSince1970).utf8) }
    private static func decode(_ data: Data?) -> Date? {
        data.flatMap { String(data: $0, encoding: .utf8) }.flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
    }

    public func all() -> [SavedLogin] {
        var query = base()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let host = item[kSecAttrServer as String] as? String,
                  let user = item[kSecAttrAccount as String] as? String else { return nil }
            let modified = Self.decode(item[kSecAttrGeneric as String] as? Data)
                ?? item[kSecAttrModificationDate as String] as? Date ?? .distantPast
            return SavedLogin(host: host, username: user, modified: modified)
        }
    }

    public func password(host: String, username: String) -> String? {
        var query = base(host: host, username: username)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func save(host: String, username: String, password: String, modified: Date) {
        let data = Data(password.utf8)
        let attrs: [String: Any] = [kSecValueData as String: data, kSecAttrGeneric as String: Self.encode(modified)]
        let update = SecItemUpdate(base(host: host, username: username) as CFDictionary, attrs as CFDictionary)
        if update == errSecItemNotFound {
            var add = base(host: host, username: username)
            add.merge(attrs) { $1 }
            add[kSecAttrLabel as String] = "Vega: \(PasswordHosts.normalized(host))"
            add[kSecAttrProtocol as String] = kSecAttrProtocolHTTPS
            SecItemAdd(add as CFDictionary, nil)
        }
        forgetTombstone(host: host, username: username)
    }

    public func delete(host: String, username: String, at: Date) {
        SecItemDelete(base(host: host, username: username) as CFDictionary)
        var all = storedTombstones().filter { $0.key != PasswordRecord(host: PasswordHosts.normalized(host), username: username, password: "", modified: at).key }
        all.append(PasswordRecord(host: PasswordHosts.normalized(host), username: username, password: "", modified: at, deleted: true))
        storeTombstones(all)
    }

    // MARK: - Remembered deletions (no secrets in them)

    private static let tombstoneKey = "fork.passwords.tombstones"

    public func tombstones() -> [PasswordRecord] { PasswordMerge.pruned(storedTombstones()) }

    private func storedTombstones() -> [PasswordRecord] {
        guard let data = UserDefaults.standard.data(forKey: Self.tombstoneKey) else { return [] }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
        return (try? decoder.decode([PasswordRecord].self, from: data)) ?? []
    }

    private func storeTombstones(_ records: [PasswordRecord]) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
        UserDefaults.standard.set(try? encoder.encode(PasswordMerge.pruned(records)), forKey: Self.tombstoneKey)
    }

    private func forgetTombstone(host: String, username: String) {
        let key = PasswordRecord(host: PasswordHosts.normalized(host), username: username, password: "", modified: Date()).key
        let all = storedTombstones()
        if all.contains(where: { $0.key == key }) { storeTombstones(all.filter { $0.key != key }) }
    }
}
