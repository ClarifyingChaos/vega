// Licensed under GPL-3.0. See LICENSE.
//
//  SyncCoordinator.swift
//  NookWeb
//
//  FORK: runs `SyncMerge` and `SyncFolder` for the app. Off until the person turns it on. Every
//  tick it applies what other Macs wrote, then writes this Mac's snapshot if it changed.
//  shortcut: polls every 20 s instead of watching the folder; local edits reach the other Mac
//  within one tick plus iCloud's own delay. Upgrade to a file-system event watcher if that lags.
//

import AppKit
import CryptoKit
import Foundation
import NookTabsCore
import Observation
import Security

@MainActor @Observable
public final class SyncCoordinator {
    public static let shared = SyncCoordinator()

    public enum Status: Equatable {
        case off
        /// iCloud Drive is not turned on for this account, so there is no folder to share.
        case noICloudDrive
        case syncing
        case idle(lastSync: Date, otherMacs: Int, waitingForDownload: Int)
        case failed(String)
    }

    public enum PasswordSyncError: LocalizedError {
        case syncOff, noFolder, wrongPassphrase, emptyPassphrase
        public var errorDescription: String? {
            switch self {
            case .syncOff: return "Turn on Sync with iCloud Drive first."
            case .noFolder: return "iCloud Drive isn't available."
            case .wrongPassphrase: return "That isn't the passphrase this sync was set up with."
            case .emptyPassphrase: return "Choose a passphrase of at least 8 characters."
            }
        }
    }

    private static let passwordsKey = "fork.sync.passwords"
    private static let enabledKey = "fork.sync.enabled"
    private static let deviceKey = "fork.sync.deviceID"
    private static let interval: Duration = .seconds(20)

    public private(set) var status: Status = .off
    /// Where password sync stands, shown under its switch.
    public private(set) var passwordStatus: String?
    @ObservationIgnored private weak var tabs: TabsController?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastWritten: SyncSnapshot?
    @ObservationIgnored private var observers: [Any] = []

