// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarMenuMediaTab.swift
//  Nook
//
//  FORK: Arc's Media view in the Library: the images and videos you downloaded, as a grid of
//  thumbnails. shortcut: downloads only, upgrade to captures saved elsewhere if people ask.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import NookDesign
import NookUI

struct SidebarMenuMediaTab: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", images = "Images", videos = "Videos"
        var id: String { rawValue }
    }

    private enum Kind { case image, video }

    private func kind(of download: Download) -> Kind? {
        guard download.state == .completed, let file = download.completedFile,
              let type = UTType(filenameExtension: file.pathExtension) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        return nil
    }

    private var items: [Download] {
        browserManager.downloadManager.allDownloads.filter { download in
            guard let kind = kind(of: download) else { return false }
            switch filter {
            case .all: return true
            case .images: return kind == .image
            case .videos: return kind == .video
            }
        }
    }

    var body: some View {
        let items = items
        VStack(spacing: 0) {
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, NookDesign.Spacing.lg)
            .padding(.top, NookDesign.Spacing.sidebarTop)
            .padding(.bottom, NookDesign.Spacing.md)

            ScrollView {
                if items.isEmpty {
                    VStack(spacing: NookDesign.Spacing.md) {
                        Image(systemName: "photo.on.rectangle")
                            .font(NookDesign.Font.titleLarge)
                            .foregroundStyle(.tertiary)
                        Text("No media yet")
                            .font(NookDesign.Font.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NookDesign.Spacing.xxxl)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: NookDesign.Spacing.md)], spacing: NookDesign.Spacing.md) {
                        ForEach(items) { MediaTile(download: $0, isVideo: kind(of: $0) == .video) }
                    }
                    .padding(.horizontal, NookDesign.Spacing.lg)
                    .padding(.bottom, NookDesign.Spacing.lg)
                }
            }
        }
    }
}

private struct MediaTile: View {
    let download: Download
    let isVideo: Bool
    @State private var isHovering = false

    var body: some View {
        Image(nsImage: download.downloadThumbnail ?? download.icon)
            .resizable()
            .aspectRatio(contentMode: download.downloadThumbnail == nil ? .fit : .fill)
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(NookDesign.Surface.fill)
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
            .overlay(alignment: .bottomLeading) {
                if isVideo {
                    Image(systemName: "play.fill")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.black.opacity(0.55), in: Circle())
                        .padding(NookDesign.Spacing.xs)
                }
            }
            .overlay(NookDesign.Radius.shape(NookDesign.Radius.md).strokeBorder(isHovering ? Color.primary.opacity(0.35) : NookDesign.Surface.hairline, lineWidth: 1))
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
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
