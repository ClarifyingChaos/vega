// Licensed under GPL-3.0. See LICENSE.
//
//  PasswordSync.swift
//  NookWeb
//
//  FORK: passwords between Macs. The shared folder is not end-to-end encrypted, so a snapshot is
//  sealed (AES-GCM) with a key made from a passphrase only the person knows; the store sees noise.
//  The newest `modified` of each login wins; a deletion is a record with `deleted` set.
//

import CommonCrypto
import CryptoKit
import Foundation

public struct PasswordRecord: Codable, Equatable, Sendable {
    public var host: String
    public var username: String
    public var password: String
    public var modified: Date
    public var deleted: Bool

    public init(host: String, username: String, password: String, modified: Date, deleted: Bool = false) {
        self.host = host
        self.username = username
        self.password = password
        self.modified = modified
        self.deleted = deleted
    }

    public var key: String { host + "\u{1F}" + username }
}

public struct PasswordSnapshot: Codable, Equatable, Sendable {
    public static let formatVersion = 1
    public var formatVersion = PasswordSnapshot.formatVersion
    public var deviceID: UUID
    public var writtenAt: Date
    public var records: [PasswordRecord]

    public init(deviceID: UUID, writtenAt: Date = Date(), records: [PasswordRecord]) {
        self.deviceID = deviceID
        self.writtenAt = writtenAt
        self.records = records
    }
}

public enum PasswordMerge {
    /// Deletions older than this are dropped from snapshots.
    public static let tombstoneDays = 60

    /// What to write locally so `local` holds the newest version of every record in `remote`.
    /// Ties keep the local record, so Macs that have exchanged everything stop changing.
    public static func changes(applying remote: [PasswordRecord], to local: [PasswordRecord]) -> [PasswordRecord] {
        let mine = Dictionary(local.map { ($0.key, $0) }, uniquingKeysWith: { a, b in a.modified >= b.modified ? a : b })
        return remote.filter { record in
            guard let have = mine[record.key] else { return !record.deleted }
            return record.modified > have.modified
        }
    }

    public static func pruned(_ records: [PasswordRecord], now: Date = Date()) -> [PasswordRecord] {
        let cutoff = now.addingTimeInterval(-Double(tombstoneDays) * 86_400)
        return records.filter { !$0.deleted || $0.modified > cutoff }
    }
}

public enum PasswordCrypto {
    public static let iterations = 600_000

    public static func newSalt() -> Data { Data((0..<16).map { _ in UInt8.random(in: 0...255) }) }

    /// PBKDF2-HMAC-SHA256 of the passphrase. Slow on purpose.
    public static func deriveKey(passphrase: String, salt: Data, iterations: Int = PasswordCrypto.iterations) -> SymmetricKey {
        var derived = [UInt8](repeating: 0, count: 32)
        let pass = Array(passphrase.utf8)
        _ = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.map { Int8(bitPattern: $0) }, pass.count,
                                 saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &derived, derived.count)
        }
        return SymmetricKey(data: derived)
    }

    public static func seal(_ data: Data, with key: SymmetricKey) throws -> Data {
        try AES.GCM.seal(data, using: key).combined!
    }

    /// nil when the key is wrong or the data was altered.
    public static func open(_ data: Data, with key: SymmetricKey) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
}

/// `passwords/meta.json`: the salt every Mac derives its key from, and a sealed word that proves
/// a passphrase right before any password is touched.
public struct PasswordSyncMeta: Codable, Equatable, Sendable {
    public var salt: Data
    public var iterations: Int
    public var check: Data
    static let word = Data("vega-passwords".utf8)

    public static func create(passphrase: String, iterations: Int = PasswordCrypto.iterations) throws -> (meta: PasswordSyncMeta, key: SymmetricKey) {
        let salt = PasswordCrypto.newSalt()
        let key = PasswordCrypto.deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        return (PasswordSyncMeta(salt: salt, iterations: iterations, check: try PasswordCrypto.seal(word, with: key)), key)
    }

    /// The key when the passphrase is right, nil when it is not.
    public func key(for passphrase: String) -> SymmetricKey? {
        let key = PasswordCrypto.deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        return PasswordCrypto.open(check, with: key) == Self.word ? key : nil
    }
}
