// Licensed under GPL-3.0. See LICENSE.
//
//  SettingsWindow.swift
//  Nook
//
//  Created by Bain Gurley on 26/03/2026.
//

import SwiftUI
import NookDesign
import NookUI

struct SettingsWindow: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @Environment(\.nookSettings) var nookSettings

    private let windowSize = CGSize(width: 860, height: 600)
    @State private var query = ""

    // Back/forward walk every place visited, sidebar picks and sub-pane pushes alike.
    @State private var paths: [SettingsTabs: [SettingsSubPane]] = [:]
    @State private var back: [SettingsLocation] = []
    @State private var forward: [SettingsLocation] = []
    @State private var restoring = false

    private var location: SettingsLocation {
        let tab = SettingsNavigation.shared.currentSettingsTab
        return SettingsLocation(tab: tab, path: paths[tab] ?? [])
    }

    var body: some View {
        let navigation = SettingsNavigation.shared
        let tab = navigation.currentSettingsTab
        // A sidebar pick lands on the tab's root, like System Settings.
        let selection = Binding(
            get: { navigation.currentSettingsTab },
            set: { paths[$0] = []; navigation.currentSettingsTab = $0 }
        )
        // FORK: System Settings (macOS 27): the native split view, whose sidebar is the glass panel
        // with the capsule search field, monochrome symbols and the blue selection.
        NavigationSplitView {
            SettingsSidebar(selection: selection, query: $query)
                .navigationSplitViewColumnWidth(min: 232, ideal: 232, max: 280)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsDetailPane(
                tab: tab,
                path: Binding(get: { paths[tab] ?? [] }, set: { paths[tab] = $0 }),
                history: HistoryToolbar(
                    canGoBack: !back.isEmpty,
                    canGoForward: !forward.isEmpty,
                    goBack: { go(from: &back, to: &forward) },
                    goForward: { go(from: &forward, to: &back) }
                )
            )
            .environmentObject(browserManager)
            .environmentObject(gradientColorManager)
            // Rebuilds the pane per tab so each opens scrolled to the top.
            .id(tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: location) { old, _ in
            if restoring { restoring = false; return }
            // A fresh move abandons the forward history, like a browser.
            back.append(old)
            forward.removeAll()
        }
        // System Settings is resizable and remembers its size; a fixed frame is not.
        .frame(minWidth: windowSize.width, minHeight: windowSize.height)
        .toggleStyle(SettingsSwitch())
        .background(UnifiedToolbarWindow())
    }

    private func go(from stack: inout [SettingsLocation], to other: inout [SettingsLocation]) {
        guard let target = stack.popLast() else { return }
        other.append(location)
        restoring = true
        paths[target.tab] = target.path
        SettingsNavigation.shared.currentSettingsTab = target.tab
    }
}

/// System Settings' switches measure 44x20, which is `.small`; a grouped Form's default
/// renders them at the mini size. Scoped to switches so buttons and pickers stay regular.
private struct SettingsSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

/// One place the window can show: a sidebar tab and whatever is pushed on top of it.
private struct SettingsLocation: Hashable {
    let tab: SettingsTabs
    let path: [SettingsSubPane]
}

