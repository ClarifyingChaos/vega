// Licensed under GPL-3.0. See LICENSE.
//
//  PasswordBridge.swift
//  NookWeb
//
//  FORK: the native side of the password manager: answers the page script, and holds the "Save
//  password?" offer the window shows. Private and Agent pages neither save nor fill.
//

import Foundation
import Observation
import WebKit

/// A login the person has not decided about yet.
public struct PendingPassword: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let host: String
    public let username: String
    public let password: String
    /// True when this site and user are saved with another password.
    public let isUpdate: Bool
    public let itemID: UUID
}

@MainActor @Observable
public final class PasswordPrompter {
    public static let shared = PasswordPrompter()
    public private(set) var pending: PendingPassword?
    @ObservationIgnored private var expiry: Task<Void, Never>?

    public var vault: PasswordVault = KeychainVault.shared

    func offer(host: String, username: String, password: String, itemID: UUID) {
        let settings = PasswordSettings.shared
        guard settings.offerToSave, !settings.isNeverSaved(host), !password.isEmpty else { return }
        let saved = vault.password(host: host, username: username)
        if saved == password { return }
        pending = PendingPassword(host: PasswordHosts.normalized(host), username: username, password: password,
                                  isUpdate: saved != nil, itemID: itemID)
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            if !Task.isCancelled { self?.pending = nil }
        }
    }

    public func savePending() {
        guard let p = pending else { return }
        vault.save(host: p.host, username: p.username, password: p.password)
        dismiss()
    }

    public func neverSavePending() {
        if let p = pending { PasswordSettings.shared.neverSave(p.host) }
        dismiss()
    }

    public func dismiss() {
        expiry?.cancel()
        pending = nil
    }
}

@MainActor
public final class PasswordBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let world = WKContentWorld.world(name: "VegaPasswords")
    private weak var session: PageSession?
    private weak var userContentController: WKUserContentController?

    public init(session: PageSession?, controller: WKUserContentController) {
        self.session = session
        userContentController = controller
        super.init()
        controller.removeScriptMessageHandler(forName: PasswordScript.handlerName, contentWorld: Self.world)
        controller.addScriptMessageHandler(self, contentWorld: Self.world, name: PasswordScript.handlerName)
        controller.addUserScript(WKUserScript(source: PasswordScript.source, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false, in: Self.world))
    }

    public func detach() {
        userContentController?.removeScriptMessageHandler(forName: PasswordScript.handlerName, contentWorld: Self.world)
        userContentController = nil
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                                      replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let session, !session.isPrivate, !session.isAgentPage,
              let body = message.body as? [String: Any], let op = body["op"] as? String,
              let origin = Optional(message.frameInfo.securityOrigin),
              PasswordHosts.isUsable(scheme: origin.protocol, host: origin.host) else { return replyHandler(nil, nil) }
        let host = origin.host
        let prompter = PasswordPrompter.shared
        switch op {
        case "list":
            guard PasswordSettings.shared.autofill else { return replyHandler([], nil) }
            replyHandler(prompter.vault.logins(forPageHost: host).map { ["u": $0.username] }, nil)
        case "fill":
            guard PasswordSettings.shared.autofill, let user = body["u"] as? String,
                  let login = prompter.vault.logins(forPageHost: host).first(where: { $0.username == user }) else { return replyHandler(nil, nil) }
            replyHandler(prompter.vault.password(host: login.host, username: login.username), nil)
        case "submit":
            if let user = body["u"] as? String, let secret = body["p"] as? String {
                prompter.offer(host: host, username: user, password: secret, itemID: session.itemID)
            }
            replyHandler(nil, nil)
        default:
            replyHandler(nil, nil)
        }
    }
}
