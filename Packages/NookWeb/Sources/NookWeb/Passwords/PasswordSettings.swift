// Licensed under GPL-3.0. See LICENSE.
//
//  PasswordSettings.swift
//  NookWeb
//
//  FORK: the password manager's switches and its "never save" list, in UserDefaults under the
//  fork's own keys so the shared settings service stays untouched.
//

import Foundation
import Observation

@MainActor @Observable
public final class PasswordSettings {
    public static let shared = PasswordSettings()

    private let defaults = UserDefaults.standard
    public var offerToSave: Bool = UserDefaults.standard.object(forKey: "fork.passwords.offerToSave") as? Bool ?? true {
        didSet { defaults.set(offerToSave, forKey: "fork.passwords.offerToSave") }
    }
    public var autofill: Bool = UserDefaults.standard.object(forKey: "fork.passwords.autofill") as? Bool ?? true {
        didSet { defaults.set(autofill, forKey: "fork.passwords.autofill") }
    }
    public var neverSaveHosts: [String] = UserDefaults.standard.stringArray(forKey: "fork.passwords.never") ?? [] {
        didSet { defaults.set(neverSaveHosts, forKey: "fork.passwords.never") }
    }

    public func neverSave(_ host: String) {
        let h = PasswordHosts.normalized(host)
        if !neverSaveHosts.contains(h) { neverSaveHosts.append(h) }
    }

    func isNeverSaved(_ host: String) -> Bool { neverSaveHosts.contains(PasswordHosts.normalized(host)) }
}
