// Licensed under GPL-3.0. See LICENSE.
//
//  PasswordLogicCheck.swift
//  Nook
//
//  Host matching, the in-memory vault and CSV import of the password manager. NookWeb has no
//  test target, so this compiles the shipped source directly:
//
//    swiftc Packages/NookWeb/Sources/NookWeb/Passwords/PasswordLogic.swift \
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
        print("PasswordLogicCheck passed")
    }
}
