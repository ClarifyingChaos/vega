// Licensed under GPL-3.0. See LICENSE.
//
//  NookCommands.swift
//  Nook
//
//  Menu bar commands for the Nook browser application
//

import AppKit
import SwiftUI
import WebKit
import NookWeb
import NookDesign
import NookSettings
import NookTabsCore

struct NookCommands: Commands {
    let browserManager: BrowserManager
    let windowRegistry: WindowRegistry
    let shortcutManager: KeyboardShortcutManager
    let tabOrganizerManager: TabOrganizerManager
    @Environment(\.openSettings) private var openSettings
    @Environment(\.nookSettings) var nookSettings

    init(browserManager: BrowserManager, windowRegistry: WindowRegistry, shortcutManager: KeyboardShortcutManager, tabOrganizerManager: TabOrganizerManager) {
        self.browserManager = browserManager
        self.windowRegistry = windowRegistry
        self.shortcutManager = shortcutManager
        self.tabOrganizerManager = tabOrganizerManager
    }

    // MARK: - Dynamic Keyboard Shortcuts

    /// Returns the key equivalent for a given action, or nil if disabled
    private func keyEquivalent(for action: ShortcutAction) -> KeyEquivalent? {
        guard let shortcut = shortcutManager.shortcut(for: action),
              shortcut.isEnabled else { return nil }
        // Handle special keys
        switch shortcut.keyCombination.key.lowercased() {
        case "return", "enter": return .return
        case "escape", "esc": return .escape
        case "delete", "backspace": return .delete
        case "tab": return .tab
        case "space": return .space
        case "up", "uparrow": return .upArrow
        case "down", "downarrow": return .downArrow
        case "left", "leftarrow": return .leftArrow
        case "right", "rightarrow": return .rightArrow
        case "home": return .home
        case "end": return .end
        case "pageup": return .pageUp
        case "pagedown": return .pageDown
        case "clear": return .clear
        default:
            // Handle single character keys
            if shortcut.keyCombination.key.count == 1,
               let char = shortcut.keyCombination.key.first {
                return KeyEquivalent(char)
            }
            return nil
        }
    }

    /// Returns the event modifiers for a given action
    private func eventModifiers(for action: ShortcutAction) -> EventModifiers {
        guard let shortcut = shortcutManager.shortcut(for: action),
              shortcut.isEnabled else { return [] }
        var modifiers: EventModifiers = []
        if shortcut.keyCombination.modifiers.contains(.command) { modifiers.insert(.command) }
        if shortcut.keyCombination.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if shortcut.keyCombination.modifiers.contains(.option) { modifiers.insert(.option) }
        if shortcut.keyCombination.modifiers.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }

    /// View extension to apply dynamic keyboard shortcut if enabled
    private func dynamicShortcut(_ action: ShortcutAction) -> some ViewModifier {
        DynamicShortcutModifier(
            keyEquivalent: keyEquivalent(for: action),
            modifiers: eventModifiers(for: action)
        )
    }

    private func spaceShortcut(_ index: Int) -> DynamicShortcutModifier {
        guard let action = ShortcutAction.goToSpaceActions[safe: index] else {
            return DynamicShortcutModifier(keyEquivalent: nil, modifiers: [])
        }
        return DynamicShortcutModifier(keyEquivalent: keyEquivalent(for: action), modifiers: eventModifiers(for: action))
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {}
        CommandGroup(replacing: .windowList) {}

        // The Settings scene supplies the standard Settings… item at ⌘,
        CommandGroup(after: .appSettings) {
            Button("Import from Another Browser…") {
                browserManager.dialogManager.showDialog(
                    BrowserImportDialog(
                        onCancel: {
                            browserManager.dialogManager.closeDialog()
                        }
                    )
                )
            }
        }

        // Replace the standard Quit menu item to route through showQuitDialog(),
        // which respects the "warn before quitting" setting
        CommandGroup(replacing: .appTermination) {
            Button("Quit Vega") {
                browserManager.showQuitDialog()
            }
            .keyboardShortcut("q", modifiers: .command)
        }

        // App Menu Section (under Nook)
        CommandGroup(after: .appInfo) {
            Divider()
            Button("Make Vega Default Browser") {
                browserManager.setAsDefaultBrowser()
            }

            // FORK: off until the appcast at SUFeedURL exists and the first release is signed with the key kept in the login Keychain (see AppDelegate).
            Button("Check for Updates…") {
                browserManager.appDelegate?.updaterController.checkForUpdates(nil)
            }
            .disabled(true)
        }
        

        // Edit Section
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Close Tab") {
                if let window = windowRegistry.activeWindow { browserManager.tabs.reopenLastClosed(in: window) }
            }
            .modifier(dynamicShortcut(.undoCloseTab))

