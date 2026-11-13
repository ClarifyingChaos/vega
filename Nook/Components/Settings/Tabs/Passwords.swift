// Licensed under GPL-3.0. See LICENSE.
//
//  Passwords.swift
//  Nook
//
//  FORK: Settings > Passwords: the switches, the saved logins (copy, edit and delete need the
//  Mac's password or Touch ID), manual add, and import of a Chrome or Safari CSV.
//

import AppKit
import LocalAuthentication
import NookDesign
import NookUI
import NookWeb
import SwiftUI
import UniformTypeIdentifiers

/// The Passwords page opens only after Touch ID or the Mac's password, every time it is opened.
struct PasswordsSettingsView: View {
    @State private var unlocked = false
    @State private var failed = false

    var body: some View {
        Group {
            if unlocked {
                PasswordsContent()
            } else {
                lockedView
            }
        }
        .onAppear { if !unlocked { unlock() } }
        // Leaving the page locks it again.
        .onDisappear { unlocked = false; failed = false }
    }

    private var lockedView: some View {
        Form {
            SettingsHero(symbol: "lock", title: "Passwords", detail: "Locked. Unlock with Touch ID or your Mac's password to see and manage saved passwords.")
            Section {
                HStack {
                    Spacer()
                    Button("Unlock", systemImage: "touchid") { unlock() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Spacer()
                }
                .padding(.vertical, NookDesign.Spacing.md)
            } footer: {
                if failed { Text("Couldn't unlock. Try again.") }
            }
        }
        .formStyle(.grouped)
    }

    private func unlock() {
        let context = LAContext()
        var error: NSError?
        // No Touch ID and no password set on the Mac: nothing to ask, so it opens.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { unlocked = true; return }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Show your saved passwords") { ok, _ in
            Task { @MainActor in
                unlocked = ok
                failed = !ok
            }
        }
    }
}

private struct PasswordsContent: View {
    @State private var settings = PasswordSettings.shared
    @State private var logins: [SavedLogin] = []
    @State private var query = ""
    @State private var editing: SavedLogin?
    @State private var adding = false
    @State private var deleting: SavedLogin?
    @State private var importResult: String?

    private let vault: PasswordVault = KeychainVault.shared

    private var shown: [SavedLogin] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = q.isEmpty ? logins : logins.filter { $0.host.contains(q) || $0.username.lowercased().contains(q) }
        return list.sorted { ($0.host, $0.username.lowercased()) < ($1.host, $1.username.lowercased()) }
    }

    var body: some View {
        Form {
            SettingsHero(symbol: "key", title: "Passwords", detail: "Saved logins, kept in your Mac's Keychain and filled only when you choose.")

            Section {
                Toggle("Offer to save passwords", isOn: $settings.offerToSave)
                Toggle("Suggest saved passwords", isOn: $settings.autofill)
            } footer: {
                Text("Nothing is filled until you pick a login from the list under a login field. Private windows never save or fill.")
            }

            Section {
                if !logins.isEmpty {
                    SidebarMenuSearchField(prompt: "Search passwords...", text: $query)
                }
                if shown.isEmpty {
                    Text(logins.isEmpty ? "No saved passwords yet." : "No matches.")
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { login in
                    HStack(spacing: NookDesign.Spacing.lg) {
                        VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                            Text(login.host)
                            Text(login.username)
                                .font(NookDesign.Font.secondary)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("Copy Username", nookIcon: "doc.on.doc") { copy(login.username) }
                            Button("Copy Password", nookIcon: "key") { reveal(login) { copy($0) } }
                            Divider()
                            Button("Edit…", nookIcon: "pencil") { reveal(login) { _ in editing = login } }
                            Button("Delete…", nookIcon: "trash", role: .destructive) { deleting = login }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel("More for \(login.host)")
                    }
                    .padding(.vertical, NookDesign.Spacing.xxs)
                }
                HStack {
                    Button("Add Password…", nookIcon: "plus") { adding = true }
                    Spacer()
                    Button("Import from CSV…") { importCSV() }
                }
                .buttonStyle(.bordered)
            } header: {
                Text("Saved Passwords")
            } footer: {
                Text(importResult ?? "Import works with a file exported from Chrome or Safari.")
            }

            if !settings.neverSaveHosts.isEmpty {
                Section {
                    ForEach(settings.neverSaveHosts, id: \.self) { host in
                        HStack {
                            Text(host)
                            Spacer()
                            Button("Remove") { settings.neverSaveHosts.removeAll { $0 == host } }
                        }
                    }
                } header: {
                    Text("Never Saved")
                } footer: {
                    Text("Vega won't offer to save passwords for these sites.")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: reload)
        .sheet(isPresented: $adding) { LoginEditor(host: "", username: "", password: "", isNew: true) { save($0, $1, $2) } }
        .sheet(item: $editing) { login in
            LoginEditor(host: login.host, username: login.username, password: vault.password(host: login.host, username: login.username) ?? "", isNew: false) { save($0, $1, $2) }
        }
        .confirmationDialog("Delete the password for \u{201C}\(deleting?.username ?? "")\u{201D} on \(deleting?.host ?? "")?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Password", role: .destructive) {
                if let login = deleting { vault.delete(host: login.host, username: login.username); reload() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can't undo this.")
        }
    }

    private func reload() { logins = vault.all() }

    private func save(_ host: String, _ user: String, _ password: String) {
        let h = PasswordHosts.normalized(host.contains("://") ? (URL(string: host)?.host ?? host) : host)
        guard !h.isEmpty, !user.isEmpty, !password.isEmpty else { return }
        vault.save(host: h, username: user, password: password)
        reload()
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // A copied password does not stay on the clipboard.
        let count = NSPasteboard.general.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            if NSPasteboard.general.changeCount == count { NSPasteboard.general.clearContents() }
        }
    }

    /// Asks for Touch ID or the Mac's password, then hands over the password.
    private func reveal(_ login: SavedLogin, _ use: @escaping (String) -> Void) {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Show the password for \(login.host)") { ok, _ in
            guard ok else { return }
            Task { @MainActor in
                if let secret = vault.password(host: login.host, username: login.username) { use(secret) }
            }
        }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.message = "Choose a passwords file exported from Chrome or Safari."
        guard panel.runModal() == .OK, let url = panel.url, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let result = PasswordCSV.parse(text)
        for row in result.rows { vault.save(host: row.host, username: row.username, password: row.password) }
        importResult = "Imported \(result.rows.count) \(result.rows.count == 1 ? "password" : "passwords")"
            + (result.skipped > 0 ? ", skipped \(result.skipped) without a site, user or password." : ".")
            + " You can delete the file now: it holds your passwords as plain text."
        reload()
    }
}

private struct LoginEditor: View {
    @State var host: String
    @State var username: String
    @State var password: String
    let isNew: Bool
    let save: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Website", text: $host, prompt: Text("example.com"))
                    .disabled(!isNew)
                TextField("Username", text: $username)
                    .disabled(!isNew)
                SecureField("Password", text: $password)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button(isNew ? "Add" : "Save") { save(host, username, password); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(host.isEmpty || username.isEmpty || password.isEmpty)
            }
            .padding(NookDesign.Spacing.xl)
        }
        .frame(width: 420)
    }
}
