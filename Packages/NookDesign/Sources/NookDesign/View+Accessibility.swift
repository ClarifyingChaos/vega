// Licensed under GPL-3.0. See LICENSE.
//
//  View+Accessibility.swift
//  NookDesign
//
//  App-wide accessibility settings applied once at each window's root, so every view inherits
//  them instead of each animation checking on its own.
//

import SwiftUI

public extension View {
    /// With Reduce Motion on, changes in this subtree happen without movement: springs, slides
    /// and scales become instant (HIG, Motion: prefer static transitions). Gesture-tracked
    /// motion, which follows the pointer rather than an animation, is unaffected.
    func nookReduceMotion() -> some View {
        modifier(NookReduceMotion())
    }
}

private struct NookReduceMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
    }
}
