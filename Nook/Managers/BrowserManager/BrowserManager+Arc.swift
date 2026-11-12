// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserManager+Arc.swift
//  Nook
//
//  FORK: actions behind the Arc menu items the fork adds (File, View, Tabs, Spaces, Archive,
//  Window). Each works on the active window and reuses the existing tab, split and window code.
//

import AppKit
import Observation
import NookTabsCore
import NookWeb
import UniformTypeIdentifiers

/// Window numbers the person set to Stay on Top.
@MainActor @Observable
final class FloatingWindows {
    static let shared = FloatingWindows()
    var numbers: Set<Int> = []
}

extension BrowserManager {
    private var activeWindowState: BrowserWindowState? { windowRegistry?.activeWindow }

    // MARK: - Tabs

    /// Arc's Clear Today: archive every unpinned tab in the current space.
    func clearToday() {
        guard let window = activeWindowState, let spaceID = window.spaceID else { return }
        let ids = tabs.children(of: .tabs(spaceID: spaceID)).map(\.id)
        guard !ids.isEmpty else { return }
        tabs.close(ids, archive: true)
    }

    /// Arc's Reset All Tabs in This Space: every pinned tab and favorite goes back to its pinned URL.
    func resetAllTabsInSpace() {
        guard let spaceID = activeWindowState?.spaceID else { return }
        func reset(_ parent: Parent) {
            for item in tabs.children(of: parent) {
                switch item.kind {
                case .folder: reset(.folder(itemID: item.id))
                case .tab: if tabs.hasLeftHome(item.id) { tabs.resetToHome(item.id) }
                }
            }
        }
        reset(.favorites(spaceID: spaceID))
        reset(.pinned(spaceID: spaceID))
    }

    /// Shows the sidebar and opens every folder above the selected tab.
    func revealSelectedTabInSidebar() {
        guard let window = activeWindowState, let selected = window.selectedItemID else { return }
        if !window.isSidebarVisible { toggleSidebar(for: window) }
        var parent = tabs.item(selected)?.parent
        while case .folder(let folderID)? = parent {
            tabs.openFolder(folderID)
            parent = tabs.item(folderID)?.parent
        }
        if case .pinned(let spaceID)? = parent { tabs.setPinnedCollapsed(false, space: spaceID) }
    }

    /// Folds or unfolds the current space's pinned section, as Arc's Expand/Collapse Pinned Tabs.
    func togglePinnedSection() {
        guard let spaceID = activeWindowState?.spaceID else { return }
        tabs.setPinnedCollapsed(!tabs.isPinnedCollapsed(space: spaceID), space: spaceID)
    }

    var isPinnedSectionCollapsed: Bool {
        activeWindowState?.spaceID.map { tabs.isPinnedCollapsed(space: $0) } ?? false
    }

    // MARK: - Split View

    /// Arc's Add Split View: opens the search engine's start page beside the current tab.
    func addSplitView() {
        guard let window = activeWindowState, window.selectedItemID != nil,
              let id = tabs.open(url: startPageURL, in: window, placement: .background) else { return }
        splitManager.enterSplit(with: id, placeOn: .right, in: window)
    }

    /// Closes the active pane's tab and leaves the other pane as the page.
    func closeActiveSplitPane() {
        guard let window = activeWindowState, let split = window.split else { return }
        let side = splitManager.activeSide(for: window.id) ?? .right
        let closing = side == .left ? split.leftItemID : split.rightItemID
        splitManager.exitSplit(keep: side == .left ? .right : .left, for: window.id)
        tabs.close(closing, archive: true)
    }

    // MARK: - Windows

    /// Arc's Little Arc: a small window, outside the sidebar, on the start page.
    func openLittleArcWindow() {
        externalMiniWindowManager.present(url: startPageURL)
    }

    /// Arc's Stay On Top: the active window floats above other apps' windows.
    func toggleStayOnTop() {
        guard let window = activeWindowState?.window else { return }
        window.level = window.level == .floating ? .normal : .floating
        FloatingWindows.shared.numbers.formSymmetricDifference([window.windowNumber])
    }

    /// Reads the observable copy so the menu title updates; NSWindow.level is not observable.
    var isActiveWindowOnTop: Bool {
        guard let number = activeWindowState?.window?.windowNumber else { return false }
        return FloatingWindows.shared.numbers.contains(number)
    }

    // MARK: - Page

    /// Saves the page as a Safari web archive, the format WebKit writes and Safari opens.
    func savePageAs() {
        guard let page = tabs.activeWindowSession, let webView = page.webView, let window = activeWindowState?.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.webArchive]
        panel.nameFieldStringValue = (page.title.isEmpty ? (page.url.host ?? "Page") : page.title)
            .replacingOccurrences(of: "/", with: "-")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            webView.createWebArchiveData { result in
                if case .success(let data) = result { try? data.write(to: url) }
            }
        }
    }

    /// Arc's Copy URL as Quote: the selected text as a Markdown quote, with the page's link.
    func copyURLAsQuote() {
        guard let page = tabs.activeWindowSession, let webView = page.webView else { return }
        let link = "[\(page.title.replacingOccurrences(of: "]", with: "\\]"))](\(page.url.absoluteString))"
        webView.evaluateJavaScript("window.getSelection().toString()") { result, _ in
            let selection = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let quote = selection.isEmpty ? link
                : selection.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n") + "\n\n" + link
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(quote, forType: .string)
        }
    }

    // MARK: - Archive

    /// Opens the Library on a tab: Archive, Spaces, Downloads or History.
    func openLibrary(_ tab: NookWeb.SidebarMenuTab) {
        guard let window = activeWindowState else { return }
        window.sidebarMenuSelectedTab = tab
        LibraryMotion.present(window)
    }

    /// Empties the Archive after a system confirmation; the tabs in it cannot come back.
    func confirmClearArchive() {
        let entries = tabs.archive.entries
        guard !entries.isEmpty else { return }
        let alert = SystemAlert.make("Clear the Archive?",
                                     "\(entries.count) archived \(entries.count == 1 ? "tab" : "tabs") will be deleted. You can't undo this.",
                                     style: .warning, buttons: ["Clear Archive", "Cancel"])
        alert.buttons.first?.hasDestructiveAction = true
        SystemAlert.present(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            for entry in entries { self.tabs.removeFromArchive(entry.id) }
        }
    }

    // MARK: - Helpers

    /// The search engine's home page, from the query template's scheme and host.
    private var startPageURL: URL {
        let template = nookSettings?.resolvedSearchEngineTemplate ?? "https://www.google.com/search?q=%@"
        var parts = URLComponents(string: template.replacingOccurrences(of: "%@", with: "")) ?? URLComponents()
        parts.path = "/"; parts.query = nil
        return parts.url ?? URL(string: "https://www.google.com/")!
    }
}
