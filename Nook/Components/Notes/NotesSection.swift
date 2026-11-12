// Licensed under GPL-3.0. See LICENSE.
//
//  NotesSection.swift
//  Nook
//
//  FORK: the current space's notes as rows above the sidebar's bottom bar. Hidden when the
//  space has none. shortcut: a section of its own, upgrade to rows among the tabs, as in Arc.
//

import SwiftUI
import NookDesign
import NookWeb
import NookUI

struct NotesSection: View {
    @Environment(BrowserWindowState.self) private var windowState
    @State private var store = NoteStore.shared
    @State private var hovered: UUID?

    var body: some View {
        let notes = store.notes(in: windowState.spaceID)
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: NookDesign.Spacing.rowGap) {
                Text("Notes")
                    .font(NookDesign.Font.label)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, NookDesign.Spacing.rowPadding)
                    .padding(.bottom, NookDesign.Spacing.xs)
                ScrollView {
                    VStack(spacing: NookDesign.Spacing.rowGap) {
                        ForEach(notes) { note in row(note) }
                    }
                }
                .scrollIndicators(.hidden)
                // Four rows show; more scroll.
                .frame(maxHeight: CGFloat(min(notes.count, 4)) * (NookDesign.Tab.height + NookDesign.Spacing.rowGap))
            }
            .padding(.horizontal, NookDesign.Spacing.sidebarInset)
        }
    }

    private func row(_ note: Note) -> some View {
        let selected = store.openNote[windowState.id] == note.id
        return Button {
            store.openNote[windowState.id] = note.id
        } label: {
            HStack(spacing: NookDesign.Spacing.md) {
                Image(systemName: "note.text")
                    .font(.system(size: NookDesign.Size.rowGlyph))
                    .foregroundStyle(.secondary)
                    .frame(width: NookDesign.Size.favicon)
                Text(note.displayTitle)
                    .font(NookDesign.Tab.font)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if hovered == note.id {
                    Button("Delete Note", systemImage: "xmark") { confirmDelete(note) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(NookIconButtonStyle(size: NookDesign.Size.rowButton, radius: NookDesign.Radius.sm))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, NookDesign.Spacing.rowPadding)
            .frame(height: NookDesign.Tab.height)
            .nookTabSurface(selected: selected, hovered: hovered == note.id)
            .contentShape(NookDesign.Radius.shape(NookDesign.Tab.radius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? note.id : (hovered == note.id ? nil : hovered) }
        .contextMenu { Button("Delete Note", systemImage: "trash") { confirmDelete(note) } }
        .accessibilityLabel(note.displayTitle)
    }

    private func confirmDelete(_ note: Note) {
        let alert = SystemAlert.make("Delete \u{201C}\(note.displayTitle)\u{201D}?", "This note will be deleted. You can't undo this.",
                                     style: .warning, buttons: ["Delete", "Cancel"])
        alert.buttons.first?.hasDestructiveAction = true
        SystemAlert.present(alert) { response in
            if response == .alertFirstButtonReturn { store.delete(note.id) }
        }
    }
}
