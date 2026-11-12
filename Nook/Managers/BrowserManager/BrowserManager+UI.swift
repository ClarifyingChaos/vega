// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserManager+UI.swift
//  Nook
//
//  Created by Bain Gurley on 17/09/2026.
//
//  The app side of NookUI's seam: the split view, the floating dialogs, the tab-closure
//  toast, the window accent, and the two AppKit services the shared menus need.
//

import AppKit
import SwiftUI
import NookTabsCore
import NookUI
import NookWeb

extension BrowserManager: TabActions {
    func enterSplit(with itemID: UUID, placeOnRight: Bool, in window: BrowserWindowState) {
        splitManager.enterSplit(with: itemID, placeOn: placeOnRight ? .right : .left, in: window)
    }

    func separateSplit(in window: BrowserWindowState) {
        splitManager.separate(in: window)
    }

    func editPinnedURL(url: URL, title: String, onSave: @escaping (URL) -> Void) {
        dialogManager.showDialog(
            EditPinnedURLDialog(
                url: url,
                title: title,
                onSave: { [weak self] newURL in
                    onSave(newURL)
                    self?.dialogManager.closeDialog()
                },
                onCancel: { [weak self] in self?.dialogManager.closeDialog() }
            )
        )
    }

    /// Asks for a feed URL and adds a live feed folder to the space's pinned section.
    func presentFeedFolderPrompt(in spaceID: UUID) {
        dialogManager.showDialog(
            FeedFolderDialog(
                onAdd: { [weak self] url in
                    self?.tabs.createLiveFolder(.feed(url), in: spaceID)
                    self?.dialogManager.closeDialog()
                },
                onCancel: { [weak self] in self?.dialogManager.closeDialog() }
            )
        )
    }

    func presentSpaceCreation(onCreate:@escaping (String, String) -> Void) {
        dialogManager.showDialog(
            SpaceCreationDialog(
                onCreate: { [weak self] name, accentHex in
                    onCreate(name, accentHex)
                    self?.dialogManager.closeDialog()
                },
                onCancel: { [weak self] in self?.dialogManager.closeDialog() }
            )
        )
    }

    func confirmSpaceDeletion(spaceName: String, tabCount: Int, isLastSpace: Bool, onDelete: @escaping () -> Void) {
        // FORK: a system alert with a destructive button (HIG, Alerts).
        if isLastSpace {
            SystemAlert.present(SystemAlert.make("You can't delete the last space", "Create another space first.", buttons: ["OK"])) { _ in }
            return
        }
        let tabs = tabCount == 1 ? "Its 1 tab" : "Its \(tabCount) tabs"
        let alert = SystemAlert.make("Delete \u{201C}\(spaceName)\u{201D}?", "\(tabs) will be deleted. You can't undo this.",
                                     style: .warning, buttons: ["Delete", "Cancel"])
        alert.buttons.first?.hasDestructiveAction = true
        SystemAlert.present(alert) { response in
            if response == .alertFirstButtonReturn { onDelete() }
        }
    }

    func openSpaceSettings() {
        openSettings(tab: .spaces)
    }

    var accentColor: Color {
        gradientColorManager.accentColor
    }

    func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func share(_ url: URL) {
        let picker = NSSharingServicePicker(items: [url as NSURL])
        guard let window = NSApp.keyWindow else { return }
        picker.show(relativeTo: .zero, of: window.contentView ?? NSView(), preferredEdge: .minY)
    }
}
