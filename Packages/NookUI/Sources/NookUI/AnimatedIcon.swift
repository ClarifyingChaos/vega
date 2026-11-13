// Licensed under GPL-3.0. See LICENSE.
//
//  AnimatedIcon.swift
//  NookUI
//
//  FORK: icons from useanimations.com (MIT, Lottie JSON in Resources/UseAnimations). Each plays once
//  when the pointer arrives on its button and rests on its first frame otherwise. Drawn in the
//  button's foreground colour. A missing file falls back to an SF Symbol.
//

import SwiftUI
import AppKit
import Lottie

private struct NookIconHoveringKey: EnvironmentKey { static let defaultValue = false }

public extension EnvironmentValues {
    /// True while the pointer is on the enclosing icon button (set by `NookIconButtonStyle`).
    var nookIconHovering: Bool {
        get { self[NookIconHoveringKey.self] }
        set { self[NookIconHoveringKey.self] = newValue }
    }
}

public struct AnimatedIcon: View {
    private let name: String
    private let fallback: String
    private let size: CGFloat
    private let holdWhileHovered: Bool
    private let ink: Color?
    private let toggled: Bool?

    @Environment(\.nookIconHovering) private var hovering
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var mode: LottiePlaybackMode
    /// Hover on the icon itself, for icons that sit outside a `NookIconButtonStyle` button.
    @State private var selfHovering = false
    private var isHovering: Bool { hovering || selfHovering }

    /// Where each animation's ink sits against the centre of its 32-unit canvas (x right, y down), for the ones
    /// that are off by more than a third of a unit. Measured from the rendered first frame; the view moves it back.
    private static let inkOffsets: [String: (x: CGFloat, y: CGFloat)] = [
        "archive": (0.0, 5.0),
        "checkmark": (0.0, -0.5),
        "key": (0.0, -0.5),
        "rotate-ccw": (-1.0, 0.0),
        "rotate-cw": (1.0, 0.0),
        // The paper plane is heavy at the nose: its mass sits 1.7 right and 2.0 up of its box, so it is placed by weight
        // (70% of the way), not by box, or it reads as off-centre inside a circle.
        "send": (1.2, -1.4),
        "star": (0.0, -0.5),
        "trash": (0.0, 2.0),
    ]

    /// Animations whose first frame is blank (they draw in), so they rest on the last frame instead.
    private static let restsAtEnd: Set<String> = ["checkmark"]

    @MainActor private static var cache: [String: LottieAnimation] = [:]

    /// `name` is a file in Resources/UseAnimations without its extension; `fallback` an SF Symbol.
    /// `toggled`: a two-state icon (mute): rests on the end frame when true and plays between the states when it changes.
    /// `holdWhileHovered`: play forward on enter and stay at the end, then play back on leave (plus to x).
    public init(_ name: String, fallback: String, size: CGFloat = 20, holdWhileHovered: Bool = false, ink: Color? = nil, toggled: Bool? = nil) {
        self.toggled = toggled
        self._mode = State(initialValue: .paused(at: .progress(toggled == true || Self.restsAtEnd.contains(name) ? 1 : 0)))
        self.ink = ink
        self.holdWhileHovered = holdWhileHovered
        self.name = name
        self.fallback = fallback
        self.size = size
    }

    @MainActor private var animation: LottieAnimation? {
        if let cached = Self.cache[name] { return cached }
        guard let loaded = LottieAnimation.named(name, bundle: .module, subdirectory: "UseAnimations") else { return nil }
        Self.cache[name] = loaded
        return loaded
    }

    private var inkColor: LottieColor {
        if let ink, let c = NSColor(ink).usingColorSpace(.sRGB) {
            return LottieColor(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent), a: Double(c.alphaComponent))
        }
        return colorScheme == .dark ? LottieColor(r: 1, g: 1, b: 1, a: 1) : LottieColor(r: 0.1, g: 0.1, b: 0.12, a: 1)
    }

    public var body: some View {
        Group {
            if let animation {
                let lottieInk = inkColor
                LottieView(animation: animation)
                    .playbackMode(mode)
                    .animationDidFinish { _ in
                        // Held icons rest on their end frame while the pointer is still on the button.
                        mode = .paused(at: .progress(toggled == true || Self.restsAtEnd.contains(name) || (holdWhileHovered && isHovering) ? 1 : 0))
                    }
                    .configure { $0.contentMode = .scaleAspectFit }
                    .valueProvider(ColorValueProvider(lottieInk), for: AnimationKeypath(keypath: "**.Color"))
                    .id(String(describing: colorScheme) + String(describing: ink))
                    .onChange(of: toggled) { _, now in
                        guard let now else { return }
                        mode = reduceMotion ? .paused(at: .progress(now ? 1 : 0))
                            : .playing(.fromProgress(now ? 0 : 1, toProgress: now ? 1 : 0, loopMode: .playOnce))
                    }
                    .onChange(of: isHovering) { _, now in
                        guard !reduceMotion, toggled == nil else { return }
                        if now {
                            mode = .playing(.fromProgress(0, toProgress: 1, loopMode: .playOnce))
                        } else if holdWhileHovered {
                            mode = .playing(.fromProgress(1, toProgress: 0, loopMode: .playOnce))
                        }
                    }
            } else {
                Image(systemName: fallback)
            }
        }
        .offset(x: -(Self.inkOffsets[name]?.x ?? 0) * size / 32, y: -(Self.inkOffsets[name]?.y ?? 0) * size / 32)
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onHover { selfHovering = $0 }
        .accessibilityHidden(true)
    }
}
