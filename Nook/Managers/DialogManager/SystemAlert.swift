// Licensed under GPL-3.0. See LICENSE.
//
//  SystemAlert.swift
//  Nook
//
//  Plain confirmations go through NSAlert, so they look, read and behave like every other
//  Mac app's (HIG, Alerts): system glass, Return and Escape, Cmd-D for Don't Save, VoiceOver.
//  Rich dialogs with their own content stay on DialogManager.
//

import AppKit

@MainActor
enum SystemAlert {
    /// A sheet on the key window when there is one, otherwise app-modal.
    static func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    static func make(_ title: String, _ detail: String, style: NSAlert.Style = .informational, buttons: [String]) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = style
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert
    }
}
