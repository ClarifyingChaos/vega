// Licensed under GPL-3.0. See LICENSE.
//
//  PasswordSyncStore.swift
//  NookWeb
//
//  FORK: reads and writes the encrypted password snapshots through any `SyncBlobStore`.
//

import CryptoKit
import Foundation
#if canImport(NookTabsCore)
import NookTabsCore
#endif

/// Reading and writing encrypted snapshots through any store.
public struct PasswordSyncStore: Sendable {
    public let store: any SyncBlobStore
    public init(store: any SyncBlobStore) { self.store = store }

    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d }

    public func meta() async throws -> PasswordSyncMeta? {
        guard let data = try await store.get("passwords/meta.json") else { return nil }
        return try? Self.decoder.decode(PasswordSyncMeta.self, from: data)
    }

    public func writeMeta(_ meta: PasswordSyncMeta) async throws {
        try await store.put("passwords/meta.json", Self.encoder.encode(meta))
    }

    public func write(_ snapshot: PasswordSnapshot, key: SymmetricKey) async throws {
        let sealed = try PasswordCrypto.seal(Self.encoder.encode(snapshot), with: key)
        try await store.put("passwords/\(snapshot.deviceID.uuidString).enc", sealed)
    }

    public func readOthers(excluding own: UUID, key: SymmetricKey) async throws -> (snapshots: [PasswordSnapshot], pending: Int) {
        let (names, pending) = try await store.list("passwords")
        var out: [PasswordSnapshot] = []
        for name in names where name.hasSuffix(".enc") && name != "\(own.uuidString).enc" {
            guard let data = try await store.get("passwords/\(name)"), let plain = PasswordCrypto.open(data, with: key),
                  let snapshot = try? Self.decoder.decode(PasswordSnapshot.self, from: plain),
                  snapshot.formatVersion <= PasswordSnapshot.formatVersion else { continue }
            out.append(snapshot)
        }
        return (out, pending)
    }
}
