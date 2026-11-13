// Licensed under GPL-3.0. See LICENSE.
//
//  SettingsHero.swift
//  Nook
//
//  FORK: the card at the top of a macOS 27 System Settings pane: the pane's symbol in a rounded
//  tile, its name in bold, and one line on what it holds, centred. Each settings page opens with it.
//

import SwiftUI
import NookDesign

public struct SettingsHero: View {
    let symbol: String
    let title: String
    let detail: String
    /// Name of an asset-catalog image shown in place of the symbol tile (Updates uses Vega's logotype).
    let logotype: String?

    public init(symbol: String, title: String, detail: String, logotype: String? = nil) {
        self.logotype = logotype
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        Section {
            VStack(spacing: NookDesign.Spacing.sm) {
                if let logotype {
                    Image(logotype)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.primary)
                        .frame(height: 24)
                        .frame(minHeight: 48)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                        .background(NookDesign.Radius.shape(12).fill(.quaternary))
                        .overlay(NookDesign.Radius.shape(12).strokeBorder(.separator, lineWidth: 0.5))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .padding(.top, NookDesign.Spacing.xxs)
                Text(detail)
                    .font(NookDesign.Font.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, NookDesign.Spacing.lg)
            .accessibilityElement(children: .combine)
        }
    }
}
