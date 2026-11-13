// Licensed under GPL-3.0. See LICENSE.
//
//  General.swift
//  Nook
//
//  Created by Maciek Bagiński on 07/12/2025.
//

import SwiftUI
import NookDesign
import NookSettings
import NookWeb

public struct SettingsGeneralTab: View {
    @Environment(TabsController.self) private var tabs
    @Environment(NookSettingsService.self) var nookSettings
    @State private var showingAddSite = false
    @State private var showingAddEngine = false
    /// The Site Search row picked for the − button.
    @State private var selectedSite: UUID?

    public init() {}

    /// The provider list, shared by both platforms' spellings of the row.
    @ViewBuilder
    private func searchEnginePicker(_ settings: NookSettingsService) -> some View {
        @Bindable var settings = settings
        Picker("Default search engine", selection: $settings.searchEngineId) {
            ForEach(SearchProvider.allCases) { provider in
                Text(provider.displayName).tag(provider.rawValue)
            }
            ForEach(nookSettings.customSearchEngines) { engine in
                Text(engine.name).tag(engine.id.uuidString)
            }
        }
    }

    public var body: some View {
        @Bindable var settings = nookSettings
        Form {
            SettingsHero(symbol: "gearshape", title: "General", detail: "Search engine, tabs, startup and how Vega performs.")

            Section {
                #if os(macOS)
                LabeledContent("Default search engine") {
                    HStack(spacing: NookDesign.Spacing.md) {
                        searchEnginePicker(settings)
                            .labelsHidden()

                        Button {
                            showingAddEngine = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                #else
                // A picker inside a LabeledContent's trailing slot gets squeezed
                // to "G...gle" at phone width. The Form's own picker row does not,
                // so the add button takes a row of its own.
                searchEnginePicker(settings)
                Button("Add Search Engine…") { showingAddEngine = true }
                #endif

                if let selected = nookSettings.customSearchEngines.first(where: { $0.id.uuidString == nookSettings.searchEngineId }) {
                    LabeledContent {
                        Button("Remove") {
                            nookSettings.customSearchEngines.removeAll { $0.id == selected.id }
                            nookSettings.searchEngineId = SearchProvider.google.rawValue
                        }
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                    } label: {
                        Text(selected.name)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Search")
            }

            #if os(macOS)
            SyncSection()
            #endif

            // FORK: grouped by what they are about, most-used first: search, tabs, startup, performance.
            Section {
                Toggle("Nest tabs opened from links", isOn: $settings.nestTabsFromLinks)
                #if os(macOS)
                Toggle("Keep videos playing in the sidebar", isOn: $settings.autoPictureInPicture)
                #endif
                Picker("Archive tabs after", selection: $settings.archiveAfter) {
                    Text("12 hours").tag(12)
                    Text("24 hours").tag(24)
                    Text("7 days").tag(168)
                    Text("30 days").tag(720)
                    Text("Never").tag(0)
                }
            } header: {
                Text("Tabs")
            } footer: {
                Text("A link's tab sits under the page that opened it. A video left playing moves into a small window above the sidebar controls. Tabs you haven't opened in the archive time move to the Archive; pinned tabs and favorites stay put.")
            }

            Section {
                Picker("On Startup", selection: Binding(
                    get: { nookSettings.startupLoadMode },
                    set: { nookSettings.startupLoadMode = $0 }
                )) {
                    ForEach(StartupLoadMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                #if os(macOS)
                // Quitting and Sparkle updates are both macOS-only concepts.
                Toggle("Warn before quitting Vega", isOn: $settings.askBeforeQuit)
                #endif
            } header: {
                Text("Startup")
            } footer: {
                Text(nookSettings.startupLoadMode.description)
            }

            Section {
                Picker("Tab Management", selection: Binding(
                    get: { nookSettings.tabManagementMode },
                    set: { nookSettings.tabManagementMode = $0 }
                )) {
                    ForEach(TabManagementMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Button("Unload All Inactive Tabs") {
                    tabs.unloadAllHidden()
                }
            } header: {
                Text("Performance")
            } footer: {
                Text(nookSettings.tabManagementMode.description)
            }

            // FORK: System Settings' editable list: plain rows you select, and one + / − bar under
            // them, in place of a red minus button on every row.
            Section {
                ForEach(nookSettings.siteSearchEntries) { entry in
                    HStack(spacing: NookDesign.Spacing.md) {
                        Circle()
                            .fill(entry.color)
                            .frame(width: NookDesign.Size.statusDot, height: NookDesign.Size.statusDot)
                        Text(entry.name)
                        Spacer()
                        Text(entry.domain)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, NookDesign.Spacing.sm)
                    .padding(.vertical, NookDesign.Spacing.xs)
                    .background(
                        NookDesign.Radius.shape(NookDesign.Radius.sm)
                            .fill(selectedSite == entry.id ? Color.accentColor.opacity(0.25) : .clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedSite = selectedSite == entry.id ? nil : entry.id }
                    .accessibilityAddTraits(selectedSite == entry.id ? [.isButton, .isSelected] : .isButton)
                }

                HStack(spacing: NookDesign.Spacing.sm) {
                    Button { showingAddSite = true } label: { Image(systemName: "plus") }
                        .help("Add Site")
                        .accessibilityLabel("Add Site")
                    Button {
                        if let id = selectedSite {
                            nookSettings.siteSearchEntries.removeAll { $0.id == id }
                            selectedSite = nil
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(selectedSite == nil)
                        .help("Remove Site")
                        .accessibilityLabel("Remove Site")
                    Spacer()
                    Button("Reset to Defaults") {
                        nookSettings.siteSearchEntries = SiteSearchEntry.defaultSites
                        selectedSite = nil
                    }
                }
                .buttonStyle(.bordered)
            } header: {
                Text("Site Search")
            } footer: {
                Text("Type a prefix in the command palette and press Tab to search a site directly.")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddSite) {
            SiteSearchEntryEditor(entry: nil) { newEntry in
                nookSettings.siteSearchEntries.append(newEntry)
            }
        }
        .sheet(isPresented: $showingAddEngine) {
            CustomSearchEngineEditor { newEngine in
                nookSettings.customSearchEngines.append(newEngine)
            }
        }
    }
}

// MARK: - Custom Search Engine Editor

struct CustomSearchEngineEditor: View {
    let onSave: (CustomSearchEngine) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var urlTemplate: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.xl) {
            Text("Add Custom Search Engine")
                .font(NookDesign.Font.heading)

            Form {
                Section {
                    TextField("Name (e.g. Startpage)", text: $name)
                    TextField("URL Template (use %@ for query)", text: $urlTemplate)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") {
                    let engine = CustomSearchEngine(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        urlTemplate: urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    onSave(engine)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || urlTemplate.isEmpty)
            }
        }
        .padding(NookDesign.Spacing.xxl)
        .frame(width: NookDesign.Size.sheetSmallWidth)
    }
}

#if os(macOS)
/// FORK: spaces, favorites and pinned tabs shared between your Macs through iCloud Drive.
private struct SyncSection: View {
    @State private var sync = SyncCoordinator.shared

    private var detail: String {
        switch sync.status {
        case .off: return "Keeps spaces, favorites and pinned tabs the same on your Macs. Open tabs stay on each Mac."
        case .noICloudDrive: return "Turn on iCloud Drive in System Settings › Apple Account › iCloud, then try again."
        case .syncing: return "Syncing…"
        case .idle(let last, let others, let waiting):
            let found = others == 0 ? "No other Mac found yet" : "\(others) other \(others == 1 ? "Mac" : "Macs")"
            return "\(found) · synced \(last.formatted(.relative(presentation: .named)))"
                + (waiting > 0 ? " · waiting for iCloud to download \(waiting) \(waiting == 1 ? "file" : "files")" : "")
        case .failed(let message): return "Couldn't sync: \(message)"
        }
    }

    var body: some View {
        Section {
            Toggle("Sync with iCloud Drive", isOn: Binding(get: { sync.isEnabled }, set: { sync.isEnabled = $0 }))
            if sync.isEnabled {
                HStack {
                    Text(detail)
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Sync Now") { sync.syncNow() }
                        .disabled(sync.status == .syncing || sync.status == .noICloudDrive)
                }
            }
        } header: {
            Text("Sync")
        } footer: {
            if !sync.isEnabled { Text(detail) }
        }
    }
}
#endif
