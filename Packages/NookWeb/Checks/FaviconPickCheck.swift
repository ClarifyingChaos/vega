// Licensed under GPL-3.0. See LICENSE.
//
//  FaviconPickCheck.swift
//  Nook
//
//  Favicon choice and preparation check. Compiles the shipped source directly:
//
//    swiftc Packages/NookWeb/Sources/NookWeb/FaviconImage+Pick.swift \
//           Packages/NookWeb/Checks/FaviconPickCheck.swift -o /tmp/favicon-pick-check && /tmp/favicon-pick-check
//

import AppKit

/// A `side`-pixel image, clear except an opaque square `inset` pixels in from every edge.
func icon(_ side: Int, inset: Int = 0, width w: Int? = nil) -> NSImage {
    let w = w ?? side
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: side, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.red.setFill()
    NSRect(x: inset, y: inset, width: w - 2 * inset, height: side - 2 * inset).fill()
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: NSSize(width: w, height: side))
    image.addRepresentation(rep)
    return image
}

@main
struct FaviconPickCheck {
    static func main() {
        // A plain favicon beats a touch icon, even a bigger one.
        precondition(IconRank(icon(48), touchIcon: false) > IconRank(icon(180), touchIcon: true))
        // Among plain favicons, sharp beats blurry, and the smallest sharp one wins.
        precondition(IconRank(icon(64), touchIcon: false) > IconRank(icon(32), touchIcon: false))
        precondition(IconRank(icon(64), touchIcon: false) > IconRank(icon(256), touchIcon: false))
        precondition(IconRank(icon(32), touchIcon: false) > IconRank(icon(16), touchIcon: false))
        // Banners are not icons.
        precondition(!IconRank(icon(32, width: 96), touchIcon: false).usable)

        // The empty margin is cropped so the mark fills the box.
        precondition(icon(128, inset: 24).trimmedToContent().pixelSize == (80, 80))
        precondition(icon(64).trimmedToContent().pixelSize == (64, 64))   // already full
        // Blank images are caught.
        precondition(icon(32, inset: 16).isBlank)
        precondition(!icon(32).isBlank)
        // Resampling lands on exact device pixels.
        precondition(icon(128).resampled(pixels: 40, scale: 2).pixelSize == (40, 40))
        precondition(icon(128).resampled(pixels: 40, scale: 2).size == NSSize(width: 20, height: 20))
        print("FaviconPickCheck: ok")
    }
}
