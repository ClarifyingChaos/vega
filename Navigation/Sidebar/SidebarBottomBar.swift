// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarBottomBar.swift
//  Nook
//
//  Created by Aether on 15/11/2025.
//

import SwiftUI
import NookDesign
import NookTabsCore
import NookWeb
import NookUI

/// Bottom bar of the sidebar containing menu button, spaces list, and new space button
struct SidebarBottomBar: View {
    @Environment(\.nookSettings) private var nookSettings
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPalette.self) private var commandPalette
    @Binding var isMenuButtonHovered: Bool
    let onMenuTap: () -> Void
    let onNewSpaceTap: () -> Void
    let onMenuHover: (Bool) -> Void
    
    var body: some View {
        // One row, as Arc's dock: library, assistant, the space dots, then create. The dots take
        // what the buttons leave, so adding the assistant button costs them no more than its width.
        HStack(alignment: .center, spacing: NookDesign.SidebarChrome.gap) {
            // Above the space dots, so its hint draws over them.
            menuButton
                .zIndex(1)

            if nookSettings.showAIAssistant {
                Button {
                    browserManager.toggleAISidebar(for: windowState)
                } label: {
                    AnimatedIcon("message-circle", fallback: "message")
                }
                .nookSidebarIconButtons()
                .accessibilityLabel("Toggle AI Assistant")
                .help("Toggle AI Assistant")
            }

            if windowState.isIncognito {
                Spacer(minLength: 0)
            } else {
                SpacesList()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .environmentObject(browserManager)
                    .environment(windowState)

                // Hide new space button in incognito windows
                newSpaceButton
            }
        }
        .frame(height: NookDesign.Size.bottomBar)
        .padding(.horizontal, NookDesign.Spacing.sidebarInset)
    }

    private var menuButton: some View {
        ZStack {
            Button {
                onMenuTap()
            } label: {
                AnimatedIcon("inbox", fallback: "archivebox")
            }
            .accessibilityLabel("Menu")
            .opacity(browserManager.downloadManager.activeDownloads.isEmpty ? 1 : 0)
            .nookSidebarIconButtons()
            .anchorPreference(key: DownloadsButtonAnchorKey.self, value: .bounds) { $0 }
            .onHoverTracking { isHovered in
                isMenuButtonHovered = isHovered
                onMenuHover(isHovered)
            }
            // Arc's hint beside the button: where it leads.
            .overlay(alignment: .leading) {
                if isMenuButtonHovered {
                    Text("View Library")
                        .font(NookDesign.Font.label)
                        .foregroundStyle(.white)
                        .padding(.horizontal, NookDesign.Spacing.md)
                        .frame(height: NookDesign.Size.iconButton)
                        .background(Color.black.opacity(0.85), in: NookDesign.Radius.shape(NookDesign.Radius.md))
                        .fixedSize()
                        .offset(x: NookDesign.SidebarChrome.button + NookDesign.Spacing.xs)
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .offset(x: -4)))
                }
            }
            .animation(NookDesign.Motion.quick, value: isMenuButtonHovered)
            .zIndex(1)

            // Arc: while a file downloads, the ring takes the library icon's place.
            DownloadIndicator()
                .allowsHitTesting(false)
        }
    }
    
    /// Arc's create menu: space and folder, then page tools, then panes and tabs.
    private var newSpaceButton: some View {
        Menu {
            Button("New Space", nookIcon: "plus.square.on.square") {
                onNewSpaceTap()
            }

            Button("New Note", nookIcon: "note.text.badge.plus") {
                browserManager.newNote()
            }

            Button("New Folder", nookIcon: "folder.badge.plus") {
                if let spaceID = windowState.spaceID {
                    tabs.createFolderForRename(in: .tabs(spaceID: spaceID), after: nil)
                }
            }

            Menu {
                ForEach(LiveFolderMenuItem.all, id: \.title) { entry in
                    Button(entry.title, systemImage: entry.symbol) {
                        if let spaceID = windowState.spaceID {
                            tabs.createLiveFolder(entry.source, in: spaceID)
                        }
                    }
                }
                Button("New Feed Folder…", systemImage: "dot.radiowaves.up.forward") {
                    if let spaceID = windowState.spaceID {
                        browserManager.presentFeedFolderPrompt(in: spaceID)
                    }
                }
            } label: {
                Label("New Live Folder", systemImage: "folder.badge.gearshape")
            }

            Divider()

            Button("New Boost", nookIcon: "wand.and.stars") {
                browserManager.openBoostPanel(in: windowState)
            }
            .disabled(!selectedPageIsWeb)

            Divider()

            Button("New Split", nookIcon: "rectangle.split.2x1") {
                if let itemID = tabs.open(url: TabsController.homeURL, in: windowState, placement: .background) {
                    browserManager.splitManager.enterSplit(with: itemID, in: windowState)
                }
            }
            .disabled(windowState.selectedItemID == nil || windowState.split != nil)

            Button("New Tab", nookIcon: "plus.square") {
                commandPalette.open()
            }
        } label: {
            AnimatedIcon("plus-to-x", fallback: "plus", holdWhileHovered: true)
        }
        .menuStyle(.button)
        .nookSidebarIconButtons()
    }

    private var selectedPageIsWeb: Bool {
        guard let url = tabs.selectedSession(in: windowState)?.url else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
}

/// The live folder sources the sidebar's create menus offer, besides feeds.
struct LiveFolderMenuItem {
    let title: String
    let symbol: String
    let source: LiveSource

    static let all = [
        LiveFolderMenuItem(title: "New Pull Requests Folder", symbol: "arrow.triangle.pull", source: .githubPulls),
        LiveFolderMenuItem(title: "New Issues Folder", symbol: "smallcircle.filled.circle", source: .githubIssues),
        LiveFolderMenuItem(title: "New Notifications Folder", symbol: "bell", source: .githubNotifications),
        LiveFolderMenuItem(title: "New Asana Tasks Folder", symbol: "checkmark.circle", source: .asanaTasks),
    ]
}

/// Vega's AI mark from the brand sheet: four pixels around an empty centre, on a 3 x 3 grid.
/// Filled (the centre pixel too) while the chat panel is open. Drawn, not an SF Symbol, so it
/// stays on the pixel grid and takes the button's colour.
struct VegaAIGlyph: View {
    var filled = false

    var body: some View {
        Canvas { context, size in
            let cell = (min(size.width, size.height) / 3).rounded(.down)
            let origin = CGPoint(x: (size.width - cell * 3) / 2, y: (size.height - cell * 3) / 2)
            var cells = [(1, 0), (0, 1), (2, 1), (1, 2)]
            if filled { cells.append((1, 1)) }
            for (x, y) in cells {
                let rect = CGRect(x: origin.x + CGFloat(x) * cell, y: origin.y + CGFloat(y) * cell, width: cell, height: cell)
                context.fill(Path(rect), with: .foreground)
            }
        }
        .frame(width: 13, height: 13)
    }
}
