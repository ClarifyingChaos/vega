// Licensed under GPL-3.0. See LICENSE.
//
//  DownloadIndicator.swift
//  Nook
//
//  Created by Maciek Bagiński on 13/09/2025.
//

import SwiftUI
import NookDesign

struct DownloadIndicator: View {
    @EnvironmentObject var browserManager: BrowserManager

    /// The newest active download. `.first` was whichever the dictionary yielded, so with two
    /// running the ring could jump between them.
    var currentDownload: Download? {
        browserManager.downloadManager.activeDownloads.max { $0.startDate < $1.startDate }
    }

    var body: some View {
        Group {
            if let download = currentDownload {
                CircularProgressView(progress: download.progress)
                    .transition(.slideFromTop)
            }
        }
        .animation(NookDesign.Motion.spring, value: currentDownload?.id)
    }
}

extension AnyTransition {
    static var slideFromTop: AnyTransition {
        .asymmetric(
            insertion: .offset(y: -10).combined(with: .opacity),
            removal: .offset(y: -30).combined(with: .opacity)
        )
    }
}

/// Arc's download ring: a thin track and arc around a small arrow.
struct CircularProgressView: View {
    let progress: Double
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            Image(systemName: "arrow.down")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(Color.primary)
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.primary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(NookDesign.Motion.standard, value: progress)
        }
        .frame(width: size, height: size)
    }
}
