// Licensed under GPL-3.0. See LICENSE.
//
//  Spaces.swift
//  Nook
//
//  Spaces and profiles. A profile is the spaces sharing one login context (cookies, site data,
//  history), so its data is inspected and cleared here too.
//

import NookTabsCore
import SwiftUI
#if os(macOS)
import AppKit
#endif
import NookDesign
import NookWeb

private extension ProfileSummary {
    var rowKey: String { "profile-\(id.uuidString)" }
}

public struct SpacesSettingsView: View {
    @Environment(TabsController.self) private var tabs
    @Environment(\.tabActions) private var actions

    /// Data size per profile, filled in as each store answers.
    @State private var stats: [UUID: String] = [:]
    /// The profile whose details sheet is open.
    @State private var detailsFor: UUID?
    /// The space being renamed and the name typed so far.
    @State private var renamingSpace: (id: UUID, name: String)?
    @State private var showAccentPickerFor: UUID?
    @State private var showIconPickerFor: UUID?
    /// A move that would leave its profile empty, waiting on confirmation.
    @State private var pendingMove: (space: UUID, to: UUID?, profile: String)?

    public init() {}

    private var spaces: [SpaceRecord] { tabs.orderedSpaces.filter { !$0.isAgent } }

    public var body: some View {
        Form {
            SettingsHero(symbol: "square.on.square", title: "Spaces", detail: "Each profile keeps its own logins, cookies and history. Spaces in a profile share them.")

            Section {
                // A profile's id is its first space's id; keyed alike, the two rows collided and this
                // section lost its card. Profile rows get their own keys.
                ForEach(tabs.profiles, id: \.rowKey) { profile in
                    profileRow(profile)
                }
            } header: {
                Text("Profiles")
            }

            Section {
                // The Agent space keeps its look and borrows another space's data, so it has no row.
                ForEach(spaces) { space in
                    row(space)
                }
            } header: {
                Text("Spaces")
            } footer: {
                Text("Each space belongs to a profile. Moving a space to another profile signs it in as that profile.")
            }

            Section {
                Button("New Space…", systemImage: "plus", action: showCreateDialog)
            }
        }
        .formStyle(.grouped)
        .task(id: tabs.profiles.map(\.id)) { await refreshStats() }
        // System Settings' pattern: the ⓘ button opens a sheet with the profile's details and actions.
        .sheet(isPresented: Binding(get: { detailsFor != nil }, set: { if !$0 { detailsFor = nil } })) {
            if let id = detailsFor, let profile = tabs.profiles.first(where: { $0.id == id }) {
                ProfileDetailsSheet(
                    profile: profile,
                    spaceNames: profile.spaceIDs.compactMap { tabs.space($0)?.name },
                    dataSize: stats[profile.id],
                    rename: { tabs.renameProfile(profile.id, to: $0) },
                    clearData: { Task { await clearData(profile) } },
                    done: { detailsFor = nil }
                )
            }
        }
        .alert("Rename Space", isPresented: Binding(get: { renamingSpace != nil }, set: { if !$0 { renamingSpace = nil } })) {
            TextField("Name", text: Binding(get: { renamingSpace?.name ?? "" }, set: { renamingSpace?.name = $0 }))
            Button("Rename") {
                if let renamingSpace, !renamingSpace.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    tabs.updateSpace(renamingSpace.id, name: renamingSpace.name, icon: nil, accentHex: nil)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Delete the \u{201C}\(pendingMove?.profile ?? "")\u{201D} profile?",
            isPresented: Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } })
        ) {
            Button("Move and Delete Profile", role: .destructive) {
                if let move = pendingMove { tabs.setProfile(move.space, to: move.to) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No other space uses it. Its logins, cookies and history will be deleted.")
        }
    }

    /// A profile as System Settings draws an account: avatar, name, a quiet summary, and ⓘ.
    private func profileRow(_ profile: ProfileSummary) -> some View {
        let count = profile.spaceIDs.count
        return HStack(spacing: NookDesign.Spacing.lg) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 28))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(profile.name)
                    .font(NookDesign.Font.body)
                Text("\(count) \(count == 1 ? "space" : "spaces")")
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                detailsFor = profile.id
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Profile Details")
            .accessibilityLabel("Details for \(profile.name)")
        }
        .padding(.vertical, NookDesign.Spacing.xs)
    }

    private func profilePicker(_ space: SpaceRecord) -> some View {
        let current = tabs.profiles.first { $0.spaceIDs.contains(space.id) }
        // A nil selection is "New Profile"; every space is always in some profile.
        return Picker("Profile", selection: Binding<UUID?>(
            get: { current?.id },
            set: { move(space.id, to: $0, from: current) }
        )) {
            ForEach(tabs.profiles) { profile in
                Text(profile.name).tag(UUID?.some(profile.id))
            }
            Divider()
            Text("New Profile").tag(UUID?.none)
        }
        .labelsHidden()
        .accessibilityLabel("Profile")
        .fixedSize()
    }

    private func move(_ spaceID: UUID, to storeID: UUID?, from current: ProfileSummary?) {
        guard storeID != current?.id else { return }
        if let current, current.spaceIDs == [spaceID] {
            pendingMove = (spaceID, storeID, current.name)
        } else {
            tabs.setProfile(spaceID, to: storeID)
        }
    }

    @ViewBuilder
    private func row(_ space: SpaceRecord) -> some View {
        HStack(spacing: NookDesign.Spacing.md) {
            Button {
                showAccentPickerFor = space.id
            } label: {
                Circle()
                    .fill(space.accentColor)
                    .frame(width: NookDesign.Size.iconButton, height: NookDesign.Size.iconButton)
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(
                get: { showAccentPickerFor == space.id },
                set: { if !$0 { showAccentPickerFor = nil } }
            )) {
                SpaceAccentPicker(selectedHex: Binding(
                    get: { space.accentHex },
                    set: { tabs.updateSpace(space.id, name: nil, icon: nil, accentHex: $0) }
                ))
                .padding(NookDesign.Spacing.lg)
            }

            Button { showIconPickerFor = space.id } label: {
                SpaceIcon(space.icon)
                    .frame(width: NookDesign.Size.spaceTarget, height: NookDesign.Size.spaceTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change Icon or Emoji…")
            .accessibilityLabel("Space icon for \(space.name)")
            .popover(isPresented: Binding(
                get: { showIconPickerFor == space.id },
                set: { if !$0 { showIconPickerFor = nil } }
            )) {
                SpaceIconPicker(icon: Binding(
                    get: { tabs.space(space.id)?.icon ?? space.icon },
                    set: { tabs.updateSpace(space.id, name: nil, icon: $0, accentHex: nil) }
                ), onSelect: { showIconPickerFor = nil })
            }

            // FORK: the name as text, renamed from the menu. A live field took focus when the page
            // opened, with its text selected, and the next keys typed anywhere replaced the name.
            Text(space.name)
                .font(NookDesign.Font.body)
            Spacer()
            profilePicker(space)
            Menu {
                Button("Rename…", systemImage: "pencil") {
                    renamingSpace = (space.id, space.name)
                }
                if spaces.count > 1 {
                    Divider()
                    Button("Delete Space…", systemImage: "trash", role: .destructive) {
                        showDeleteDialog(space)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            // FORK: System Settings' row menu: a round "…" button with no disclosure arrow.
            .menuStyle(.button)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More for \(space.name)")
        }
    }

    // MARK: - Data

    private func refreshStats() async {
        for summary in tabs.profiles {
            guard let space = summary.spaceIDs.first, let profile = tabs.profile(forSpace: space) else { continue }
            await profile.refreshDataStoreStats()
            stats[summary.id] = profile.estimatedDataSize
        }
    }

    private func clearData(_ summary: ProfileSummary) async {
        guard let space = summary.spaceIDs.first, let profile = tabs.profile(forSpace: space) else { return }
        await profile.clearAllData()
        stats[summary.id] = profile.estimatedDataSize
    }

    // MARK: - Dialogs

    private func showCreateDialog() {
        actions?.presentSpaceCreation { name, accentHex in
            tabs.createSpace(
                name: name.isEmpty ? "New Space" : name,
                icon: "",
                accentHex: accentHex,
                after: tabs.orderedSpaces.last?.id,
                sharingLoginsWith: tabs.windowRegistry.activeWindow?.spaceID ?? tabs.regularWindows.first?.spaceID
            )
        }
    }

    private func showDeleteDialog(_ space: SpaceRecord) {
        actions?.confirmSpaceDeletion(
            spaceName: space.name,
            tabCount: tabs.tabCount(inSpace: space.id),
            isLastSpace: spaces.count <= 1,
            onDelete: { tabs.deleteSpace(space.id) }
        )
    }
}

/// The ⓘ sheet for a profile, laid out like an account sheet in System Settings: an editable name,
/// what uses it, how much it stores, and the destructive action last, behind a confirmation.
private struct ProfileDetailsSheet: View {
    let profile: ProfileSummary
    let spaceNames: [String]
    let dataSize: String?
    let rename: (String) -> Void
    let clearData: () -> Void
    let done: () -> Void

    @State private var name = ""
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: avatar beside the name and a quiet summary, no card.
            HStack(spacing: NookDesign.Spacing.lg) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                    Text(name.isEmpty ? profile.name : name)
                        .font(.system(size: 15, weight: .semibold))
                    Text("Profile")
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, NookDesign.Spacing.xxl)
            .padding(.top, NookDesign.Spacing.xxl)

            Form {
                Section {
                    TextField("Name", text: $name)
                    LabeledContent("Used by") {
                        Text("\(spaceNames.count) \(spaceNames.count == 1 ? "space" : "spaces")")
                            .help(spaceNames.joined(separator: ", "))
                    }
                    // The amount under its label, and the button alone at the trailing edge.
                    HStack(spacing: NookDesign.Spacing.lg) {
                        VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                            Text("Website data")
                            Text(dataSize ?? "Checking…")
                                .font(NookDesign.Font.secondary)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: NookDesign.Spacing.lg)
                        Button("Clear…") { confirmingClear = true }
                    }
                    .padding(.vertical, NookDesign.Spacing.xxs)
                }
            }
            .formStyle(.grouped)
            // The sheet's own background behind the group, not a second, darker band.
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: 190)

            HStack {
                Spacer()
                Button("Done") { commit(); done() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, NookDesign.Spacing.xxl)
            .padding(.bottom, NookDesign.Spacing.xl)
        }
        .frame(width: 460)
        .onAppear {
            name = profile.name
            #if os(macOS)
            // A sheet focuses its first field with the text selected; leave it unfocused until clicked.
            DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
            #endif
        }
        .confirmationDialog("Clear website data for \u{201C}\(profile.name)\u{201D}?", isPresented: $confirmingClear) {
            Button("Clear Website Data", role: .destructive, action: clearData)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every space in this profile is signed out of all websites. You can't undo this.")
        }
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != profile.name { rename(trimmed) }
    }
}
