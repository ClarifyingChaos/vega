// Licensed under GPL-3.0. See LICENSE.
//
//  WebsiteLoadingIndicator.swift
//  Nook
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import SwiftUI
import NookDesign
import NookWeb

struct WebsiteLoadingIndicator: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    
    var body: some View {
        HStack {
            Spacer()
            // FORK: Arc's loading pill above the page: a visible capsule that grows with the load
            // and fades out when it ends (was 3 pt of 30% white, invisible on light chrome).
            Capsule()
                .fill(Color.black.opacity(0.5)) // dark pill on the colored chrome, as in Arc
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                .frame(width: indicatorWidth, height: 4)
                .opacity(indicatorWidth > 0 ? 1 : 0)
                .animation(NookDesign.Motion.spring, value: indicatorWidth)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: NookDesign.Chrome.pageInsetTop)
        
        
    }
    
    private var indicatorWidth: CGFloat {
        switch browserManager.tabs.selectedSession(in: windowState)?.loadingState {
        case .idle:
            return 0
        case .didStartProvisionalNavigation:
            return 120
        case .didCommit:
            return 240
        case .didFinish:
            return 0
        case .didFail:
            return 0
        case .didFailProvisionalNavigation:
            return 0
        case .none:
            return 0
        }
    }
}
