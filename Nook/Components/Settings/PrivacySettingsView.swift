// Licensed under GPL-3.0. See LICENSE.
//
//  PrivacySettingsView.swift
//  Nook
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import SwiftUI
import NookUI
import WebKit

import NookDesign
import NookSettings
import NookWeb

struct PrivacySettingsView: View {
    @State private var confirmingClearHistory = false
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.nookSettings) var nookSettings
    @Environment(\.showSettingsSubPane) private var showSettingsSubPane
    @ObservedObject var cookieManager: CookieManager
    @ObservedObject var cacheManager: CacheManager
    @State private var isClearing = false

    init(cookieManager: CookieManager, cacheManager: CacheManager) {
        self.cookieManager = cookieManager
        self.cacheManager = cacheManager
    }

    var body: some View {
        @Bindable var settings = nookSettings

        Form {
            SettingsHero(symbol: "lock.shield", title: "Privacy", detail: "Tracking protection, history and the data websites store.")

            Section("Tracking") {
                scopePicker(
                    "Enhanced fingerprinting protection",
                    detail: "Makes it harder for sites to recognize your Mac. If a site breaks, turn it off in Site Controls.",
                    selection: $settings.enhancedFingerprintingProtection
                )
                scopePicker(
                    "Remove tracking from links",
                    detail: "Strips tracking added to links you open.",
                    selection: $settings.removeTrackingFromLinks
                )
                .onChange(of: nookSettings.removeTrackingFromLinks) {
                    browserManager.contentBlockerManager.prepareLinkCleaning()
                }
            }

            Section("Security") {
                settingToggle(
                    "Warn before opening a site over HTTP",
                    detail: "Vega tries HTTPS first. Asks before opening a site that only works over HTTP.",
                    isOn: $settings.warnBeforeHTTP
                )
            }

            Section("History") {
                settingToggle(
                    "Search page text in history",
                    detail: "Lets history search find words inside pages. Private windows and password pages are skipped.",
                    isOn: $settings.searchPageTextInHistory
                )
                .onChange(of: nookSettings.searchPageTextInHistory) { _, enabled in
                    if !enabled { browserManager.historyManager.erasePageText() }
                }
            }

            Section {
                cookiesRow
                cacheRow
                HStack {
                    Text("Browsing history")
                    Spacer()
                    Button("Clear History…") { confirmingClearHistory = true }
                }
            } header: {
                HStack(spacing: NookDesign.Spacing.md) {
                    Text("Website Data")
                    if isClearing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear your browsing history?", isPresented: $confirmingClearHistory) {
            Button("Clear History", role: .destructive, action: clearBrowsingHistory)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every page you visited is removed from history in all spaces. You can't undo this.")
        }
        .onAppear {
            Task {
                await cookieManager.loadCookies()
                await cacheManager.loadCacheData()
            }
        }
    }

    private func settingToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            settingLabel(title, detail: detail)
        }
    }

    private func scopePicker(_ title: String, detail: String, selection: Binding<ProtectionScope>) -> some View {
        LabeledContent {
            // Hidden copies hold the widest option's width, so the text beside it doesn't reflow.
            ZStack(alignment: .trailing) {
                ForEach(ProtectionScope.allCases) { scope in
                    scopeMenu(title, selection: .constant(scope))
                        .hidden()
                }
                scopeMenu(title, selection: selection)
            }
            .fixedSize()
        } label: {
            settingLabel(title, detail: detail)
        }
    }

    private func scopeMenu(_ title: String, selection: Binding<ProtectionScope>) -> some View {
        Picker(title, selection: selection) {
            ForEach(ProtectionScope.allCases) { scope in
                Text(scope.displayName).tag(scope)
            }
        }
        .labelsHidden()
    }

    private func settingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
            Text(title)
            Text(detail)
                .font(NookDesign.Font.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Website Data Rows

    private var cookiesRow: some View {
        let stats = cookieManager.getCookieStats()
        return websiteDataRow(
            "Cookies",
            summary: stats.total == 0 ? "None" : "\(stats.total.formatted()) cookies · \(formatSize(stats.totalSize))",
            manage: .cookies
        ) {
            Button("Clear Expired Cookies") {
                clearExpiredCookies()
            }
            Button("Clear Third-Party Cookies") {
                clearThirdPartyCookies()
            }
            Button("Clear High-Risk Cookies") {
                clearHighRiskCookies()
            }
            Divider()
            Button("Clear All Cookies") {
                clearAllCookies()
            }
            Button("Privacy Cleanup") {
                performCookiePrivacyCleanup()
            }
            Divider()
            Button("Clear All Website Data", role: .destructive) {
                clearAllWebsiteData()
            }
        }
    }

    private var cacheRow: some View {
        let stats = cacheManager.getCacheStats()
        return websiteDataRow(
            "Cache",
            summary: stats.total == 0 ? "None" : "\(stats.total == 1 ? "1 site" : "\(stats.total.formatted()) sites") · \(formatSize(stats.totalSize))",
            manage: .cache
        ) {
            Button("Clear Stale Cache") {
                clearStaleCache()
            }
            Button("Clear Personal Data Cache") {
                clearPersonalDataCache()
            }
            Button("Clear Disk Cache") {
                clearDiskCache()
            }
            Button("Clear Memory Cache") {
                clearMemoryCache()
            }
            Divider()
            Button("Privacy Cleanup") {
                performCachePrivacyCleanup()
            }
            Divider()
            Button("Clear All Cache", role: .destructive) {
                clearAllCache()
            }
        }
    }

    /// System Settings' row: the name with a one-line summary, Clear at the trailing edge, and a
    /// chevron to the detail list. FORK: replaces a four-column stats grid and a 7 pt chevron.
    private func websiteDataRow<ClearItems: View>(
        _ title: String,
        summary: String,
        manage: SettingsSubPane,
        @ViewBuilder clearItems: () -> ClearItems
    ) -> some View {
        HStack(alignment: .center, spacing: NookDesign.Spacing.lg) {
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(title)
                Text(summary)
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu("Clear", content: clearItems)
                .menuStyle(.button)
                .fixedSize()
                .disabled(isClearing)
            NookSymbol("chevron.right", size: 16)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, NookDesign.Spacing.xxs)
        .contentShape(Rectangle())
        .onTapGesture { showSettingsSubPane(manage) }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows \(title.lowercased()) by site")
    }

    private func clearExpiredCookies() {
        isClearing = true
        Task {
            await cookieManager.deleteExpiredCookies()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearAllCookies() {
        isClearing = true
        Task {
            await cookieManager.deleteAllCookies()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearAllWebsiteData() {
        isClearing = true
        Task {
            await removeWebsiteData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
            await cookieManager.loadCookies()
            await cacheManager.loadCacheData()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearBrowsingHistory() {
        browserManager.historyManager.clearHistory()
    }

    /// Tabs use one store per space; Peek and the base config have used the default.
    @MainActor
    private func removeWebsiteData(ofTypes dataTypes: Set<String>) async {
        let tabs = browserManager.tabs
        let dataStores: [WKWebsiteDataStore] = tabs.orderedSpaces.compactMap { tabs.profile(forSpace: $0.id)?.dataStore }
            + [WKWebsiteDataStore.default()]
        for dataStore in dataStores {
            await dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast)
        }
    }
    
        
    // MARK: - Helper Methods
    
    // MARK: - Cache Action Methods
    
    private func clearStaleCache() {
        isClearing = true
        Task {
            await cacheManager.clearStaleCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearDiskCache() {
        isClearing = true
        Task {
            await cacheManager.clearDiskCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearMemoryCache() {
        isClearing = true
        Task {
            await cacheManager.clearMemoryCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearAllCache() {
        isClearing = true
        Task {
            await removeWebsiteData(ofTypes: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache])
            await cacheManager.clearAllCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    // MARK: - Privacy-Compliant Actions
    
    private func clearThirdPartyCookies() {
        isClearing = true
        Task {
            await cookieManager.deleteThirdPartyCookies()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearHighRiskCookies() {
        isClearing = true
        Task {
            await cookieManager.deleteHighRiskCookies()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func performCookiePrivacyCleanup() {
        isClearing = true
        Task {
            await cookieManager.performPrivacyCleanup()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func clearPersonalDataCache() {
        isClearing = true
        Task {
            await cacheManager.clearPersonalDataCache()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func performCachePrivacyCleanup() {
        isClearing = true
        Task {
            await cacheManager.performPrivacyCompliantCleanup()
            await MainActor.run {
                isClearing = false
            }
        }
    }
    
    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) bytes"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    PrivacySettingsView(cookieManager: CookieManager(), cacheManager: CacheManager())
        .environmentObject(BrowserManager(settings: NookSettingsService(), windowRegistry: WindowRegistry()))
}