    public var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            newValue ? begin() : stop()
        }
    }

    public var passwordsEnabled: Bool { UserDefaults.standard.bool(forKey: Self.passwordsKey) && Self.loadKey() != nil }
    @ObservationIgnored private var lastPasswordFingerprint: [String: Date]?

    // MARK: - Password sync

    /// Sets up password sync on this Mac: the first Mac creates the passphrase's salt in the shared
    /// folder, the others must enter the same passphrase. The derived key stays in this Mac's Keychain.
    public func enablePasswords(passphrase: String) async throws {
        guard isEnabled else { throw PasswordSyncError.syncOff }
        guard let url = FolderBlobStore.iCloudDrive() else { throw PasswordSyncError.noFolder }
        guard passphrase.count >= 8 else { throw PasswordSyncError.emptyPassphrase }
        let store = PasswordSyncStore(store: FolderBlobStore(url: url))
        let key: SymmetricKey
        if let meta = try await store.meta() {
            guard let k = await Task.detached(operation: { meta.key(for: passphrase) }).value else { throw PasswordSyncError.wrongPassphrase }
            key = k
        } else {
            let made = try await Task.detached { try PasswordSyncMeta.create(passphrase: passphrase) }.value
            try await store.writeMeta(made.meta)
            key = made.key
        }
        Self.saveKey(key)
        UserDefaults.standard.set(true, forKey: Self.passwordsKey)
        lastPasswordFingerprint = nil
        await tick()
    }

    public func disablePasswords() {
        UserDefaults.standard.set(false, forKey: Self.passwordsKey)
        Self.deleteKey()
        passwordStatus = nil
        lastPasswordFingerprint = nil
    }

    private func syncPasswords(folder url: URL) async {
        guard UserDefaults.standard.bool(forKey: Self.passwordsKey), let key = Self.loadKey() else { return }
        let store = PasswordSyncStore(store: FolderBlobStore(url: url))
        let vault = PasswordPrompter.shared.vault
        do {
            let (others, _) = try await store.readOthers(excluding: deviceID, key: key)
            // Merge decisions need only each login's key and time, so no password is read for them.
            var light = vault.all().map { PasswordRecord(host: $0.host, username: $0.username, password: "", modified: $0.modified) } + vault.tombstones()
            var changed = 0
            for snapshot in others {
                let changes = PasswordMerge.changes(applying: snapshot.records, to: light)
                if !changes.isEmpty { vault.apply(changes); changed += changes.count }
                light = vault.all().map { PasswordRecord(host: $0.host, username: $0.username, password: "", modified: $0.modified) } + vault.tombstones()
            }
            // Own snapshot (with passwords) only when a login or a deletion changed since the last write.
            let fingerprint = Dictionary(light.map { ($0.key + ($0.deleted ? "\u{0}" : ""), $0.modified) }, uniquingKeysWith: { a, _ in a })
            if fingerprint != lastPasswordFingerprint {
                try await store.write(PasswordSnapshot(deviceID: deviceID, records: vault.records()), key: key)
                lastPasswordFingerprint = fingerprint
            }
            passwordStatus = changed > 0 ? "Passwords synced · \(changed) updated" : "Passwords synced"
        } catch {
            passwordStatus = "Couldn't sync passwords: \(error.localizedDescription)"
        }
    }

    // The derived key, in this Mac's Keychain so the passphrase is asked once.
    private static let keyService = "com.vega.browser.syncKey"
    private static func loadKey() -> SymmetricKey? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keyService,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return SymmetricKey(data: data)
    }
    private static func saveKey(_ key: SymmetricKey) {
        deleteKey()
        let data = key.withUnsafeBytes { Data($0) }
        SecItemAdd([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keyService,
                    kSecValueData as String: data, kSecAttrLabel as String: "Vega sync key"] as CFDictionary, nil)
    }
    private static func deleteKey() {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keyService] as CFDictionary)
    }

    private var deviceID: UUID {
        if let text = UserDefaults.standard.string(forKey: Self.deviceKey), let id = UUID(uuidString: text) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: Self.deviceKey)
        return id
    }

    /// Called once at launch with the controller that owns the tree.
    public func start(tabs: TabsController) {
        self.tabs = tabs
        if isEnabled { begin() }
    }

    public func syncNow() { Task { await tick() } }

    private func begin() {
        stop(keepStatus: true)
        guard FolderBlobStore.iCloudDrive() != nil else { status = .noICloudDrive; return }
        status = .syncing
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: Self.interval)
            }
        }
        // A change made just before the app goes to the background or quits should leave this Mac.
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.willTerminateNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.writeOwn() }
            })
        }
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        })
    }

    private func stop(keepStatus: Bool = false) {
        loop?.cancel()
        loop = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if !keepStatus { status = .off }
    }

    private var deviceName: String { Host.current().localizedName ?? "Mac" }

    private func tick() async {
        guard isEnabled, let tabs else { return }
        guard let url = FolderBlobStore.iCloudDrive() else { status = .noICloudDrive; return }
        let store = FolderBlobStore(url: url)
        let own = deviceID
        do {
            let (snapshots, pending) = try await store.readOtherSnapshots(excluding: own)
            for snapshot in snapshots {
                let change = SyncMerge.change(applying: snapshot, to: tabs.tree)
                if !change.isEmpty { tabs.apply(change) }
            }
            try await writeOwn(store: store)
            await syncPasswords(folder: url)
            status = .idle(lastSync: Date(), otherMacs: snapshots.count, waitingForDownload: pending)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func writeOwn() {
        guard isEnabled, let url = FolderBlobStore.iCloudDrive() else { return }
        Task { try? await writeOwn(store: FolderBlobStore(url: url)) }
    }

    /// Writes only when something other than the timestamp changed.
    private func writeOwn(store: FolderBlobStore) async throws {
        guard let tabs else { return }
        let snapshot = SyncMerge.snapshot(of: tabs.tree, deviceID: deviceID, deviceName: deviceName)
        if let last = lastWritten, last.spaces == snapshot.spaces, last.items == snapshot.items { return }
        try await store.writeSnapshot(snapshot)
        lastWritten = snapshot
    }
}
