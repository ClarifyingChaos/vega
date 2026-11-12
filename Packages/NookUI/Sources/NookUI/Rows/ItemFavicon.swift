// Licensed under GPL-3.0. See LICENSE.
//
//  ItemFavicon.swift
//  NookUI
//
//  The favicon every row and tile draws, and the inline-rename state the rows and the
//  context menu share.
//

import SwiftUI
import NookTabsCore
import NookWeb

// MARK: - Rename State

/// The row being renamed inline. Shared so a context menu can start a rename on its row.
@MainActor
@Observable
final class SidebarRenameState {
    static let shared = SidebarRenameState()
    var itemID: UUID?
}

extension TabsController {
    /// Creates a "New Folder" under `parent` after `after` and starts renaming it inline.
    public func createFolderForRename(in parent: Parent, after: UUID?) {
        guard let folderID = createFolder(title: "New Folder", in: parent, after: after) else { return }
        if case .folder(let outer) = parent { openFolder(outer) }
        SidebarRenameState.shared.itemID = folderID
    }
}

// MARK: - Favicon

/// A row or tile favicon: the live page's, else the cached one for the item's host, else a globe.
public struct ItemFavicon: View {
    let item: Item
    let session: PageSession?
    @State private var cached: Image?
    @State private var cachedPlatform: PlatformImage?

    public init(item: Item, session: PageSession?) {
        self.item = item
        self.session = session
    }

    public var body: some View {
        let _ = session?.favicon // FORK: re-render when the live icon changes
        Group {
            if let crisp = crispSource {
                CrispIcon(source: crisp)
            } else {
                ((session?.hasLoadedFavicon == true ? session?.favicon : nil) ?? cached ?? session?.favicon ?? Image(systemName: "globe"))
                    .resizable()
                    .scaledToFit()
            }
        }
            // Keyed on the session too: closing a pinned tab or favorite ends its page but keeps
            // the row, and the cached icon must be loaded then.
            .task(id: "\(item.url.flatMap(FaviconCache.key) ?? "")|\(session == nil)|\(session?.hasLoadedFavicon == true)") {
                session?.ensureFaviconLoaded()
                guard let url = item.url, let host = FaviconCache.key(for: url) else { return }
                // FORK: a pin whose address redirects (gmail.com to mail.google.com) keeps the icon its page loaded.
                if let session, session.hasLoadedFavicon, FaviconCache.shared.image(for: host) == nil,
                   let live = FaviconCache.key(for: session.url).flatMap({ FaviconCache.shared.image(for: $0) }) {
                    FaviconCache.shared.store(live, for: host)
                }
                if let image = await FaviconCache.shared.cachedImage(for: host) { cached = Image(platformImage: image); cachedPlatform = image }
                // FORK: an unloaded favorite or pinned tab has no page to fetch its icon, so fetch it here.
                guard session?.hasLoadedFavicon != true,
                      let image = await FaviconCache.shared.loadOrFetch(for: url) else { return }
                cached = Image(platformImage: image)
                cachedPlatform = image
            }
    }

    /// FORK: the stored bitmap behind the icon, when there is one to resample for the tile.
    private var crispSource: PlatformImage? {
        #if os(macOS)
        if let session, session.hasLoadedFavicon, let image = FaviconCache.key(for: session.url).flatMap({ FaviconCache.shared.image(for: $0) }) { return image }
        return cachedPlatform
        #else
        return nil
        #endif
    }
}

#if os(macOS)
/// Draws an icon at exactly the device pixels it occupies. A square placeholder takes the layout
/// the scaled image would, then the resampled bitmap is drawn 1:1 inside it.
private struct CrispIcon: View {
    let source: PlatformImage
    @Environment(\.displayScale) private var scale
    @State private var edge: CGFloat = 0

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { edge = $0 }
            .overlay {
                if edge > 0 {
                    Image(nsImage: source.resampled(pixels: Int((edge * scale).rounded()), scale: scale))
                }
            }
    }
}
#endif
