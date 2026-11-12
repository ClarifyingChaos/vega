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
        // FORK: the loading pill is gone; loading shows as a tint in the address field. This keeps the page inset.
        HStack {
            Spacer()
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
