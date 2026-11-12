// Licensed under GPL-3.0. See LICENSE.
//
//  View+Glass.swift
//  NookDesign
//
//  The translucent glass layer for panels that float over the window: Liquid Glass on macOS 26
//  and later, a blur material before that, and the solid raised card when the user turns on
//  Reduce Transparency.
//

import SwiftUI

public extension View {
    /// A floating panel drawn as glass, so the page and sidebar show through it.
    /// `tint` colors the glass, as a space's color tints the floating sidebar.
    func nookGlassSurface<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(NookGlassSurface(shape: shape, tint: tint))
    }
}

private struct NookGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    /// A lit edge, brighter at the top as light catches the glass. Over a dark page the glass and
    /// its shadow both go dark too, and without this edge the panel melts into the page.
    private var rim: some View {
        shape.strokeBorder(
            LinearGradient(colors: colorScheme == .dark ? [.white.opacity(0.24), .white.opacity(0.08)]
                                                        : [.black.opacity(0.10), .black.opacity(0.16)],
                           startPoint: .top, endPoint: .bottom),
            lineWidth: NookDesign.Size.hairlineWidth)
    }

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.nookFloatingSurface(in: shape)
        } else if #available(macOS 26, iOS 26, *) {
            content
                // Regular, not clear: these panels carry text (HIG, Materials).
                .glassEffect(.regular.tint(tint), in: shape)
                .overlay(rim)
                .nookElevation(.floating)
        } else {
            content
                .clipShape(shape)
                .background(.regularMaterial, in: shape)
                .background((tint ?? .clear).opacity(0.25), in: shape)
                .overlay(rim)
                .nookElevation(.floating)
        }
    }
}
