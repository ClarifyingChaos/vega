// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionLibraryOverlay.swift
//  Nook
//
//  Created by Bain Gurley on 21/09/2026.
//

import SwiftUI
import NookDesign
import NookWeb

/// Where the URL bar's overflow button sits, reported so the overlay can hang off it.
struct ExtensionLibraryAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// The extension library and its overflow menu, drawn inside the window rather than in an
/// `NSPanel`: a key panel gets a heavier window shadow that squares off at its own edge, and
/// in-window needs no event monitors to dismiss.
struct ExtensionLibraryOverlay: View {
    let anchor: Anchor<CGRect>?

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @State private var isShowingMoreMenu = false
    @State private var appeared = false

    private let menuWidth: CGFloat = 232 // FORK: Arc's panel is about 232 pt wide (was 300)
    private let gap: CGFloat = 10
    private let notchWidth: CGFloat = 18
    private let notchHeight: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            if windowState.isExtensionLibraryVisible,
               let settings = browserManager.nookSettings,
               let anchor {
                let buttonFrame = proxy[anchor]

                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { close() }

                    HStack(alignment: .top, spacing: gap) {
                        ExtensionLibraryView(
                            browserManager: browserManager,
                            windowState: windowState,
                            settings: settings,
                            onDismiss: { close() },
                            onShowMoreMenu: { isShowingMoreMenu.toggle() }
                        )
                        .frame(width: menuWidth)
                        .padding(.top, notchHeight)
                        // FORK: Arc's dark panel with its notch pointing at the button, as one glass
                        // shape; the panel stays dark in a light theme, as Arc's does.
                        .environment(\.colorScheme, .dark)
                        .nookGlassSurface(
                            in: NotchedPanel(radius: NookDesign.Radius.xl, notchX: buttonFrame.midX - originX(buttonFrame: buttonFrame, container: proxy.size),
                                             notchWidth: notchWidth, notchHeight: notchHeight),
                            tint: .black.opacity(0.45))
                        // Grows out of the button rather than appearing whole.
                        .scaleEffect(appeared ? 1 : 0.88, anchor: UnitPoint(
                            x: (buttonFrame.midX - originX(buttonFrame: buttonFrame, container: proxy.size)) / menuWidth, y: 0))
                        .opacity(appeared ? 1 : 0)
                        .onAppear {
                            withAnimation(.interpolatingSpring(Spring(response: 0.3, dampingRatio: 0.86))) { appeared = true }
                        }
                        .onDisappear { appeared = false }

                        if isShowingMoreMenu {
                            MoreMenuView(
                                browserManager: browserManager,
                                windowState: windowState,
                                onDismiss: { isShowingMoreMenu = false }
                            )
                            .nookGlassSurface(in: NookDesign.Radius.shape(NookDesign.Radius.lg))
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                        }
                    }
                    .fixedSize()
                    .offset(x: originX(buttonFrame: buttonFrame, container: proxy.size),
                            y: buttonFrame.maxY + 2)
                }
                .animation(NookDesign.Motion.quick, value: isShowingMoreMenu)
                .transition(.opacity)
                .onExitCommand { close() }
                .onChange(of: windowState.selectedItemID) { _, _ in close() }
            }
        }
        .ignoresSafeArea()
    }

    /// Centred under the button, clamped so a narrow window cannot push it off screen. Centring
    /// uses the library's own width, not the pair's, so the library stays put when the overflow
    /// menu opens beside it.
    private func originX(buttonFrame: CGRect, container: CGSize) -> CGFloat {
        let preferred = buttonFrame.midX - menuWidth / 2
        let maxX = max(gap, container.width - menuWidth - gap)
        return min(max(gap, preferred), maxX)
    }

    private func close() {
        isShowingMoreMenu = false
        withAnimation(.interpolatingSpring(Spring(response: 0.25, dampingRatio: 1))) {
            windowState.isExtensionLibraryVisible = false
        }
    }
}

/// A rounded panel with a notch on its top edge, drawn as one path so glass fills it whole.
struct NotchedPanel: InsettableShape {
    var radius: CGFloat
    /// The notch's centre, in the panel's own coordinates.
    var notchX: CGFloat
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let top = r.minY + notchHeight, rad = radius
        let cx = min(max(notchX, r.minX + rad + notchWidth / 2), r.maxX - rad - notchWidth / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + rad, y: top))
        p.addLine(to: CGPoint(x: cx - notchWidth / 2, y: top))
        p.addQuadCurve(to: CGPoint(x: cx, y: r.minY), control: CGPoint(x: cx - notchWidth * 0.18, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: cx + notchWidth / 2, y: top), control: CGPoint(x: cx + notchWidth * 0.18, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - rad, y: top))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: top), tangent2End: CGPoint(x: r.maxX, y: top + rad), radius: rad)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - rad, y: r.maxY), radius: rad)
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - rad), radius: rad)
        p.addLine(to: CGPoint(x: r.minX, y: top + rad))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: top), tangent2End: CGPoint(x: r.minX + rad, y: top), radius: rad)
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> NotchedPanel {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
