// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarMenuMediaTab.swift
//  Nook
//
//  FORK: Arc's Media view in the Library: the images and videos you downloaded, as a grid of
//  thumbnails with a search field on top. shortcut: downloads only, upgrade to captures saved
//  elsewhere if people ask.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import NookDesign
import NookUI

struct SidebarMenuMediaTab: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var text = ""

    private func isVideo(_ download: Download) -> Bool? {
        guard download.state == .completed, let file = download.completedFile,
              let type = UTType(filenameExtension: file.pathExtension) else { return nil }
        if type.conforms(to: .image) { return false }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return true }
        return nil
    }

    private var items: [Download] {
        browserManager.downloadManager.allDownloads.filter { download in
            guard isVideo(download) != nil else { return false }
            return text.isEmpty
                || download.displayName.localizedCaseInsensitiveContains(text)
                || download.originalURL.absoluteString.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        let items = items
        VStack(spacing: 0) {
            SidebarMenuSearchField(prompt: "Search Media...", text: $text)
                .padding(.horizontal, NookDesign.Spacing.md)
                .padding(.top, NookDesign.Spacing.sidebarTop)
                .padding(.bottom, NookDesign.Spacing.md)

            ScrollView {
                if items.isEmpty {
                    VStack(spacing: NookDesign.Spacing.md) {
                        Image(systemName: text.isEmpty ? "photo.on.rectangle" : "magnifyingglass")
                            .font(NookDesign.Font.titleLarge)
                            .foregroundStyle(.tertiary)
                        Text(text.isEmpty ? "No media yet" : "No media found")
                            .font(NookDesign.Font.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NookDesign.Spacing.xxxl)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: NookDesign.Spacing.md)], spacing: NookDesign.Spacing.md) {
                        ForEach(items) { MediaTile(download: $0, isVideo: isVideo($0) == true) }
                    }
                    .padding(.horizontal, NookDesign.Spacing.md)
                    .padding(.bottom, NookDesign.Spacing.lg)
                }
            }
        }
    }
}

/// Arc's cell: the file fitted inside a rounded dark square.
private struct MediaTile: View {
    let download: Download
    let isVideo: Bool
    @State private var isHovering = false

    private var shape: some InsettableShape { NookDesign.Radius.shape(NookDesign.Radius.lg) }

    var body: some View {
        Image(nsImage: download.downloadThumbnail ?? download.icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(NookDesign.Spacing.xl)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(NookDesign.Surface.fill)
            .clipShape(shape)
            .overlay(alignment: .bottomLeading) {
                if isVideo {
                    Image(systemName: "play.fill")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.black.opacity(0.55), in: Circle())
                        .padding(NookDesign.Spacing.sm)
                }
            }
            .overlay(shape.strokeBorder(isHovering ? Color.primary.opacity(0.35) : Color.clear, lineWidth: 1))
            .contentShape(shape)
            .onHover { isHovering = $0 }
            .help(download.displayName)
            .accessibilityLabel(download.displayName)
            .task(id: download.destinationURL) {
                if download.downloadThumbnail == nil { await download.loadThumbnail(size: CGSize(width: 240, height: 240)) }
            }
            .onTapGesture { DownloadManager.shared.previewing = download }
            .onDrag { download.dragItemProvider() }
            .contextMenu {
                if let file = download.completedFile {
                    Button("Open") { NSWorkspace.shared.open(file) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                    Divider()
                }
                Button("Hide from Vega") { DownloadManager.shared.removeDownload(download.id) }
            }
    }
}
