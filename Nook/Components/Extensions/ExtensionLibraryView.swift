// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionLibraryView.swift
//  Nook
//

import AppKit
import os
import SwiftUI
import WebKit

import NookBlocker
import NookDesign
import NookSettings
import NookWeb
import NookUI

struct ExtensionLibraryView: View {
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let settings: NookSettingsService
    let onDismiss: () -> Void
    let onShowMoreMenu: () -> Void


    private let logger = Logger(subsystem: "com.nook.browser", category: "ExtensionLibrary")

    private var currentTab: PageSession? {
        browserManager.tabs.selectedSession(in: windowState)
    }

    private var currentHost: String? {
        currentTab?.url.host
    }

    /// Only web pages can be Boosted.
    private var boostHost: String? {
        guard let url = currentTab?.url, url.scheme == "http" || url.scheme == "https" else { return nil }
        let host = Boost.normalizeHost(url.host ?? "")
        return host.isEmpty ? nil : host
    }

    private let width: CGFloat = 232
    private let columns = Array(repeating: GridItem(.flexible(), spacing: NookDesign.Spacing.sm), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.lg) {
            actionTiles
            extensionsSection
            settingsSection
            Rectangle().fill(NookDesign.Surface.hairline).frame(height: 1)
            footer
        }
        .padding(NookDesign.Spacing.lg)
        .frame(width: width)
    }

    // MARK: - Actions

    /// Arc's top row: share, Boost, capture, sound.
    private var actionTiles: some View {
        HStack(spacing: NookDesign.Spacing.sm) {
            Menu {
                Button("Copy Link", systemImage: "link") {
                    guard let url = currentTab?.url.absoluteString else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    onDismiss()
                }
                if let url = currentTab?.url {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            } label: {
                ActionTileLabel(systemImage: "square.and.arrow.up")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(ActionTileStyle(solid: true))
            .help("Share")
            .disabled(currentTab == nil)

            Button {
                browserManager.openBoostPanel(in: windowState)
                onDismiss()
            } label: {
                ActionTileLabel(systemImage: "wand.and.sparkles")
            }
            .buttonStyle(ActionTileStyle(solid: true))
            .help("Boost")
            .disabled(boostHost == nil)

            Button {
                onDismiss()
                withAnimation(NookDesign.Motion.spring) { windowState.isPortraitCaptureVisible = true }
            } label: {
                ActionTileLabel(systemImage: "camera")
            }
            .buttonStyle(ActionTileStyle(solid: true))
            .help("Capture")
            .disabled(currentTab == nil)

            MuteButton(tab: currentTab)
        }
    }

    // MARK: - Extensions

    private var extensionsSection: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.sm) {
            Text("Extensions")
                .font(NookDesign.Font.label)
                .foregroundStyle(.secondary)

            let extensions = browserManager.extensionManager?.installedExtensions.filter { $0.isEnabled } ?? []
            LazyVGrid(columns: columns, spacing: NookDesign.Spacing.sm) {
                ForEach(extensions, id: \.id) { ext in
                    ExtensionGridItem(
                        ext: ext,
                        isPinned: settings.pinnedExtensionIDs.contains(ext.id),
                        browserManager: browserManager,
                        windowState: windowState,
                        settings: settings
                    )
                }
                Button(action: openWebStore) {
                    ActionTileLabel(systemImage: "plus", compact: true)
                }
                .buttonStyle(ActionTileStyle())
                .help("Add Extension…")
            }
        }
    }

    // MARK: - Settings

    @State private var contentBlockerEnabled: Bool = true

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.xs) {
            Text("Settings")
                .font(NookDesign.Font.label)
                .foregroundStyle(.secondary)
                .padding(.bottom, NookDesign.Spacing.xxs)

            if let host = currentHost {
                SiteSettingRow(
                    icon: "shield.lefthalf.filled",
                    title: "Content Blocker",
                    subtitle: contentBlockerEnabled ? "On" : "Off for this site",
                    isOn: contentBlockerEnabled
                ) {
                    contentBlockerEnabled.toggle()
                    browserManager.contentBlockerManager.allowDomain(host, allowed: !contentBlockerEnabled)
                }
                .onAppear { contentBlockerEnabled = !browserManager.contentBlockerManager.isDomainAllowed(host) }
                .onChange(of: currentHost) { _, newHost in
                    if let newHost { contentBlockerEnabled = !browserManager.contentBlockerManager.isDomainAllowed(newHost) }
                }

                if let tab = currentTab, tab.enhancedFingerprintingProtectionApplies {
                    SiteSettingRow(
                        icon: "hand.raised.fill",
                        title: "Fingerprinting Protection",
                        subtitle: tab.usesEnhancedFingerprintingProtection ? "Enhanced" : "Standard until you leave this site",
                        isOn: tab.usesEnhancedFingerprintingProtection
                    ) {
                        if tab.usesEnhancedFingerprintingProtection {
                            tab.reloadWithoutEnhancedFingerprintingProtection()
                        } else {
                            tab.reloadWithEnhancedFingerprintingProtection()
                        }
                    }
                }

                // FORK: per-site settings that WebKit applies on the next load (see SitePreferences).
                let site = SitePreferences.shared.prefs(for: host)
                SiteSettingRow(
                    icon: "curlybraces",
                    title: "JavaScript",
                    subtitle: site.javaScript == false ? "Off for this site" : "On",
                    isOn: site.javaScript != false
                ) {
                    SitePreferences.shared.update(host) { $0.javaScript = $0.javaScript == false ? nil : false }
                    currentTab?.refresh()
                }
                SiteSettingRow(
                    icon: "iphone",
                    title: "Mobile Site",
                    subtitle: site.mobileSite == true ? "Requested" : "Off",
                    isOn: site.mobileSite == true
                ) {
                    SitePreferences.shared.update(host) { $0.mobileSite = $0.mobileSite == true ? nil : true }
                    currentTab?.refresh()
                }

                let developer = settings.isDeveloperSite(host)
                SiteSettingRow(
                    icon: "hammer.fill",
                    title: "Developer Mode",
                    subtitle: developer ? "On" : "Off",
                    isOn: developer
                ) {
                    withAnimation(NookDesign.Motion.spring) { settings.setDeveloperSite(host, on: !developer) }
                }
            }

            // FORK: per site when there is one; the global setting only without a page.
            let pipHost = currentHost
            let pipOn = SitePreferences.shared.prefs(for: pipHost).autoPiP ?? settings.autoPictureInPicture
            SiteSettingRow(
                icon: "pip",
                title: "Automatic Picture-in-Picture",
                subtitle: pipOn ? "Allowed" : "Off",
                isOn: pipOn
            ) {
                if let pipHost { SitePreferences.shared.update(pipHost) { $0.autoPiP = !pipOn } }
                else { settings.autoPictureInPicture.toggle() }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        let secure = currentTab?.url.scheme == "https"
        return HStack {
            Label(secure ? "Secure" : "Not Secure", systemImage: secure ? "lock.fill" : "lock.open.fill")
                .font(NookDesign.Font.body)
                .padding(.horizontal, NookDesign.Spacing.md)
                .frame(height: NookDesign.Size.row)
                .background(Color.black.opacity(0.28), in: NookDesign.Radius.shape(NookDesign.Radius.md))
                .help(currentHost ?? "")

            Spacer()

            Menu {
                Button("Clear Cache") { clear(cache: true) }
                    .disabled(currentHost == nil)
                Button("Clear Cookies") { clear(cache: false) }
                    .disabled(currentHost == nil)
                Divider()
                Button("Manage Boosts…") {
                    browserManager.openSettings(tab: .tweaks)
                    onDismiss()
                }
                Button("New Boost…") {
                    browserManager.openBoostPanel(in: windowState)
                    onDismiss()
                }
                .disabled(boostHost == nil)
                Divider()
                Button("Manage Extensions…") {
                    browserManager.openSettings(tab: .extensions)
                    onDismiss()
                }
                Button("Add Extension…", action: openWebStore)
                Divider()
                Button("All Site Settings…", action: onShowMoreMenu)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: NookDesign.Size.spaceIcon, weight: .semibold))
                    .frame(width: NookDesign.Size.iconButton + NookDesign.Spacing.xs,
                           height: NookDesign.Size.iconButton + NookDesign.Spacing.xs)
                    .background(Color.white.opacity(0.2), in: Circle())
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .help("More")
        }
    }

    /// Extensions come from the Chrome Web Store, whose pages get Nook's install button.
    private func openWebStore() {
        browserManager.tabs.open(url: Self.webStoreURL, in: windowState, placement: .newTab)
        onDismiss()
    }

    private static let webStoreURL = URL(string: "https://chromewebstore.google.com/category/extensions")!

    private func clear(cache: Bool) {
        guard let host = currentHost else { return }
        Task {
            if cache {
                await browserManager.cacheManager.clearCacheForDomain(host)
            } else {
                await browserManager.cookieManager.deleteCookiesForDomain(host)
            }
        }
        onDismiss()
    }
}

