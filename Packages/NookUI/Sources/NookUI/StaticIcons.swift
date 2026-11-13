// Licensed under GPL-3.0. See LICENSE.
//
//  StaticIcons.swift
//  NookUI
//
//  FORK: the useAnimations icons as still images, for the places a Lottie view cannot go: menu items,
//  context menus and labels. Frame 0 of each animation, drawn black on clear (Assets.xcassets/
//  UseAnimationsStatic) and used as template images, so they take the menu's colour.
//  Where no animated icon was chosen for a symbol, the SF Symbol stays.
//

import SwiftUI
import AppKit

public enum NookStaticIcons {
    /// SF Symbol name to the useAnimations icon chosen for it (vega-icon-picks.json and the guide page).
    static let animations: [String: String] = [
        "airplayvideo": "airplay",
        "archivebox": "inbox",
        "arrow.backward": "arrow-left",
        "arrow.clockwise": "rotate-cw",
        "arrow.counterclockwise": "rotate-ccw",
        "arrow.down.circle": "download",
        "arrow.down.to.line": "download",
        "arrow.left": "arrow-left",
        "arrow.right": "arrow-right",
        "arrow.up.forward": "arrow-up-right",
        "arrow.up.forward.app": "external-link",
        "arrow.up.left.and.arrow.down.right": "maximize-2",
        "arrow.up.to.line": "upload",
        "arrow.uturn.backward": "rotate-ccw",
        "bell": "notification",
        "camera": "camera",
        "checkmark": "checkmark",
        "checkmark.circle": "check-circle",
        "chevron.backward": "chevron-left",
        "chevron.down": "chevron-down",
        "chevron.forward": "chevron-right",
        "chevron.left": "chevron-left",
        "chevron.right": "chevron-right",
        "chevron.up": "chevron-up",
        "clock": "clock",
        "doc.on.doc": "copy",
        "ellipsis": "more-horizontal",
        "exclamationmark.triangle": "alert-triangle",
        "exclamationmark.triangle.fill": "alert-triangle",
        "eye.slash": "visibility",
        "folder": "folder",
        "folder.badge.plus": "folder-plus",
        "gear": "settings",
        "gearshape": "settings",
        "globe": "globe",
        "hammer": "code",
        "house": "home",
        "icloud": "cloud",
        "info.circle": "info",
        "key": "key",
        "keyboard": "command",
        "link": "link",
        "magnifyingglass": "search-to-x",
        "message": "message-circle",
        "mic.fill": "microphone",
        "minus": "minus",
        "minus.magnifyingglass": "zoom-out",
        "note.text": "file-text",
        "note.text.badge.plus": "file-plus",
        "pencil": "edit-2",
        "person.2": "users",
        "person.crop.circle": "user",
        "photo.on.rectangle": "image",
        "pin": "pin",
        "pin.slash": "unpin",
        "pip": "pip",
        "pip.exit": "pip-exit",
        "plus": "plus-to-x",
        "plus.circle": "plus-circle",
        "plus.magnifyingglass": "zoom-in",
        "plus.square": "plus-square",
        "plus.square.on.square": "plus-square",
        "printer": "printer",
        "puzzlepiece.extension": "package",
        "rectangle.split.2x1": "columns",
        "rectangle.stack": "layers",
        "shield.lefthalf.filled": "shield",
        "slider.horizontal.3": "settings-v2",
        "square.and.arrow.down": "download",
        "square.and.arrow.up": "share",
        "square.grid.2x2": "grid",
        "star": "star",
        "textformat": "type",
        "trash": "trash",
        "video.fill": "video",
        "wand.and.sparkles": "zap",
        "wand.and.stars": "zap",
        "xmark": "error",
    ]

    /// Rendered at 22 pt: the art fills 24 of the 32 units, so the glyph is about 16.5 pt, like an SF Symbol in a menu.
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor public static func image(forSymbol symbol: String) -> NSImage? {
        guard let id = animations[symbol] else { return nil }
        if let cached = cache[symbol] { return cached }
        guard let base = NSImage(named: "ua-\(id)"), let image = base.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = true
        cache[symbol] = image
        return image
    }
}

public extension Label where Title == Text, Icon == Image {
    /// Like `Label(_:systemImage:)`, with the chosen animated icon's still frame where there is one.
    @MainActor init(_ title: LocalizedStringKey, nookIcon symbol: String) {
        if let image = NookStaticIcons.image(forSymbol: symbol) { self.init(title: { Text(title) }, icon: { Image(nsImage: image) }) }
        else { self.init(title, systemImage: symbol) }
    }
    @MainActor init<S: StringProtocol>(_ title: S, nookIcon symbol: String) {
        if let image = NookStaticIcons.image(forSymbol: symbol) { self.init(title: { Text(title) }, icon: { Image(nsImage: image) }) }
        else { self.init(title, systemImage: symbol) }
    }
}

public extension Button where Label == SwiftUI.Label<Text, Image> {
    @MainActor init(_ title: LocalizedStringKey, nookIcon symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(title, nookIcon: symbol) }
    }
    @MainActor init<S: StringProtocol>(_ title: S, nookIcon symbol: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) { SwiftUI.Label(title, nookIcon: symbol) }
    }
}

/// A still animated-icon frame in place of `Image(systemName:)`; takes the surrounding foreground style.
public struct NookSymbol: View {
    private let symbol: String
    private let size: CGFloat
    public init(_ symbol: String, size: CGFloat) { self.symbol = symbol; self.size = size }
    @MainActor public var body: some View {
        if let image = NookStaticIcons.image(forSymbol: symbol) {
            Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: symbol).font(.system(size: size / 1.25, weight: .medium))
        }
    }
}