            Button("Reopen Closed Tab") {
                if let window = windowRegistry.activeWindow { browserManager.tabs.reopenLastClosed(in: window) }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        }

        // File Section
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                windowRegistry.activeWindow?.commandPalette?.open()
            }
            .modifier(dynamicShortcut(.newTab))
            Button("New Window") {
                browserManager.createNewWindow()
            }
            .modifier(dynamicShortcut(.newWindow))
            
            Button("New Incognito Window") {
                browserManager.createIncognitoWindow()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            // FORK: Arc's File items.
            Button("New Little Arc Window") { browserManager.openLittleArcWindow() }
                .keyboardShortcut("n", modifiers: [.command, .option])
            
            Divider()
            Button("Open Command Bar") {
                let currentURL = browserManager.tabs.activeWindowSession?.url.absoluteString ?? ""
                windowRegistry.activeWindow?.commandPalette?.open(prefill: currentURL, navigateCurrentTab: true)
            }
            .modifier(dynamicShortcut(.focusAddressBar))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Divider()
            Button("Save Page As…") { browserManager.savePageAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(browserManager.tabs.activeWindowSession == nil)

            Button("Print…") {
                browserManager.printCurrentPage()
            }
            .modifier(dynamicShortcut(.printPage))
            .disabled(browserManager.tabs.activeWindowSession == nil)
        }

        // Sidebar commands
        CommandGroup(after: .sidebar) {
            Button(windowRegistry.activeWindow?.isSidebarVisible == false ? "Show Sidebar" : "Hide Sidebar") { // FORK: HIG titles
                browserManager.toggleSidebar()
            }
            .modifier(dynamicShortcut(.toggleSidebar))

            Button(windowRegistry.activeWindow?.isSidebarAIChatVisible == true ? "Hide AI Assistant" : "Show AI Assistant") {
                browserManager.toggleAISidebar()
            }
            .modifier(dynamicShortcut(.toggleAIAssistant))
            .disabled(!nookSettings.showAIAssistant)

            Button("Picture in Picture") {
                browserManager.tabs.activeWindowSession?.requestPictureInPicture()
            }
            .modifier(dynamicShortcut(.togglePictureInPicture))
            .disabled(
                browserManager.tabs.activeWindowSession == nil
                    || !(browserManager.tabs.activeWindowSession.map { $0.hasVideoContent || $0.hasPiPActive } ?? false)
            )

            // FORK: the sidebar footer's Library button, also in the menu bar (HIG, Sidebars).
            Button("Show Library") {
                if let window = windowRegistry.activeWindow { LibraryMotion.present(window) }
            }
            .disabled(windowRegistry.activeWindow == nil)

            Divider()

            Button("Collapse All Folders") {
                if let spaceID = windowRegistry.activeWindow?.spaceID {
                    browserManager.tabs.setAllFolders(open: false, space: spaceID)
                }
            }
            .disabled(windowRegistry.activeWindow?.spaceID == nil)

            Button("Expand All Folders") {
                if let spaceID = windowRegistry.activeWindow?.spaceID {
                    browserManager.tabs.setAllFolders(open: true, space: spaceID)
                }
            }
            .modifier(dynamicShortcut(.expandAllFolders))
            .disabled(windowRegistry.activeWindow?.spaceID == nil)

            if tabOrganizerManager.isAvailable {
                Divider()

                Button("Organize Tabs") {
                    if let spaceID = windowRegistry.activeWindow?.spaceID {
                        Task {
                            await tabOrganizerManager.organizeTabs(in: spaceID, using: browserManager.tabs)
                        }
                    }
                }
                .modifier(dynamicShortcut(.organizeTabs))
                .disabled(
                    tabOrganizerManager.isOrganizing
                        || windowRegistry.activeWindow?.spaceID == nil
                )
            }
        }

        // View commands. FORK: in the View menu, as Safari and Dia have them (they sat in Window).
        CommandGroup(after: .toolbar) {
            // FORK: Arc's View items.
            // The app's own settings object: in Commands, @Environment(\.nookSettings) is a separate default copy.
            Button(browserManager.nookSettings?.topBarAddressView == true ? "Hide Toolbar" : "Show Toolbar") {
                browserManager.toggleTopBarAddressView()
            }
            .modifier(dynamicShortcut(.toggleTopBarAddressView))

            Toggle("Show Full URL", isOn: Binding(get: { FullURLDisplay.shared.isOn }, set: { FullURLDisplay.shared.isOn = $0 }))

            Button(browserManager.isPinnedSectionCollapsed ? "Expand Pinned Tabs" : "Collapse Pinned Tabs") {
                browserManager.togglePinnedSection()
            }
            .disabled(windowRegistry.activeWindow?.spaceID == nil)

            Divider()

            Button("Add Split View") { browserManager.addSplitView() }
                .keyboardShortcut("=", modifiers: [.command, .control])
                .disabled(windowRegistry.activeWindow?.selectedItemID == nil)
            Button("Close This Split Pane") { browserManager.closeActiveSplitPane() }
                .disabled(windowRegistry.activeWindow?.split == nil)
            Button("Focus Next Split Pane") { browserManager.focusSplitPane() }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(windowRegistry.activeWindow?.split == nil)
            Button("Focus Previous Split Pane") { browserManager.focusSplitPane() }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(windowRegistry.activeWindow?.split == nil)
            Button("Separate Page from Split View") {
                if let window = windowRegistry.activeWindow { browserManager.separateSplit(in: window) }
            }
            .disabled(windowRegistry.activeWindow?.split == nil)

            Divider()

            Button("Reload Page") {
                browserManager.tabs.activeWindowSession?.refresh()
            }
            .modifier(dynamicShortcut(.refresh))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Button("Stop Loading") {
                browserManager.stopLoadingCurrentPage()
            }
            .modifier(dynamicShortcut(.stopLoading))
            .disabled(browserManager.tabs.activeWindowSession?.isLoading != true)

            Button("Reload with Standard Fingerprinting Protection") {
                browserManager.tabs.activeWindowSession?.reloadWithoutEnhancedFingerprintingProtection()
            }
            .disabled(browserManager.tabs.activeWindowSession?.usesEnhancedFingerprintingProtection != true)

            Button(browserManager.tabs.activeWindowSession?.isTranslated == true ? "Show Original" : "Translate Page") {
                browserManager.tabs.activeWindowSession?.toggleTranslation()
            }
            .disabled(browserManager.tabs.activeWindowSession?.canTranslate != true)

            Divider()

            Button("Zoom In") {
                browserManager.zoomInCurrentTab()
            }
            .modifier(dynamicShortcut(.zoomIn))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Button("Zoom Out") {
                browserManager.zoomOutCurrentTab()
            }
            .modifier(dynamicShortcut(.zoomOut))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Button("Actual Size") {
                browserManager.resetZoomCurrentTab()
            }
            .modifier(dynamicShortcut(.actualSize))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Divider()

            Button("Hard Reload (Ignore Cache)") {
                browserManager.hardReloadCurrentPage()
            }
            .modifier(dynamicShortcut(.hardReload))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Divider()

            Menu("Appearance") {
                // The app's own settings object: in Commands, @Environment(\.nookSettings) is a separate default copy.
                Picker("Appearance", selection: Binding(get: { browserManager.nookSettings?.appearanceMode ?? .system },
                                                        set: { browserManager.nookSettings?.appearanceMode = $0 })) {
                    Text("Automatic").tag(AppearanceMode.system)
                    Text("Light").tag(AppearanceMode.light)
                    Text("Dark").tag(AppearanceMode.dark)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Menu("Developer") {
                Button("Web Inspector") {
                    browserManager.openWebInspector()
                }
                .modifier(dynamicShortcut(.openDevTools))
                .disabled(browserManager.tabs.activeWindowSession == nil)

                if nookSettings.developerModeEnabled {
                    Button("Developer Panel") {
                        browserManager.toggleDevPanel(.console)
                    }
                    .modifier(dynamicShortcut(.openDevPanel))

                    Button("Pick Element") {
                        browserManager.startElementPicker()
                    }
                    .modifier(dynamicShortcut(.pickElement))
                    .disabled(browserManager.tabs.activeWindowSession == nil)
                }
            }
        }

        // FORK: Edit gains Find and the URL copies, where Dia and Safari keep them.
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy URL") {
                browserManager.copyCurrentURL()
            }
            .modifier(dynamicShortcut(.copyCurrentURL))
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Button("Copy URL as Markdown") {
                guard let page = browserManager.tabs.activeWindowSession else { return }
                let title = page.title.replacingOccurrences(of: "]", with: "\\]")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("[\(title)](\(page.url.absoluteString))", forType: .string)
            }
            .disabled(browserManager.tabs.activeWindowSession == nil)

            Button("Copy URL as Quote") { browserManager.copyURLAsQuote() }
                .disabled(browserManager.tabs.activeWindowSession == nil)

            Divider()
            Button("Find in Page…") {
                browserManager.showFindBar()
            }
            .modifier(dynamicShortcut(.findInPage))
            .disabled(browserManager.tabs.activeWindowSession == nil)
        }

        // FORK: Tabs and History menus, as in Dia, built on the existing shortcut actions.
        CommandMenu("Tabs") {
            Button("New Note") { browserManager.newNote() }
                .keyboardShortcut("n", modifiers: [.command, .control])
                .disabled(windowRegistry.activeWindow?.spaceID == nil || windowRegistry.activeWindow?.isIncognito == true)

            Button("New Folder…") {
                if let spaceID = windowRegistry.activeWindow?.spaceID {
                    browserManager.tabs.createFolderForRename(in: .tabs(spaceID: spaceID), after: nil)
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .option, .shift])
            .disabled(windowRegistry.activeWindow?.spaceID == nil || windowRegistry.activeWindow?.isIncognito == true)

            Divider()
            Button("Next Tab") { shortcutManager.executeAction(.nextTab) }
                .modifier(dynamicShortcut(.nextTab))
            Button("Previous Tab") { shortcutManager.executeAction(.previousTab) }
                .modifier(dynamicShortcut(.previousTab))
            Button("Search Tabs…") { windowRegistry.activeWindow?.commandPalette?.open() }
            Button("Reveal Tab in Sidebar") { browserManager.revealSelectedTabInSidebar() }
                .disabled(windowRegistry.activeWindow?.selectedItemID == nil)

            Divider()
            Button(browserManager.pinToggleIsPin == false ? "Unpin Tab" : "Pin Tab") {
                browserManager.togglePinCurrentTab()
            }
            .modifier(dynamicShortcut(.togglePinTab))
            .disabled(browserManager.pinToggleIsPin == nil)

            Button("Duplicate Tab") { shortcutManager.executeAction(.duplicateTab) }
                .modifier(dynamicShortcut(.duplicateTab))
                .disabled(windowRegistry.activeWindow?.selectedItemID == nil)

            Button(browserManager.tabs.activeWindowSession?.isAudioMuted == true ? "Unmute Site" : "Mute Site") {
                browserManager.tabs.activeWindowSession?.toggleMute()
            }
            .modifier(dynamicShortcut(.muteUnmuteAudio))
            .disabled(
                browserManager.tabs.activeWindowSession == nil
                    || browserManager.tabs.activeWindowSession?.hasAudioContent != true)

            Divider()
            Button("Clear Today") { browserManager.clearToday() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(windowRegistry.activeWindow?.spaceID == nil)
            Button("Reset All Tabs in This Space") { browserManager.resetAllTabsInSpace() }
                .disabled(windowRegistry.activeWindow?.spaceID == nil)
        }

        // FORK: Arc's Archive menu: navigation, history and the tab archive.
        CommandMenu("Archive") {
            Button("Go Back") { shortcutManager.executeAction(.goBack) }
                .disabled(browserManager.tabs.activeWindowSession?.canGoBack != true)
            Button("Go Forward") { shortcutManager.executeAction(.goForward) }
                .disabled(browserManager.tabs.activeWindowSession?.canGoForward != true)

            Divider()
            Button("View History") { shortcutManager.executeAction(.viewHistory) }
                .modifier(dynamicShortcut(.viewHistory))
            Button("View Archive…") { browserManager.openLibrary(.archive) }
            Button("Clear Archive…") { browserManager.confirmClearArchive() }
                .disabled(browserManager.tabs.archive.entries.isEmpty)
        }

        // FORK: Arc's Window items.
        CommandGroup(before: .windowArrangement) {
            Button("Merge All Windows") { browserManager.mergeAllWindows() }
                .disabled(!browserManager.canMergeWindows)
            Button(browserManager.isActiveWindowOnTop ? "Don't Stay on Top" : "Stay on Top") { browserManager.toggleStayOnTop() }
                .disabled(windowRegistry.activeWindow == nil)
            Divider()
            Button("Open Library…") { browserManager.openLibrary(.history) }
            Button("View Downloads…") { shortcutManager.executeAction(.viewDownloads) }
                .modifier(dynamicShortcut(.viewDownloads))
            Divider()
        }

        Group {
            CommandMenu("Spaces") {
                // FORK: the sidebar footer's New Space, also in the menu bar (HIG, Sidebars).
                Button("New Space…") {
                    guard let window = windowRegistry.activeWindow, !window.isIncognito else { return }
                    withAnimation(NookDesign.Motion.standard) {
                        window.isSidebarMenuVisible = false
                        window.spaceDraftTheme = .randomPreset()
                    }
                }
                .disabled(windowRegistry.activeWindow?.isIncognito != false)
                Button("Edit Theme…") { browserManager.showSpaceSettings() }
                    .disabled(windowRegistry.activeWindow?.spaceID == nil)
                Button("Manage Spaces…") { browserManager.openLibrary(.spaces) }

                Divider()

                Button("Next Space") {
                    if let window = windowRegistry.activeWindow { browserManager.tabs.selectNextSpace(in: window) }
                }
                .modifier(dynamicShortcut(.nextSpace))

                Button("Previous Space") {
                    if let window = windowRegistry.activeWindow { browserManager.tabs.selectPreviousSpace(in: window) }
                }
                .modifier(dynamicShortcut(.previousSpace))

                if let window = windowRegistry.activeWindow {
                    let spaces = browserManager.tabs.userSpaces(for: window)
                    if !spaces.isEmpty { Divider() }
                    ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                        Button(space.name) {
                            browserManager.tabs.selectSpace(at: index, in: window)
                        }
                        .modifier(spaceShortcut(index))
                    }
                }
            }

            CommandMenu("Privacy") {
                Menu("Clear Cookies") {
                    Button("Clear Cookies for Current Site") {
                        browserManager.clearCurrentPageCookies()
                    }
                    .disabled(browserManager.tabs.activeWindowSession?.url.host == nil)

                    Button("Clear Expired Cookies") {
                        browserManager.clearExpiredCookies()
                    }

                    Divider()

                    Button("Clear All Cookies") {
                        browserManager.clearAllCookies()
                    }

                    Divider()

                    Button("Clear Third-Party Cookies") {
                        browserManager.clearThirdPartyCookies()
                    }

                    Button("Clear High-Risk Cookies") {
                        browserManager.clearHighRiskCookies()
                    }
                }

                Menu("Clear Cache") {
                    Button("Clear Cache for Current Site") {
                        browserManager.clearCurrentPageCache()
                    }
                    .disabled(browserManager.tabs.activeWindowSession?.url.host == nil)

                    Button("Clear Stale Cache") {
                        browserManager.clearStaleCache()
                    }

                    Button("Clear Disk Cache") {
                        browserManager.clearDiskCache()
                    }

                    Button("Clear Memory Cache") {
                        browserManager.clearMemoryCache()
                    }

                    Divider()

                    Button("Clear All Cache") {
                        browserManager.clearAllCache()
                    }

                    Divider()

                    Button("Clear Personal Data Cache") {
                        browserManager.clearPersonalDataCache()
                    }

                    Button("Clear Favicon Cache") {
                        browserManager.clearFaviconCache()
                    }
                }

                Divider()

                Button("Privacy Cleanup") {
                    browserManager.performPrivacyCleanup()
                }

                Button("Clear Browsing History") {
                    browserManager.historyManager.clearHistory()
                }

                Button("Clear All Website Data") {
                    Task {
                        // Tabs use one store per space; Peek and the base config have used the default.
                        let tabs = browserManager.tabs
                        let dataStores: [WKWebsiteDataStore] = tabs.orderedSpaces.compactMap { tabs.profile(forSpace: $0.id)?.dataStore }
                            + [WKWebsiteDataStore.default()]
                        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
                        for dataStore in dataStores {
                            await dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast)
                        }
                    }
                }
            }

            CommandMenu("Extensions") {
                Button("Show Site Controls") {
                    browserManager.toggleExtensionLibrary()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Divider()

                Button("Install Extension…") {
                    browserManager.showExtensionInstallDialog()
                }
                .modifier(dynamicShortcut(.installExtension))

                Button("Manage Extensions…") {
                    SettingsNavigation.shared.currentSettingsTab = .extensions
                    openSettings()
                }

                Divider()

                Button("Chrome Web Store") {
                    browserManager.tabs.activeWindowSession?.load(URL(string: "https://chromewebstore.google.com")!)
                }

                #if DEBUG
                Divider()
                Button("Open Popup Console") {
                    browserManager.extensionManager?.showPopupConsole()
                }
                #endif
            }

            CommandMenu("Appearance") {
                Button("Space Settings…") {
                    browserManager.showSpaceSettings()
                }
                .modifier(dynamicShortcut(.customizeSpaceGradient))
                .disabled(windowRegistry.activeWindow?.spaceID == nil)

                Button("Boost This Site…") {
                    browserManager.boostCurrentSite()
                }
                .disabled(browserManager.tabs.activeWindowSession == nil)
            }
        }
    }
}

// MARK: - Dynamic Shortcut Modifier

/// View modifier that conditionally applies a keyboard shortcut based on user preferences
struct DynamicShortcutModifier: ViewModifier {
    let keyEquivalent: KeyEquivalent?
    let modifiers: EventModifiers

    func body(content: Content) -> some View {
        if let keyEquivalent = keyEquivalent {
            content.keyboardShortcut(keyEquivalent, modifiers: modifiers)
        } else {
            content
        }
    }
}
