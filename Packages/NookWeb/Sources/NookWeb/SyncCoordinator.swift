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
import Foundation
import NookTabsCore
import Observation

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

    private static let enabledKey = "fork.sync.enabled"
    private static let deviceKey = "fork.sync.deviceID"
    private static let interval: Duration = .seconds(20)

    public private(set) var status: Status = .off
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
        guard SyncFolder.iCloudDrive() != nil else { status = .noICloudDrive; return }
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
        guard let url = SyncFolder.iCloudDrive() else { status = .noICloudDrive; return }
        let folder = SyncFolder(url: url)
        let own = deviceID
        // Reading and decoding other Macs' files can touch iCloud; keep it off the main actor.
        let (snapshots, pending) = await Task.detached { folder.readOthers(excluding: own) }.value
        for snapshot in snapshots {
            let change = SyncMerge.change(applying: snapshot, to: tabs.tree)
            if !change.isEmpty { tabs.apply(change) }
        }
        do {
            try writeOwn(folder: folder)
            status = .idle(lastSync: Date(), otherMacs: snapshots.count, waitingForDownload: pending)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func writeOwn() {
        guard isEnabled, let url = SyncFolder.iCloudDrive() else { return }
        try? writeOwn(folder: SyncFolder(url: url))
    }

    /// Writes only when something other than the timestamp changed.
    private func writeOwn(folder: SyncFolder) throws {
        guard let tabs else { return }
        let snapshot = SyncMerge.snapshot(of: tabs.tree, deviceID: deviceID, deviceName: deviceName)
        if let last = lastWritten, last.spaces == snapshot.spaces, last.items == snapshot.items { return }
        try folder.write(snapshot)
        lastWritten = snapshot
    }
}