// MARK: - Tiles

/// Arc's square action tile: a raised dark key with a soft top light, pressing in a touch.
private struct ActionTileStyle: ButtonStyle {
    /// FORK: Arc's top row is near-black keys; the extension tiles stay translucent.
    var solid = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .background {
                NookDesign.Radius.shape(NookDesign.Radius.lg)
                    .fill(solid ? Color.black.opacity(configuration.isPressed || (isHovering && isEnabled) ? 0.78 : 0.62)
                          : Color.white.opacity(configuration.isPressed || (isHovering && isEnabled) ? 0.2 : 0.13))
                    .overlay(alignment: .top) {
                        // The light catching the key's top edge.
                        NookDesign.Radius.shape(NookDesign.Radius.lg)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .top, endPoint: .center))
                    }
            }
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(NookDesign.Motion.quick, value: configuration.isPressed)
            .animation(NookDesign.Motion.hover(isHovering), value: isHovering)
            .onHoverTracking { isHovering = $0 }
    }
}

private struct ActionTileLabel: View {
    let systemImage: String
    var compact = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: compact ? NookDesign.Size.spaceIcon : NookDesign.Size.spaceIcon + 4, weight: .regular))
            .contentTransition(.symbolEffect(.replace))
            .frame(maxWidth: .infinity)
            .frame(height: 34) // FORK: Arc's compact key height (was 44)
    }
}

