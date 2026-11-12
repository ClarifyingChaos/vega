// Licensed under GPL-3.0. See LICENSE.
//
//  PageLoadingProgressBar.swift
//  Nook
//
//  Thin progress bar shown on the URL bar during page loads.
//  Observes WKWebView.estimatedProgress + isLoading via KVO.
//

import SwiftUI
import WebKit
import NookDesign
import NookWeb

/// FORK: the load shows as a tint in the space's colour that sweeps across the address field and
/// fades when the page is ready. It replaces the 2.5 pt bar that sat on the field's lower edge.
struct PageLoadingProgressBar: View {
    let session: PageSession?
    let color: Color

    @StateObject private var observer = WebViewLoadingObserver()

    var body: some View {
        GeometryReader { geo in
            // Starts at a visible 12% so a fast load still shows, then follows the page's progress.
            Rectangle()
                .fill(LinearGradient(colors: [color.opacity(0.34), color.opacity(0.18)], startPoint: .leading, endPoint: .trailing))
                .frame(width: geo.size.width * max(observer.progress, observer.isLoading ? 0.12 : 0))
                .animation(NookDesign.Motion.standard, value: observer.progress)
                .opacity(observer.isLoading ? 1 : 0)
                .animation(.easeOut(duration: 0.45), value: observer.isLoading)
        }
        // Observation tracks the session's web view, so a view created later attaches too.
        .onChange(of: session?.webView) { _, webView in
            observer.attach(to: webView)
        }
        .onAppear {
            observer.attach(to: session?.webView)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .allowsHitTesting(false)
    }
}

@MainActor
private class WebViewLoadingObserver: ObservableObject {
    @Published var progress: CGFloat = 0
    @Published var isLoading: Bool = false

    private(set) weak var webView: WKWebView?
    private var progressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var hideTask: Task<Void, Never>?

    func attach(to webView: WKWebView?) {
        guard webView !== self.webView else { return }

        progressObservation?.invalidate()
        loadingObservation?.invalidate()
        self.webView = webView

        guard let webView else {
            progress = 0
            isLoading = false
            return
        }

        progress = webView.estimatedProgress
        isLoading = webView.isLoading

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            // KVO for WKWebView properties fires on the main thread
            MainActor.assumeIsolated {
                self?.progress = wv.estimatedProgress
            }
        }

        loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
            // KVO for WKWebView properties fires on the main thread
            MainActor.assumeIsolated {
                guard let self else { return }
                if wv.isLoading {
                    self.hideTask?.cancel()
                    self.isLoading = true
                } else {
                    // Brief delay to show completed state before hiding
                    self.progress = 1.0
                    self.hideTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        self.isLoading = false
                        self.progress = 0
                    }
                }
            }
        }
    }

    deinit {
        progressObservation?.invalidate()
        loadingObservation?.invalidate()
    }
}
