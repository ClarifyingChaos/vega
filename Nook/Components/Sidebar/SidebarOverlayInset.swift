// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarOverlayInset.swift
//  Nook
//
//  How far the hover overlay sits in from the window's corner. The window buttons stay in the
//  corner, so the title row cancels the inset to keep the toggle and history buttons where
//  they are with the sidebar docked.
//

import SwiftUI

private struct SidebarOverlayInsetKey: EnvironmentKey {
    static let defaultValue = CGSize.zero
}

extension EnvironmentValues {
    var sidebarOverlayInset: CGSize {
        get { self[SidebarOverlayInsetKey.self] }
        set { self[SidebarOverlayInsetKey.self] = newValue }
    }
}
