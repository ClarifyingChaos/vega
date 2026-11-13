// Licensed under GPL-3.0. See LICENSE.
//
//  PeekOverlayView.swift
//  Nook
//
//  Created by Jonathan Caudill on 24/09/2025.
//

import NookTabsCore
import SwiftUI
import NookDesign
import NookWeb
import AppKit
import NookUI

struct PeekOverlayView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) var windowState
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.nookSettings) var nookSettings

    private var peek: PeekManager { browserManager.peekManager }

    /// Peek belongs to the window that opened it; the others show nothing.
    private var page: PageSession? {
        peek.windowId == windowState.id ? peek.page : nil
    }

    private var currentSpaceColor: Color {
        windowState.spaceID.flatMap { tabs.space($0)?.accentColor } ?? Color.accentColor
    }

    var body: some View {
        ZStack {
            if let page {
                backgroundOverlay
                    .transition(.opacity)
                peekContent(page: page)
                    .transition(.scale(scale: 0.001).combined(with: .opacity))
                    .zIndex(1000)
            }
        }
        .zIndex(9999) // Put it at the very top
        .animation(NookDesign.Motion.spring, value: page?.itemID)
    }

    private var backgroundOverlay: some View {
        Color.black.opacity(0.4)
            .contentShape(Rectangle()) // Ensure proper hit testing
            .onTapGesture { peek.dismissPeek() }
    }

    private func peekContent(page: PageSession) -> some View {
        GeometryReader { geometry in
            let (frame, cornerRadius) = calculateLayout(geometry: geometry)

            ZStack {
                // The card's surface and shadow sit behind the page, never on it: see DetachedPageHost.
                NookDesign.Radius.shape(cornerRadius)
                    .fill(colorScheme == .dark ? Color.black : Color.white)
                    .nookElevation(.floating)

                DetachedPageHost(page: page, cornerRadius: cornerRadius)
                    .id(page.itemID)

                BlockedPageView(session: page)
                TranslationTaskHost(session: page)

                if let webView = page.webView {
                    PageLoadBar(webView: webView, tint: currentSpaceColor)
                        .padding(.horizontal, cornerRadius)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .id(page.itemID)
                }
            }
            .frame(width: frame.width, height: frame.height)
            // The buttons sit in the margin right of the card, level with its top.
            .overlay(alignment: .topTrailing) {
                actionButtons
                    .alignmentGuide(.trailing) { $0[.leading] - NookDesign.Spacing.lg }
            }
            // The site sits in the margin above, where the page cannot draw over it.
            .overlay(alignment: .topLeading) {
                siteLabel(page: page)
                    .environment(\.colorScheme, .dark)
                    .frame(maxWidth: frame.width, alignment: .leading)
                    .alignmentGuide(.top) { $0[.bottom] + NookDesign.Spacing.sm }
            }
            .position(
                x: frame.minX + (frame.width / 2),
                y: geometry.size.height / 2
            )
        }
    }

    // Both pieces float over the dimmed window, which is dark in either appearance: they are drawn
    // as dark glass with white content so they never depend on the colour scheme of what is behind.
    /// The card's site, drawn as the address bar draws it: the URL bar still names the tab under Peek.
    private func siteLabel(page: PageSession) -> some View {
        HStack(spacing: NookDesign.Spacing.xs) {
            if page.url.scheme == "http" {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: NookDesign.Size.rowGlyph, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            // Head truncation keeps the registrable domain: `accounts.google.com.x.evil.tld`.
            Text(page.url.nookDisplayHost ?? page.url.absoluteString)
                .font(NookDesign.Font.secondary)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, NookDesign.Spacing.sm)
        .padding(.vertical, NookDesign.Spacing.xs)
        .nookGlassSurface(in: NookDesign.Radius.shape(NookDesign.Radius.md))
    }

    /// Close, open as a tab and split: round dark-glass buttons beside the card, like the site name.
    private var actionButtons: some View {
        VStack(spacing: NookDesign.Spacing.sm) {
            circleButton("error", fallback: "xmark", help: "Close", action: peek.dismissPeek)
            circleButton("maximize-2", fallback: "arrow.up.left.and.arrow.down.right", help: "Open as a tab", action: peek.moveToNewTab)
            circleButton("columns", fallback: "square.split.2x1", help: "Open in split view", action: peek.moveToSplitView)
                .disabled(!peek.canEnterSplitView)
        }
    }

    private func circleButton(_ animation: String, fallback: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            AnimatedIcon(animation, fallback: fallback, size: 20, ink: .white)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .nookGlassSurface(in: Circle())
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
        .help(help)
        .accessibilityLabel(help)
    }


    // MARK: - Layout Calculation

    private func calculateLayout(geometry: GeometryProxy) -> (frame: CGRect, cornerRadius: CGFloat) {
        let windowSize = geometry.size
        let sidebarPosition = nookSettings.sidebarPosition

        // Compute the visible web content area by excluding the sidebar width
        let sidebarWidth: CGFloat = windowState.isSidebarVisible ? windowState.sidebarWidth : 0
        let webAreaWidth = max(0, windowSize.width - sidebarWidth)

        // 80% of the web area wide and 90% of the window tall, so the page behind stays in view.
        let webViewHeight = windowSize.height * 0.9
        let cornerRadius: CGFloat = NookDesign.Radius.xl

        // Center within the web area (excluding sidebar)
        let peekWidth = webAreaWidth * 0.8
        let peekXWithinWebArea = (webAreaWidth - peekWidth) / 2

        // Calculate peek X position based on sidebar position
        let peekX: CGFloat
        if sidebarPosition == .left {
            // Sidebar on left: peek window starts after sidebar
            peekX = sidebarWidth + peekXWithinWebArea
        } else {
            // Sidebar on right: peek window starts from left edge
            peekX = peekXWithinWebArea
        }


        return (
            frame: CGRect(
                x: peekX,
                y: 0,
                width: peekWidth,
                height: webViewHeight
            ),
            cornerRadius: cornerRadius
        )
    }
}
