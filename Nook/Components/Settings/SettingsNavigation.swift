// Licensed under GPL-3.0. See LICENSE.
//
//  SettingsNavigation.swift
//  Nook
//

import Foundation
import Observation

/// Which settings tab the Settings window shows. Window navigation state, not a setting:
/// it never syncs, so it stays in the app rather than in NookSettings.
@MainActor @Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    private static let key = "fork.lastSettingsPane"
    /// HIG (Settings, macOS): the window reopens on the pane last viewed, also after a relaunch.
    var currentSettingsTab: SettingsTabs = SettingsTabs(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .general {
        didSet { UserDefaults.standard.set(currentSettingsTab.rawValue, forKey: Self.key) }
    }
}
