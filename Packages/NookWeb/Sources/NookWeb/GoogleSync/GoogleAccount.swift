// Licensed under GPL-3.0. See LICENSE.
//
//  GoogleAccount.swift
//  NookWeb
//
//  FORK: who is signed in to Google for sync. The refresh token lives in this Mac's Keychain; the
//  short-lived access token only in memory.
//

import AppKit
import Foundation
import Observation
import Security

@MainActor @Observable
public final class GoogleAccount {
    public static let shared = GoogleAccount()

    public private(set) var email: String? = UserDefaults.standard.string(forKey: "fork.google.email")
    public private(set) var isSigningIn = false
    public var isSignedIn: Bool { email != nil && Self.loadRefreshToken() != nil }
    /// False in a build without a Google client: the sign-in button says so instead of failing.
    public var isAvailable: Bool { GoogleOAuthConfig.load() != nil }

    @ObservationIgnored private var access: GoogleOAuth.Tokens?
    @ObservationIgnored private var loopback: GoogleLoopback?

    public func signIn() async throws {
        guard let config = GoogleOAuthConfig.load() else { throw GoogleOAuth.OAuthError.notConfigured }
        isSigningIn = true
        defer { isSigningIn = false; loopback = nil }
        let state = UUID().uuidString
        let pkce = GoogleOAuth.PKCE()
        let server = try GoogleLoopback(state: state)
        loopback = server
        let port = try await server.start()
        NSWorkspace.shared.open(GoogleOAuth.authorizationURL(config: config, port: port, state: state, pkce: pkce))
        let code = try await server.code()
        let tokens = try await GoogleOAuth.exchange(code: code, config: config, port: port, verifier: pkce.verifier)
        guard let refresh = tokens.refresh else { throw GoogleOAuth.OAuthError.badResponse }
        Self.saveRefreshToken(refresh)
        access = tokens
        email = tokens.email
        UserDefaults.standard.set(tokens.email, forKey: "fork.google.email")
    }

    public func cancelSignIn() { loopback?.cancel() }

    public func signOut() {
        Self.deleteRefreshToken()
        access = nil
        email = nil
        UserDefaults.standard.removeObject(forKey: "fork.google.email")
    }

    /// A store for the sync code, or nil when nobody is signed in.
    public func store() -> GoogleDriveStore? {
        guard isSignedIn else { return nil }
        return GoogleDriveStore(token: { [weak self] in try await self?.accessToken() ?? { throw GoogleOAuth.OAuthError.cancelled }() })
    }

    private func accessToken() async throws -> String {
        if let access, access.expires > Date() { return access.access }
        guard let config = GoogleOAuthConfig.load(), let refresh = Self.loadRefreshToken() else { throw GoogleOAuth.OAuthError.notConfigured }
        let fresh = try await GoogleOAuth.refresh(refresh, config: config)
        access = fresh
        return fresh.access
    }

    private static let service = "com.vega.browser.google"
    private static func loadRefreshToken() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var r: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess, let d = r as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    private static func saveRefreshToken(_ token: String) {
        deleteRefreshToken()
        SecItemAdd([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                    kSecValueData as String: Data(token.utf8), kSecAttrLabel as String: "Vega Google sign-in"] as CFDictionary, nil)
    }
    private static func deleteRefreshToken() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }
}
