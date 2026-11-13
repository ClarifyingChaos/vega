// Licensed under GPL-3.0. See LICENSE.
//
//  GoogleSyncCheck.swift
//  Nook
//
//  The parts of Google sign-in and Drive storage that need no Google account: PKCE, the sign-in
//  URL, the loopback server (right state accepted, wrong state ignored), Drive file naming and
//  query quoting. Compiles the shipped sources:
//
//    swiftc -parse-as-library Packages/NookTabsCore/Sources/NookTabsCore/*.swift \
//           Packages/NookWeb/Sources/NookWeb/GoogleSync/GoogleOAuth.swift \
//           Packages/NookWeb/Sources/NookWeb/GoogleSync/GoogleLoopback.swift \
//           Packages/NookWeb/Sources/NookWeb/GoogleSync/GoogleDriveStore.swift \
//           Packages/NookWeb/Checks/GoogleSyncCheck.swift -o /tmp/google-sync-check && /tmp/google-sync-check
//

import Foundation

@main
struct GoogleSyncCheck {
    static func main() async throws {
        // RFC 7636's example: verifier dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk -> E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM
        let pkce = GoogleOAuth.PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        precondition(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", pkce.challenge)
        let generated = GoogleOAuth.PKCE.randomVerifier()
        precondition(generated.count >= 43 && !generated.contains("=") && !generated.contains("+"))

        let config = GoogleOAuthConfig(clientID: "id.apps.googleusercontent.com", clientSecret: "x")
        let url = GoogleOAuth.authorizationURL(config: config, port: 5555, state: "st", pkce: pkce)
        let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        precondition(url.host == "accounts.google.com" && q["redirect_uri"] == "http://127.0.0.1:5555")
        precondition(q["code_challenge_method"] == "S256" && q["code_challenge"] == pkce.challenge && q["state"] == "st")
        precondition(q["scope"]!.contains("drive.appdata") && !q["scope"]!.contains("drive.file") && !q["scope"]!.contains("/auth/drive "), "only the app-data scope")
        precondition(q["access_type"] == "offline")

        // The ID token's email (a hand-made token: only the middle part is read).
        let payload = Data(#"{"email":"me@example.com"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        precondition(GoogleOAuth.email(fromIDToken: "h.\(payload).s") == "me@example.com")
        precondition(GoogleOAuth.email(fromIDToken: "garbage") == nil)

        // Drive naming and quoting.
        precondition(GoogleDriveStore.flatName("devices/ABC.json") == "devices__ABC.json")
        precondition(GoogleDriveStore.quoted("it's") == "'it\\'s'")

        // The loopback server: a wrong-state request is ignored, the right one delivers the code.
        let server = try GoogleLoopback(state: "good")
        let port = try await server.start()
        async let code = server.code(timeout: 10)
        try await Task.sleep(for: .milliseconds(100))
        let (_, bad) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/?code=evil&state=bad")!)
        precondition((bad as? HTTPURLResponse)?.statusCode == 404, "wrong state ignored")
        let (_, good) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/?code=abc123&state=good")!)
        precondition((good as? HTTPURLResponse)?.statusCode == 200)
        let received = try await code
        precondition(received == "abc123", "got \(received)")
        print("GoogleSyncCheck passed")
    }
}
