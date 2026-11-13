// Licensed under GPL-3.0. See LICENSE.
//
//  GoogleLoopback.swift
//  NookWeb
//
//  FORK: the one-shot web server on 127.0.0.1 that receives Google's redirect. It answers a single
//  request, checks the `state` it was started with, and shuts down.
//

import Foundation
import Network

final class GoogleLoopback: @unchecked Sendable {
    private let listener: NWListener
    private let state: String
    private var continuation: CheckedContinuation<String, Error>?
    private let queue = DispatchQueue(label: "com.vega.browser.google-loopback")
    private(set) var port: UInt16 = 0

    init(state: String) throws {
        self.state = state
        let params = NWParameters.tcp
        // Only this Mac can reach it.
        params.requiredInterfaceType = .loopback
        listener = try NWListener(using: params)
    }

    /// Starts listening and returns the port Google should redirect to.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (ready: CheckedContinuation<UInt16, Error>) in
            let answered = NSLock()
            nonisolated(unsafe) var done = false
            listener.stateUpdateHandler = { [weak self] newState in
                guard let self else { return }
                answered.lock(); defer { answered.unlock() }
                guard !done else { return }
                switch newState {
                case .ready: done = true; self.port = self.listener.port?.rawValue ?? 0; ready.resume(returning: self.port)
                case .failed(let error): done = true; ready.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.start(queue: queue)
        }
    }

    /// Waits for Google's redirect and returns the authorization code.
    func code(timeout: TimeInterval = 300) async throws -> String {
        let deadline = DispatchWorkItem { [weak self] in self?.finish(.failure(GoogleOAuth.OAuthError.cancelled)) }
        queue.asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer { deadline.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { self.continuation = continuation }
        }
    }

    func cancel() { finish(.failure(GoogleOAuth.OAuthError.cancelled)) }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { connection.cancel(); return }
            let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let items = URLComponents(string: "http://127.0.0.1" + target)?.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            var body = "<h2>Signed in to Vega</h2><p>You can close this tab and go back to Vega.</p>"
            if value("state") != self.state || (value("code") == nil && value("error") == nil) {
                // Not Google's answer (a favicon request, a probe): ignore, keep waiting.
                self.reply(connection, status: "404 Not Found", body: "")
                return
            }
            if let error = value("error") {
                body = "<h2>Sign-in didn't finish</h2><p>You can close this tab.</p>"
                self.finish(.failure(GoogleOAuth.OAuthError.denied(error)))
            } else if let code = value("code") {
                self.finish(.success(code))
            }
            self.reply(connection, status: "200 OK", body: "<!doctype html><meta charset=utf-8><body style=\"font:16px system-ui;padding:40px\">\(body)")
        }
    }

    private func reply(_ connection: NWConnection, status: String, body: String) {
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data((head + body).utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func finish(_ result: Result<String, Error>) {
        queue.async {
            self.listener.cancel()
            guard let continuation = self.continuation else { return }
            self.continuation = nil
            continuation.resume(with: result)
        }
    }
}
