// Licensed under GPL-3.0. See LICENSE.
//
//  AdBlocker.swift
//  Nook
//
//  Created by Bain Gurley on 26/03/2026.
//

import SwiftUI

import NookBlocker
import NookDesign
import NookSettings

public struct SettingsAdBlockerTab: View {
    @Environment(NookSettingsService.self) var nookSettings
    @Environment(\.contentBlocker) private var contentBlocker
    @State private var isUpdatingFilters = false

    public init() {}

    public var body: some View {
        @Bindable var settings = nookSettings
        Form {
            SettingsHero(symbol: "shield.lefthalf.filled", title: "Ad Blocker", detail: "Block ads and trackers with the filter lists you choose.")

            // FORK: one group: the switch, then when the lists last updated with Update at the trailing edge.
            Section {
                Toggle("Ad & Tracker Blocker", isOn: $settings.adBlockerEnabled)
                    .onChange(of: nookSettings.adBlockerEnabled) { _, enabled in
                        contentBlocker?.setEnabled(enabled)
                    }
                if nookSettings.adBlockerEnabled {
                    HStack {
                        VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                            Text("Filter lists")
                            Group {
                                if isUpdatingFilters {
                                    Text("Updating…")
                                } else if let lastUpdate = nookSettings.adBlockerLastUpdate {
                                    Text("Updated \(lastUpdate, style: .relative) ago")
                                } else {
                                    Text("Not updated yet")
                                }
                            }
                            .font(NookDesign.Font.secondary)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isUpdatingFilters {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Update Now") {
                                isUpdatingFilters = true
                                Task {
                                    await contentBlocker?.recompileFilterLists()
                                    isUpdatingFilters = false
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text("Filter lists update automatically every 24 hours.")
            }

            if nookSettings.adBlockerEnabled {
                Section("Default Filter Lists") {
                    ForEach(FilterListManager.defaultLists, id: \.filename) { list in
                        LabeledContent {
                            Text(list.category.rawValue)
                                .font(NookDesign.Font.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, NookDesign.Spacing.sm)
                                .padding(.vertical, NookDesign.Spacing.xxs)
                                .background(NookDesign.Surface.fill)
                                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
                        } label: {
                            Label {
                                Text(list.name)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }

                if !FilterListManager.optionalLists.isEmpty {
                    ForEach(FilterListManager.FilterListCategory.allCases, id: \.rawValue) { category in
                        let listsInCategory = FilterListManager.optionalLists.filter { $0.category == category }
                        if !listsInCategory.isEmpty {
                            Section(category.rawValue) {
                                ForEach(listsInCategory, id: \.filename) { list in
                                    Toggle(list.name, isOn: Binding(
                                        get: { nookSettings.enabledOptionalFilterLists.contains(list.filename) },
                                        set: { enabled in
                                            if enabled {
                                                nookSettings.enabledOptionalFilterLists.append(list.filename)
                                            } else {
                                                nookSettings.enabledOptionalFilterLists.removeAll { $0 == list.filename }
                                            }
                                            contentBlocker?.filterListManager.enabledOptionalFilterListFilenames = Set(nookSettings.enabledOptionalFilterLists)
                                            Task {
                                                await contentBlocker?.recompileFilterLists()
                                            }
                                        }
                                    ))
                                }
                            }
                        }
                    }

                    Section {
                        Text("Enabling additional lists improves blocking but increases memory usage.")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
