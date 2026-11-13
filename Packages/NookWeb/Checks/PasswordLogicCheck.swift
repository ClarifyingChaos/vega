// Licensed under GPL-3.0. See LICENSE.
//
//  PasswordLogicCheck.swift
//  Nook
//
//  Host matching, the in-memory vault and CSV import of the password manager. NookWeb has no
//  test target, so this compiles the shipped source directly:
//
//    swiftc Packages/NookWeb/Sources/NookWeb/Passwords/PasswordLogic.swift \
//           Packages/NookWeb/Sources/NookWeb/Passwords/PasswordSync.swift \
//           Packages/NookWeb/Checks/PasswordLogicCheck.swift -o /tmp/password-check && /tmp/password-check
//

import Foundation

@main
struct PasswordLogicCheck {
    static func main() {
        precondition(PasswordHosts.normalized("WWW.Example.com.") == "example.com")
        precondition(PasswordHosts.registrable("login.example.com") == "example.com")
        precondition(PasswordHosts.registrable("a.b.example.co.uk") == "example.co.uk")
        precondition(PasswordHosts.registrable("localhost") == "localhost")
        precondition(PasswordHosts.registrable("192.168.1.5") == "192.168.1.5")
        precondition(PasswordHosts.matches(saved: "example.com", page: "accounts.example.com"), "sibling subdomain")
        precondition(PasswordHosts.matches(saved: "www.example.com", page: "example.com"))
        precondition(!PasswordHosts.matches(saved: "example.com", page: "example.com.evil.io"), "lookalike is another site")
        precondition(!PasswordHosts.matches(saved: "example.com", page: "notexample.com"))
        precondition(!PasswordHosts.matches(saved: "a.co.uk", page: "b.co.uk"), "co.uk is a suffix, not a site")
        precondition(PasswordHosts.isUsable(scheme: "https", host: "x.com"))
        precondition(!PasswordHosts.isUsable(scheme: "http", host: "x.com"))
        precondition(PasswordHosts.isUsable(scheme: "http", host: "localhost"))

        let vault = MemoryVault()
        vault.save(host: "www.example.com", username: "Zed", password: "p1")
        vault.save(host: "example.com", username: "amy", password: "p2")
        vault.save(host: "other.org", username: "amy", password: "p3")
        let mine = vault.logins(forPageHost: "login.example.com")
        precondition(mine.map(\.username) == ["amy", "Zed"], "exact host first would tie here; then by name: \(mine.map(\.username))")
        precondition(vault.password(host: "example.com", username: "amy") == "p2")
        vault.save(host: "example.com", username: "amy", password: "new")
        precondition(vault.all().count == 3 && vault.password(host: "example.com", username: "amy") == "new", "save replaces")
        vault.delete(host: "example.com", username: "amy")
        precondition(vault.password(host: "example.com", username: "amy") == nil)
        precondition(vault.tombstones().map(\.username) == ["amy"], "a deletion is remembered for sync")
        let fromOtherMac = Date(timeIntervalSince1970: 1_900_000_000)
        vault.apply([PasswordRecord(host: "new.io", username: "zoe", password: "s", modified: fromOtherMac)])
        precondition(vault.all().first { $0.host == "new.io" }?.modified == fromOtherMac, "keeps the other Mac's time")
        precondition(vault.records().contains { $0.host == "new.io" && $0.password == "s" } && vault.records().contains { $0.deleted })

        let csv = "name,url,username,password,note\n" +
            "Ex,https://www.example.com/login,amy,\"p,1\",\n" +
            "Q,example.org,bob,\"say \"\"hi\"\"\",\"two\nlines\"\n" +
            "Bad,,nobody,x,\n" +
            "NoPw,https://a.com,u,,\n"
        let parsed = PasswordCSV.parse(csv)
        precondition(parsed.rows == [.init(host: "example.com", username: "amy", password: "p,1"),
                                     .init(host: "example.org", username: "bob", password: "say \"hi\"")], "\(parsed.rows)")
        precondition(parsed.skipped == 2)
        precondition(PasswordCSV.parse("a,b\n1,2").rows.isEmpty, "unknown header imports nothing")
        // Sync: newest wins, a deletion travels, ties change nothing.
        let t0 = Date(timeIntervalSince1970: 1_800_000_000), t1 = t0.addingTimeInterval(60), t2 = t0.addingTimeInterval(120)
        let a1 = PasswordRecord(host: "a.com", username: "u", password: "old", modified: t0)
        let a2 = PasswordRecord(host: "a.com", username: "u", password: "new", modified: t1)
        precondition(PasswordMerge.changes(applying: [a2], to: [a1]) == [a2], "newer replaces")
        precondition(PasswordMerge.changes(applying: [a1], to: [a2]).isEmpty, "older ignored")
        precondition(PasswordMerge.changes(applying: [a2], to: [a2]).isEmpty, "tie keeps local")
        precondition(PasswordMerge.changes(applying: [a1], to: []) == [a1], "new login arrives")
        let gone = PasswordRecord(host: "a.com", username: "u", password: "", modified: t2, deleted: true)
        precondition(PasswordMerge.changes(applying: [gone], to: [a2]) == [gone], "deletion wins when newer")
        precondition(PasswordMerge.changes(applying: [gone], to: []).isEmpty, "a deletion of nothing is nothing")
        precondition(PasswordMerge.changes(applying: [a1], to: [gone]).isEmpty, "a deleted login does not come back")
        precondition(PasswordMerge.pruned([gone], now: t2.addingTimeInterval(61 * 86_400)).isEmpty, "old tombstone dropped")

        // Crypto: right passphrase opens, wrong one and tampering do not; the store never sees plaintext.
        let made = try! PasswordSyncMeta.create(passphrase: "correct horse", iterations: 1_000)
        precondition(made.meta.key(for: "correct horse") != nil)
        precondition(made.meta.key(for: "wrong") == nil)
        let snap = PasswordSnapshot(deviceID: UUID(), writtenAt: t0, records: [a2])
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let plain = try! enc.encode(snap)
        let sealed = try! PasswordCrypto.seal(plain, with: made.key)
        precondition(!String(decoding: sealed, as: UTF8.self).contains("a.com"), "ciphertext hides the host")
        precondition(PasswordCrypto.open(sealed, with: made.key) == plain)
        precondition(PasswordCrypto.open(sealed, with: PasswordCrypto.deriveKey(passphrase: "x", salt: made.meta.salt, iterations: 1_000)) == nil)
        var tampered = sealed; tampered[tampered.count - 1] ^= 1
        precondition(PasswordCrypto.open(tampered, with: made.key) == nil, "altered data is rejected")
        print("PasswordLogicCheck passed")
    }
}