// MARK: - Mute Button (reactive to tab state)

private struct MuteButton: View {
    let tab: PageSession?

    var body: some View {
        let muted = tab?.isAudioMuted ?? false
        Button {
            tab?.toggleMute()
        } label: {
            ActionTileLabel(systemImage: muted ? "speaker.slash" : "speaker.wave.2")
        }
        .buttonStyle(ActionTileStyle(solid: true))
        .help(muted ? "Unmute" : "Mute")
        .disabled(tab == nil)
    }
}

// MARK: - Extension Grid Item

private struct ExtensionGridItem: View {
    let ext: InstalledExtension
    let isPinned: Bool
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let settings: NookSettingsService

    @State private var isHovering = false
    @State private var badgeText: String?

    private var currentTab: PageSession? {
        browserManager.tabs.selectedSession(in: windowState)
    }

    var body: some View {
        Button {
            triggerExtensionAction()
        } label: {
            Group {
                if let iconPath = ext.iconPath, let nsImage = NSImage(contentsOfFile: iconPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: NookDesign.Size.essentialsFavicon + 2, height: NookDesign.Size.essentialsFavicon + 2)
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .font(NookDesign.Font.title)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: NookDesign.Size.essentialsTile)
            .overlay(alignment: .topTrailing) {
                if let badge = badgeText, !badge.isEmpty {
                    Text(badge)
                        .font(NookDesign.Font.micro)
                        .foregroundStyle(.white)
                        .padding(.horizontal, NookDesign.Spacing.xs)
                        .padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                        .padding(NookDesign.Spacing.xs)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(NookDesign.Font.micro)
                        .foregroundStyle(.secondary)
                        .padding(NookDesign.Spacing.xs)
                }
            }
        }
        .buttonStyle(ActionTileStyle())
        .help(ext.name)
        .onHoverTracking { isHovering = $0 }
        .onAppear { refreshBadge() }
        .extensionContextMenu(for: ext, browserManager: browserManager)
        .accessibilityLabel(ext.name)
        .accessibilityHint("Extension. Double-tap to activate.")
        .accessibilityAddTraits(.isButton)
    }

    private func triggerExtensionAction() {
        guard let ctx = ExtensionManager.shared.getExtensionContext(for: ext.id) else { return }

        if ctx.webExtension.hasBackgroundContent {
            ctx.loadBackgroundContent { error in
                if let error { Logger(subsystem: "com.nook.browser", category: "ExtensionLibrary").error("Background wake failed: \(error.localizedDescription, privacy: .public)") }
            }
        }

        let adapter = ExtensionManager.shared.actionAdapter(in: windowState)
        ExtensionManager.shared.performAction(ctx, for: adapter)
    }

    private func refreshBadge() {
        guard let ctx = ExtensionManager.shared.getExtensionContext(for: ext.id) else {
            badgeText = nil
            return
        }
        let adapter = ExtensionManager.shared.actionAdapter(in: windowState)
        badgeText = ctx.action(for: adapter)?.badgeText
    }
}

// MARK: - Site Setting Row

/// Arc's settings row: a round icon, white when the setting is on, a title and its state.
/// Tapping the row flips it; a row with its own controls passes `action: nil`.
private struct SiteSettingRow<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let isOn: Bool
    let action: (() -> Void)?
    @ViewBuilder let trailing: () -> Trailing

    @State private var isHovering = false
    private let iconSize: CGFloat = 32

    var body: some View {
        HStack(spacing: NookDesign.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: NookDesign.Size.spaceIcon, weight: .semibold))
                // FORK: as in Arc, on is a white circle with a dark glyph; off is a soft gray circle.
                // The panel is always dark, so these are fixed colors, not the appearance's.
                .foregroundStyle(isOn ? Color.black.opacity(0.72) : Color.white)
                .frame(width: iconSize, height: iconSize)
                .background(isOn ? Color.white.opacity(0.94) : Color.white.opacity(0.2), in: Circle())
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(NookDesign.Font.label)
                    .lineLimit(1)
                Text(subtitle)
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, NookDesign.Spacing.xs)
        .padding(.vertical, NookDesign.Spacing.xs)
        .background(isHovering && action != nil ? NookDesign.Surface.fill : .clear, in: NookDesign.Radius.shape(NookDesign.Radius.md))
        .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .onHoverTracking { isHovering = $0 }
        .onTapGesture { withAnimation(NookDesign.Motion.quick) { action?() } }
        .animation(NookDesign.Motion.quick, value: isOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(action == nil ? [] : .isButton)
    }
}

extension SiteSettingRow where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String, isOn: Bool, action: @escaping () -> Void) {
        self.init(icon: icon, title: title, subtitle: subtitle, isOn: isOn, action: action) { EmptyView() }
    }
}