/// Both buttons always show, disabled when there is nowhere to go, as standalone icon buttons
/// with the toolbar's glass backing hidden.
private struct HistoryToolbar: ViewModifier {
    let canGoBack: Bool
    let canGoForward: Bool
    let goBack: () -> Void
    let goForward: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        // Branch at the View level: ToolbarContentBuilder's availability erasure fails to link in
        // optimized builds. On 26+, a fixed spacer keeps the capsule clear of the sidebar, as in
        // System Settings; padding on the item only widens its glass.
        if #available(macOS 26, *) {
            content
                .toolbar {
                    // The item's shared glass would grow with any padding, so the capsule draws its
                    // own glass and the 8 pt gap to the sidebar sits outside it, as in System Settings.
                    ToolbarItem(placement: .navigation) {
                        navigationPair
                            .glassEffect(.regular.interactive(), in: .capsule)
                            // The item starts under the sidebar's edge; 14 pt leaves System Settings' 8 pt gap.
                            .padding(.leading, 14)
                            // and 12 pt before the page title, which otherwise runs under the glass.
                            .padding(.trailing, 12)
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
                .toolbar { buttons }
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
    }

    /// System Settings' pair: back and forward joined in one capsule, the page title beside it.
    private var buttons: some ToolbarContent {
        ToolbarItem(placement: .navigation) { navigationPair }
    }

    private var navigationPair: some View {
        ControlGroup {
            Button("Back", systemImage: "chevron.backward", action: goBack)
                .disabled(!canGoBack)
            Button("Forward", systemImage: "chevron.forward", action: goForward)
                .disabled(!canGoForward)
        }
        .controlGroupStyle(.navigation)
    }
}

/// The Settings scene ignores `.windowToolbarStyle` and lays its toolbar out in the old two-row
/// preference style. System Settings' single row (back button, then the title inline, traffic
/// lights 26pt in from the corner) needs the style set on the window itself.
private struct UnifiedToolbarWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // SwiftUI installs the toolbar after the view lands, so wait one turn.
            guard let window else { return }
            DispatchQueue.main.async { window.toolbarStyle = .unified }
        }
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @Binding var selection: SettingsTabs
    @Binding var query: String
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        List(selection: Binding<SettingsTabs?>(get: { selection }, set: { if let tab = $0 { selection = tab } })) {
            ForEach(Array(SettingsTabs.sidebarGroups.enumerated()), id: \.offset) { _, group in
                let tabs = group.tabs.filter { tab in
                    guard tab.matches(query) else { return false }
                    return tab != .extensions || browserManager.extensionManager != nil
                }
                if !tabs.isEmpty {
                    // Untitled sections: the list draws System Settings' gap between groups.
                    Section {
                        ForEach(tabs, id: \.self) { tab in
                            Label {
                                Text(tab.name)
                            } icon: {
                                // macOS 27 System Settings: symbols in the label colour, not the accent.
                                Image(systemName: tab.icon)
                                    .foregroundStyle(.primary)
                            }
                            .tag(tab)
                            .listItemTint(.fixed(Color(nsColor: .labelColor)))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // System Settings' sidebar is 232 pt; the split view otherwise opens it at its narrowest.
        .frame(minWidth: 232)
        .searchable(text: $query, placement: .sidebar, prompt: "Search")
    }
}

// MARK: - Sub-Panes

/// Pages shown in place of a tab's own page. Typed so back/forward can replay them.
enum SettingsSubPane: Hashable {
    case cookies
    case cache

    @MainActor @ViewBuilder
    func view(_ browserManager: BrowserManager) -> some View {
        switch self {
        case .cookies: CookieManagementView(cookieManager: browserManager.cookieManager)
        case .cache: CacheManagementView(cacheManager: browserManager.cacheManager)
        }
    }
}

extension EnvironmentValues {
    @Entry var showSettingsSubPane: (SettingsSubPane) -> Void = { _ in }
}

// MARK: - Detail Pane

private struct SettingsDetailPane: View {
    let tab: SettingsTabs
    @Binding var path: [SettingsSubPane]
    let history: HistoryToolbar
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        NavigationStack {
            Group {
                if let pane = path.last {
                    pane.view(browserManager)
                } else {
                    tabPage
                        // FORK: room to breathe: taller rows on every page.
                        .environment(\.defaultMinListRowHeight, 40)
                    .navigationTitle(tab.name)
                }
            }
            .environment(\.showSettingsSubPane) { path.append($0) }
            // FORK: AppKit focuses a page's first text field, all of it selected, so the next keys
            // typed replaced a space's name. Nothing takes focus until it is clicked, as in System Settings.
            .task(id: tab) {
                try? await Task.sleep(for: .milliseconds(80))
                if let window = NSApp.windows.first(where: { $0.title == tab.name && $0.firstResponder is NSText }) {
                    window.makeFirstResponder(nil)
                }
            }
            .modifier(history)
        }
    }

    @ViewBuilder
    private var tabPage: some View {
        switch tab {
        case .general:
            SettingsGeneralTab()
        case .appearance:
            SettingsAppearanceTab()
        case .ai:
            SettingsAITab()
        case .privacy:
            PrivacySettingsView(
                cookieManager: browserManager.cookieManager,
                cacheManager: browserManager.cacheManager
            )
        case .adBlocker:
            SettingsAdBlockerTab()
        case .tweaks:
            SettingsTweaksTab()
        case .links:
            LinksSettingsView()
        case .spaces:
            SpacesSettingsView()
        case .shortcuts:
            ShortcutsSettingsView()
        case .extensions:
            if let extensionManager = browserManager.extensionManager {
                ExtensionsSettingsView(extensionManager: extensionManager)
            }
        case .developer:
            SettingsDeveloperTab()
        }
    }
}
