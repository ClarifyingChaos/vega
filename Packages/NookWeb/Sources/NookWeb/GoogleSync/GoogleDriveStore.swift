// Licensed under GPL-3.0. See LICENSE.
//
//  GoogleDriveStore.swift
//  NookWeb
//
//  FORK: the sync files in Google Drive's hidden app-data folder: only Vega can see them, they
//  don't show in the person's Drive, and Google can't read the password files (encrypted).
//  Drive's app-data folder is flat, so "devices/<id>.json" is stored as "devices__<id>.json".
//

import Foundation
#if canImport(NookTabsCore)
import NookTabsCore
#endif

public struct GoogleDriveStore: SyncBlobStore {
    /// A valid access token, refreshed when needed.
    let token: @Sendable () async throws -> String

    public init(token: @escaping @Sendable () async throws -> String) { self.token = token }

    public static func flatName(_ path: String) -> String { path.replacingOccurrences(of: "/", with: "__") }

    /// Drive query strings quote with single quotes.
    static func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'" }

    private func request(_ url: URL, method: String = "GET", body: Data? = nil, contentType: String? = nil) async throws -> Data {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.httpBody = body
        r.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        if let contentType { r.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: r)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw URLError(.badServerResponse) }
        if status == 404 { throw DriveError.notFound }
        guard (200..<300).contains(status) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
            throw DriveError.http(status, (message?["message"] as? String) ?? "")
        }
        return data
    }

    enum DriveError: LocalizedError {
        case notFound, http(Int, String)
        var errorDescription: String? {
            switch self {
            case .notFound: return "Not found in Google Drive."
            case .http(let code, let message): return "Google Drive said \(code)\(message.isEmpty ? "" : ": " + message)"
            }
        }
    }

    private func files(matching query: String) async throws -> [(id: String, name: String)] {
        var c = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        c.queryItems = [.init(name: "spaces", value: "appDataFolder"), .init(name: "q", value: query),
                        .init(name: "fields", value: "files(id,name)"), .init(name: "pageSize", value: "200")]
        let json = try JSONSerialization.jsonObject(with: try await request(c.url!)) as? [String: Any]
        return (json?["files"] as? [[String: Any]] ?? []).compactMap {
            guard let id = $0["id"] as? String, let name = $0["name"] as? String else { return nil }
            return (id, name)
        }
    }

    public func put(_ path: String, _ data: Data) async throws {
        let name = Self.flatName(path)
        if let existing = try await files(matching: "name = \(Self.quoted(name)) and trashed = false").first {
            var c = URLComponents(string: "https://www.googleapis.com/upload/drive/v3/files/\(existing.id)")!
            c.queryItems = [.init(name: "uploadType", value: "media")]
            _ = try await request(c.url!, method: "PATCH", body: data, contentType: "application/octet-stream")
            return
        }
        // New file: metadata and content in one multipart request.
        let boundary = "vega-" + UUID().uuidString
        let metadata = try JSONSerialization.data(withJSONObject: ["name": name, "parents": ["appDataFolder"]])
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)); body.append(metadata)
        body.append(Data("\r\n--\(boundary)\r\nContent-Type: application/octet-stream\r\n\r\n".utf8)); body.append(data)
        body.append(Data("\r\n--\(boundary)--".utf8))
        var c = URLComponents(string: "https://www.googleapis.com/upload/drive/v3/files")!
        c.queryItems = [.init(name: "uploadType", value: "multipart")]
        _ = try await request(c.url!, method: "POST", body: body, contentType: "multipart/related; boundary=\(boundary)")
    }

    public func get(_ path: String) async throws -> Data? {
        guard let file = try await files(matching: "name = \(Self.quoted(Self.flatName(path))) and trashed = false").first else { return nil }
        var c = URLComponents(string: "https://www.googleapis.com/drive/v3/files/\(file.id)")!
        c.queryItems = [.init(name: "alt", value: "media")]
        do { return try await request(c.url!) } catch DriveError.notFound { return nil }
    }

    public func list(_ directory: String) async throws -> (names: [String], pending: Int) {
        let prefix = Self.flatName(directory) + "__"
        let found = try await files(matching: "name contains \(Self.quoted(prefix)) and trashed = false")
        return (found.map(\.name).filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }, 0)
    }
}
