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
            return SavedLogin(host: host, username: user, modified: item[kSecAttrModificationDate as String] as? Date ?? .distantPast)
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

    public func save(host: String, username: String, password: String) {
        let data = Data(password.utf8)
        let update = SecItemUpdate(base(host: host, username: username) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard update == errSecItemNotFound else { return }
        var add = base(host: host, username: username)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "Vega: \(PasswordHosts.normalized(host))"
        add[kSecAttrProtocol as String] = kSecAttrProtocolHTTPS
        SecItemAdd(add as CFDictionary, nil)
    }

    public func delete(host: String, username: String) {
        SecItemDelete(base(host: host, username: username) as CFDictionary)
    }
}
