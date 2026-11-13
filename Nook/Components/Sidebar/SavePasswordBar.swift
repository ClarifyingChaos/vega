// Licensed under GPL-3.0. See LICENSE.
//
//  SavePasswordBar.swift
//  Nook
//
//  FORK: "Save password?" above the sidebar's media controls, like the Cast bar. Shown on the tab
//  where the login happened until the person answers, or after two minutes.
//

import NookDesign
import NookUI
import NookWeb
import SwiftUI

struct SavePasswordBar: View {
    @Environment(BrowserWindowState.self) private var windowState
    @State private var prompter = PasswordPrompter.shared

    var body: some View {
        if let pending = prompter.pending, pending.itemID == windowState.selectedItemID {
            VStack(alignment: .leading, spacing: NookDesign.Spacing.md) {
                HStack(spacing: NookDesign.Spacing.md) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(pending.isUpdate ? "Update password?" : "Save password?")
                            .font(NookDesign.Font.title)
                            .foregroundStyle(.white)
                        Text(pending.username.isEmpty ? pending.host : "\(pending.username) on \(pending.host)")
                            .font(NookDesign.Font.secondary)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: NookDesign.Spacing.sm) {
                    Button("Never") { prompter.neverSavePending() }
                    Button("Not Now") { prompter.dismiss() }
                    Spacer(minLength: 0)
                    Button(pending.isUpdate ? "Update" : "Save") { prompter.savePending() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
            }
            .padding(10)
            .background(NookDesign.Radius.shape(NookDesign.Radius.md).fill(Color.black))
            .overlay(NookDesign.Radius.shape(NookDesign.Radius.md).stroke(Color.white.opacity(0.2), lineWidth: 0.5))
            .padding(.horizontal, NookDesign.Spacing.sidebarInset)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityElement(children: .contain)
        }
    }
}
