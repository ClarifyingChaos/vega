// Licensed under GPL-3.0. See LICENSE.
//
//  SettingsFieldStyle.swift
//  Nook
//
//  FORK: the text field Settings uses for API keys, URLs and names: a filled, continuously rounded
//  field, the same surface as the sidebar's search field, in place of AppKit's square bezel.
//

import SwiftUI
import NookDesign

public struct SettingsFieldStyle: TextFieldStyle {
    public init() {}

    public func _body(configuration: TextField<_Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, NookDesign.Spacing.lg)
            .frame(minHeight: 32)
            .nookControlSurface(in: NookDesign.Radius.shape(NookDesign.Radius.md))
    }
}

extension TextFieldStyle where Self == SettingsFieldStyle {
    public static var settings: SettingsFieldStyle { SettingsFieldStyle() }
}
