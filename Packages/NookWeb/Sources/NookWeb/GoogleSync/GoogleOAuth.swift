// Licensed under GPL-3.0. See LICENSE.
//
//  GoogleOAuth.swift
//  NookWeb
//
//  FORK: Sign in with Google, the installed-app way: the system browser shows Google's own page,
//  a loopback address on this Mac receives the answer, and PKCE protects the exchange. Vega asks for
//  one thing: its own hidden app-data folder in Google Drive (drive.appdata), plus the email address
//  to show who is signed in.
//

import CryptoKit
import Foundation

public struct GoogleOAuthConfig: Sendable {
    public let clientID: String
    public let clientSecret: String

    /// Read from GoogleOAuth.plist in the app, or in Application Support/com.vega.browser for a dev
    /// build. The secret of an installed-app client is not confidential (Google's own words), but it
    /// stays out of the repository; scripts/release.sh copies the file into the app.
    public static func load() -> GoogleOAuthConfig? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.vega.browser/GoogleOAuth.plist")
        let candidates = [Bundle.main.url(forResource: "GoogleOAuth", withExtension: "plist"), support].compactMap { $0 }
        for url in candidates {
            guard let dict = NSDictionary(contentsOf: url), let id = dict["ClientID"] as? String, !id.isEmpty,
                  let secret = dict["ClientSecret"] as? String else { continue }
            return GoogleOAuthConfig(clientID: id, clientSecret: secret)
        }
        return nil
    }
}

public enum GoogleOAuth {
    public static let scopes = "openid email https://www.googleapis.com/auth/drive.appdata"
    static let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    public struct PKCE: Sendable {
        public let verifier: String
        public var challenge: String { Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8)))) }

        public init(verifier: String = PKCE.randomVerifier()) { self.verifier = verifier }

        public static func randomVerifier() -> String { base64url(Data((0..<48).map { _ in UInt8.random(in: 0...255) })) }
        static func base64url(_ data: Data) -> String {
            data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
    }

    public static func authorizationURL(config: GoogleOAuthConfig, port: UInt16, state: String, pkce: PKCE) -> URL {
        var c = URLComponents(string: authURL)!
        c.queryItems = [
            .init(name: "client_id", value: config.clientID),
            .init(name: "redirect_uri", value: "http://127.0.0.1:\(port)"),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: pkce.challenge),
            .init(name: "code_challenge_method", value: "S256"),
            // A refresh token only comes with offline access and a consent screen.
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        return c.url!
    }

    public struct Tokens: Sendable {
        public var access: String
        public var refresh: String?
        public var expires: Date
        public var email: String?
    }

    public enum OAuthError: LocalizedError {
        case notConfigured, cancelled, denied(String), network(String), badResponse
        public var errorDescription: String? {
            switch self {
            case .notConfigured: return "Google sign-in isn't set up in this build."
            case .cancelled: return "Sign-in was cancelled."
            case .denied(let why): return "Google said no: \(why)."
            case .network(let why): return "Couldn't reach Google: \(why)"
            case .badResponse: return "Google's answer wasn't understood."
            }
        }
    }

    static func tokenRequest(_ form: [String: String]) async throws -> Tokens {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.urlQueryAllowed; allowed.remove(charactersIn: "+&=")
        request.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").data(using: .utf8)
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) } catch { throw OAuthError.network(error.localizedDescription) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OAuthError.badResponse }
        if let error = json["error"] as? String { throw OAuthError.denied((json["error_description"] as? String) ?? error) }
        guard (response as? HTTPURLResponse)?.statusCode == 200, let access = json["access_token"] as? String else { throw OAuthError.badResponse }
        let seconds = (json["expires_in"] as? Double) ?? 3600
        return Tokens(access: access, refresh: json["refresh_token"] as? String,
                      expires: Date().addingTimeInterval(seconds - 60), email: (json["id_token"] as? String).flatMap(email(fromIDToken:)))
    }

    /// The email in the signed ID token. It is read, not trusted for anything: it only labels the account.
    static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["email"] as? String
    }

    public static func exchange(code: String, config: GoogleOAuthConfig, port: UInt16, verifier: String) async throws -> Tokens {
        try await tokenRequest(["code": code, "client_id": config.clientID, "client_secret": config.clientSecret,
                                "redirect_uri": "http://127.0.0.1:\(port)", "grant_type": "authorization_code", "code_verifier": verifier])
    }

    public static func refresh(_ refreshToken: String, config: GoogleOAuthConfig) async throws -> Tokens {
        try await tokenRequest(["refresh_token": refreshToken, "client_id": config.clientID, "client_secret": config.clientSecret, "grant_type": "refresh_token"])
    }
}
