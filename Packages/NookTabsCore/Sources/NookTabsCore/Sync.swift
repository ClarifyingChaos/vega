// Licensed under GPL-3.0. See LICENSE.
//
//  Sync.swift
//  NookTabsCore
//
//  FORK: sync of spaces, favorites and pinned tabs between Macs through a shared folder (iCloud
//  Drive). No CloudKit, so no paid Apple account. Each Mac writes its own snapshot file and reads
//  the others'; the newest `modifiedAt` of each record wins, deletions travel as tombstones.
//  Open tabs stay on their Mac (device scope), as in the tab store.
//

import Foundation

/// One Mac's synced scope: every space and every favorite, pinned tab and folder in them.
public struct SyncSnapshot: Codable, Equatable, Sendable {
    public static let formatVersion = 1
    public var formatVersion = SyncSnapshot.formatVersion
    public var deviceID: UUID
    public var deviceName: String
    public var writtenAt: Date
    public var spaces: [SpaceRecord]
    public var items: [Item]

    public init(deviceID: UUID, deviceName: String, writtenAt: Date = Date(), spaces: [SpaceRecord], items: [Item]) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.writtenAt = writtenAt
        self.spaces = spaces
        self.items = items
    }
}

public enum SyncMerge {
    /// Tombstones older than this are left out of snapshots, so the files stay small. A Mac that
    /// has been offline longer can resurrect something deleted meanwhile.
    public static let tombstoneDays = 30

    /// The synced scope of a tree. The Agent space is this Mac's own and never travels.
    public static func snapshot(of tree: TabTree, deviceID: UUID, deviceName: String, now: Date = Date()) -> SyncSnapshot {
        let cutoff = now.addingTimeInterval(-Double(tombstoneDays) * 86_400)
        func kept(_ deleted: Date?) -> Bool { deleted.map { $0 > cutoff } ?? true }
        let agentIDs = Set(tree.spaces.values.filter(\.isAgent).map(\.id))
        let spaces = tree.spaces.values.filter { !$0.isAgent && kept($0.deletedAt) }
        let items = tree.items.values.filter { item in
            guard kept(item.deletedAt), tree.scope(of: item.id) == .synced else { return false }
            return !(tree.spaceID(of: item.id).map(agentIDs.contains) ?? false)
        }
        return SyncSnapshot(deviceID: deviceID, deviceName: deviceName, writtenAt: now,
                            spaces: spaces.sorted { $0.id.uuidString < $1.id.uuidString },
                            items: items.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    /// What to write into `tree` so it holds the newest version of every record in `remote`.
    /// Empty when the tree is already at least as new. Ties keep the local record, so two Macs
    /// that have exchanged everything stop producing changes.
    public static func change(applying remote: SyncSnapshot, to tree: TabTree) -> Change {
        var change = Change()
        for space in remote.spaces where !space.isAgent {
            let local = tree.spaces[space.id]
            if let local {
                if space.modifiedAt > local.modifiedAt { change.spaces[space.id] = .some(space) }
            } else if space.deletedAt == nil {
                change.spaces[space.id] = .some(space)
            }
        }
        for item in remote.items {
            let local = tree.items[item.id]
            if let local {
                if item.modifiedAt > local.modifiedAt { change.items[item.id] = .some(item) }
            } else if item.deletedAt == nil {
                change.items[item.id] = .some(item)
            }
        }
        return change
    }
}

/// The shared folder: `devices/<device id>.json` per Mac, written atomically by that Mac only.
public struct SyncFolder: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }

    /// iCloud Drive's folder for apps without an iCloud container, if iCloud Drive is on.
    public static func iCloudDrive(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let drive = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return FileManager.default.fileExists(atPath: drive.path) ? drive.appendingPathComponent("Vega Sync", isDirectory: true) : nil
    }

    private var devicesURL: URL { url.appendingPathComponent("devices", isDirectory: true) }
    private func file(_ id: UUID) -> URL { devicesURL.appendingPathComponent("\(id.uuidString).json") }

    public func write(_ snapshot: SyncSnapshot) throws {
        try FileManager.default.createDirectory(at: devicesURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: file(snapshot.deviceID), options: .atomic)
    }

    /// Other Macs' snapshots. Files iCloud has not downloaded yet are requested and read next time;
    /// files that fail to decode are skipped, so one bad file never stops the rest.
    public func readOthers(excluding own: UUID) -> (snapshots: [SyncSnapshot], pending: Int) {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: devicesURL.path) else { return ([], 0) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var snapshots: [SyncSnapshot] = []
        var pending = 0
        for name in names {
            // An evicted file shows as ".<name>.icloud"; asking for the real one starts its download.
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                let real = String(name.dropFirst().dropLast(".icloud".count))
                try? manager.startDownloadingUbiquitousItem(at: devicesURL.appendingPathComponent(real))
                pending += 1
                continue
            }
            guard name.hasSuffix(".json"), name != "\(own.uuidString).json",
                  let data = try? Data(contentsOf: devicesURL.appendingPathComponent(name)),
                  let snapshot = try? decoder.decode(SyncSnapshot.self, from: data),
                  snapshot.formatVersion <= SyncSnapshot.formatVersion, snapshot.deviceID != own else { continue }
            snapshots.append(snapshot)
        }
        return (snapshots, pending)
    }
}
