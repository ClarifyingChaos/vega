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
    func nookGlassSurface<S: InsettableShape>(in shape: S) -> some View {
        modifier(NookGlassSurface(shape: shape))
    }
}

private struct NookGlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.nookFloatingSurface(in: shape)
        } else if #available(macOS 26, iOS 26, *) {
            content
                .glassEffect(.regular, in: shape)
                .nookElevation(.floating)
        } else {
            content
                .clipShape(shape)
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(NookDesign.Surface.hairline, lineWidth: NookDesign.Size.hairlineWidth))
                .nookElevation(.floating)
        }
    }
}
