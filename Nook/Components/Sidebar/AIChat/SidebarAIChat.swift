// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarAIChat.swift
//  Nook
//
//  AI chat panel for sidebar — view-only layer delegating to AIService
//

import SwiftUI
import AppKit
import NookDesign
import NookWeb
import NookUI

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date
    var citations: [URLCitation] = []
    var usedWebSearch: Bool = false

    enum Role {
        case user
        case assistant
    }
}

struct URLCitation: Identifiable, Equatable, Codable {
    var id = UUID()
    let url: String
    let title: String?
    let content: String?
    let startIndex: Int
    let endIndex: Int

    var displayTitle: String {
        title ?? url
    }

    var domain: String {
        if let urlObj = URL(string: url),
           let host = urlObj.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return url
    }
}

struct SidebarAIChat: View {
    @Environment(BrowserWindowState.self) private var windowState
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.nookSettings) var nookSettings
    @Environment(AIService.self) var aiService
    @Environment(AIConfigService.self) var configService

    @State private var messageText: String = ""
    @State private var showAddModelPopover: Bool = false
    @State private var showModelMenu: Bool = false
    @State private var newModelId: String = ""
    @FocusState private var isTextFieldFocused: Bool

    private let streamingBubbleID = "streaming"

    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !aiService.hasApiKey {
                            apiKeyRequiredView
                        } else if aiService.messages.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(aiService.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }

                        if aiService.isLoading {
                            if aiService.streamingText.isEmpty {
                                loadingView
                            } else {
                                MessageBubble(message: ChatMessage(role: .assistant, content: aiService.streamingText, timestamp: .now))
                                    .id(streamingBubbleID)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onChange(of: aiService.streamingText) {
                    proxy.scrollTo(streamingBubbleID, anchor: .bottom)
                }
                .onChange(of: aiService.messages.count) { _, _ in
                    if let last = aiService.messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(stops: [.init(color: .black.opacity(0.2), location: 0.4), .init(color: .black, location: 1.0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 60)
                    Color.black
                    LinearGradient(colors: [.black, .black.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 90)
                }.ignoresSafeArea()
            }
        }
        .safeAreaInset(edge: .top, content: {
            headerView
        })
        .safeAreaInset(edge: .bottom) {
            inputAreaView
        }
        .safeAreaPadding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: windowState.agentDraft, initial: true) { takeAgentDraft() }
        .onAppear {
            isTextFieldFocused = true

            if configService.activeProviderType == .ollama {
                Task { await configService.fetchOllamaModels() }
            }
        }
        .onChange(of: configService.config.activeProviderId) { _, _ in
            if configService.activeProviderType == .ollama {
                Task { await configService.fetchOllamaModels() }
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask Vega")
                        .font(NookDesign.Font.heading)
                        .foregroundStyle(.primary)
                    // The page the chat is about, so it is clear what "this page" means.
                    if let host = pageHost {
                        Text(host)
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: NookDesign.Spacing.xxs) {
                    Button {
                        showClearMessagesDialog()
                    } label: {
                        AnimatedIcon("trash", fallback: "trash")
                    }
                    .disabled(aiService.messages.isEmpty)
                    .accessibilityLabel("Clear Chat")
                    .help("Clear this chat")
                    Button {
                        showSettings()
                    } label: {
                        AnimatedIcon("settings", fallback: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                    .help("AI settings")
                    Button {
                        withAnimation(NookDesign.Motion.standard) {
                            windowState.isSidebarAIChatVisible = false
                        }
                    } label: {
                        AnimatedIcon("error", fallback: "xmark")
                    }
                    .accessibilityLabel("Close")
                    .help("Close")
                }
                .nookIconButtons()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().opacity(0.5)
        }
    }

    private var pageHost: String? {
        guard let url = browserManager.tabs.selectedSession(in: windowState)?.url,
              let host = url.host(), ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    // MARK: - Input Area

    private var inputAreaView: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("", text: $messageText, prompt: Text("Ask about this page...").foregroundColor(.secondary), axis: .vertical)
                .textFieldStyle(.plain)
                .font(NookDesign.Font.body)
                .foregroundStyle(.primary)
                .lineLimit(2...6)
                .focused($isTextFieldFocused)
                .onSubmit { sendMessage() }

            HStack(spacing: 8) {
                // Dynamic model selector
                modelSelectorMenu

                // Web search toggle
                if let providerType = configService.activeProviderType,
                   providerType == .gemini || providerType == .openRouter {
                    webSearchToggle
                }

                Spacer()

                Button(action: sendMessage) {
                    AnimatedIcon("send", fallback: "paperplane", size: 18, ink: canSend ? .white : .secondary)
                        .frame(width: 28, height: 28)
                        .background(canSend ? Color.accentColor : Color.primary.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .help("Send")
            }
        }
        .padding(14)
        .chatSurface(radius: NookDesign.Radius.xl)
        .overlay(alignment: .topLeading) {
            if showModelMenu {
                // A zero-size frame pinned at the composer's top-left corner; the card hangs from its bottom-left,
                // so it opens upward with its left edge on the pill's left edge.
                modelMenuCard
                    .padding(.leading, 14)
                    .frame(width: 0, height: 0, alignment: .bottomLeading)
                    .offset(y: -8)
                    .transition(.opacity)
            }
        }
        .zIndex(1)
        .onChange(of: isTextFieldFocused) { _, focused in if focused { showModelMenu = false } }
        .onExitCommand { showModelMenu = false }
        .padding(.horizontal, 12)
    }

    private var canSend: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !aiService.isLoading && aiService.hasApiKey
    }

    // MARK: - Model Selector

    private var modelSelectorMenu: some View {
        Button {
            withAnimation(NookDesign.Motion.quick) { showModelMenu.toggle() }
        } label: {
            // A pill with its own edge, so its left side lines up with the text above it.
            HStack(spacing: 5) {
                Text(configService.activeModel?.displayName ?? "Add Model")
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.primary.opacity(0.09), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.75))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showAddModelPopover, arrowEdge: .top) {
            VStack(spacing: 8) {
                Text("Add Model by ID")
                    .font(NookDesign.Font.secondary)
                TextField("Model ID (e.g. gpt-4o)", text: $newModelId)
                    .textFieldStyle(.roundedBorder)
                    .font(NookDesign.Font.secondary)
                    .frame(width: 200)
                HStack {
                    Button("Cancel") {
                        newModelId = ""
                        showAddModelPopover = false
                    }
                    .controlSize(.small)
                    Button("Add") {
                        guard !newModelId.isEmpty,
                              let providerId = configService.config.activeProviderId else { return }
                        configService.addModelById(newModelId, displayName: nil, providerId: providerId)
                        configService.setActiveModel(newModelId)
                        newModelId = ""
                        showAddModelPopover = false
                    }
                    .controlSize(.small)
                    .disabled(newModelId.isEmpty || configService.config.activeProviderId == nil)
                }
            }
            .padding(12)
        }
    }


    /// The model list, opened above the composer with its left edge on the model pill (a system menu centres itself
    /// on the pill, which left the two out of line).
    private var modelMenuCard: some View {
        let close = { withAnimation(NookDesign.Motion.quick) { showModelMenu = false } }
        let active = configService.config.activeModelId
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(configService.modelsForActiveProvider()) { model in
                ModelMenuRow(title: model.displayName, checked: active == model.id) {
                    configService.setActiveModel(model.id); close()
                }
            }
            if !configService.ollamaModels.isEmpty && configService.activeProviderType == .ollama {
                Divider().padding(.vertical, 4)
                ForEach(configService.ollamaModels) { model in
                    ModelMenuRow(title: model.displayName, checked: active == model.id) {
                        configService.addModel(model); configService.setActiveModel(model.id); close()
                    }
                }
            }
            Divider().padding(.vertical, 4)
            if configService.activeProviderType != .appleIntelligence {
                ModelMenuRow(title: "Add Model…", icon: "plus.circle") { close(); showAddModelPopover = true }
            }
            ModelMenuRow(title: "Manage Models…", icon: "gearshape") { close(); showSettings() }
        }
        .padding(6)
        .frame(minWidth: 190, alignment: .leading)
        .fixedSize()
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96), in: NookDesign.Radius.shape(NookDesign.Radius.lg))
        .overlay(NookDesign.Radius.shape(NookDesign.Radius.lg).strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }

    // MARK: - Web Search Toggle

    private var webSearchToggle: some View {
        Button(action: {
            withAnimation(NookDesign.Motion.standard) {
                var config = configService.generationConfig
                config.webSearchEnabled.toggle()
                configService.generationConfig = config
            }
        }) {
            AnimatedIcon("globe", fallback: "globe", size: 18,
                         ink: configService.generationConfig.webSearchEnabled ? .green : .secondary)
        }
        .buttonStyle(NookIconButtonStyle())
        .help(configService.generationConfig.webSearchEnabled ? "Web Search On" : "Web Search Off")
    }

    // MARK: - Empty/Loading States

    private var apiKeyRequiredView: some View {
        VStack(spacing: 12) {
            AnimatedIcon("key", fallback: "key", size: 40, ink: .secondary)

            Text("API Key Required")
                .font(NookDesign.Font.label)
                .foregroundStyle(.primary)

            Text("Add your API key to start chatting")
                .font(NookDesign.Font.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Add API Key") { showSettings() }
                .font(NookDesign.Font.secondary)
                .buttonStyle(RectNavButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            let webSearchEnabled = configService.generationConfig.webSearchEnabled
            let supportsWebSearch = configService.activeProviderType == .openRouter || configService.activeProviderType == .gemini

            VStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .font(NookDesign.Font.display)
                    .foregroundStyle(.tertiary)
                Text("What can I help with?")
                    .font(NookDesign.Font.heading)
                    .foregroundStyle(.primary)
                Text("Ask about this page, or anything else.")
                    .font(NookDesign.Font.bodyRegular)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if webSearchEnabled && supportsWebSearch {
                    Text("Web search is on")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.green.opacity(0.12), in: NookDesign.Radius.shape(NookDesign.Radius.sm))
                }
            }

            VStack(spacing: 8) {
                suggestion("Summarize this page")
                suggestion("List the key points")
                suggestion("Explain this in simple terms")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, 4)
    }

    /// A starter prompt: one click sends it.
    private func suggestion(_ text: String) -> some View {
        Button {
            messageText = text
            sendMessage()
        } label: {
            HStack(spacing: 10) {
                Text(text)
                    .font(NookDesign.Font.body)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                AnimatedIcon("arrow-up-right", fallback: "arrow.up.right", size: 16, ink: .secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .chatSurface(radius: NookDesign.Radius.lg)
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
        }
        .buttonStyle(.plain)
        .disabled(!aiService.hasApiKey || aiService.isLoading)
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            VStack(alignment: .leading, spacing: 2) {
                if let toolName = aiService.currentToolName {
                    Text("Using \(toolName)...")
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.purple.opacity(0.8))
                } else {
                    Text("Thinking...")
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.secondary)
                }
                if configService.generationConfig.webSearchEnabled && !aiService.isExecutingTools {
                    Text("Searching the web...")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !messageText.isEmpty, aiService.hasApiKey else { return }
        let text = messageText
        messageText = ""
        Task {
            await aiService.sendMessage(text, windowState: windowState)
        }
    }

    private func takeAgentDraft() {
        guard let draft = windowState.agentDraft else { return }
        windowState.agentDraft = nil
        messageText = messageText.isEmpty ? draft : messageText + "\n\n" + draft
        isTextFieldFocused = true
    }

    private func showSettings() {
        browserManager.openSettings(tab: .ai)
    }

    private func showClearMessagesDialog() {
        browserManager.dialogManager.showDialog {
            StandardDialog(
                header: {
                    DialogHeader(
                        icon: "trash.fill",
                        title: "Clear Chat History?",
                        subtitle: "This will delete all messages in this conversation"
                    )
                },
                content: {
                    EmptyView()
                },
                footer: {
                    DialogFooter(
                        rightButtons: [
                            DialogButton(
                                text: "Cancel",
                                variant: .secondary,
                                action: {
                                    browserManager.dialogManager.closeDialog()
                                }
                            ),
                            DialogButton(
                                text: "Clear",
                                iconName: "trash",
                                variant: .primary,
                                action: {
                                    withAnimation(NookDesign.Motion.standard) {
                                        aiService.clearMessages()
                                    }
                                    browserManager.dialogManager.closeDialog()
                                }
                            )
                        ]
                    )
                }
            )
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.openURL) var openURL
    @State private var isHovered: Bool = false
    @State private var showCopied: Bool = false

    /// The person's own messages carry the space's accent; private windows keep the neutral one.
    private var accent: Color {
        windowState.isIncognito ? SpaceGradient.incognito.primaryColor : gradientColorManager.accentColor
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .assistant {
                    VStack(alignment: .leading, spacing: 0) {
                        if message.usedWebSearch {
                            HStack(spacing: 4) {
                                AnimatedIcon("globe", fallback: "globe", size: 16, ink: .secondary)
                                Text("Web Search")
                                    .font(NookDesign.Font.caption)
                                if !message.citations.isEmpty {
                                    Text("• \(message.citations.count) \(message.citations.count == 1 ? "source" : "sources")")
                                        .font(NookDesign.Font.caption)
                                }
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.green.opacity(0.15))
                            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(parseMarkdown(message.content).enumerated()), id: \.offset) { _, block in
                                block
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.top, message.usedWebSearch ? 6 : 10)
                        .padding(.bottom, message.citations.isEmpty ? 10 : 6)

                        if !message.citations.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Divider()
                                    .padding(.horizontal, 12)

                                Text("Sources")
                                    .font(NookDesign.Font.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)

                                VStack(spacing: 4) {
                                    ForEach(message.citations) { citation in
                                        CitationView(citation: citation)
                                    }
                                }
                                .padding(.horizontal, 12)
                            }
                            .padding(.bottom, 10)
                        }
                    }
                    .chatSurface(radius: NookDesign.Radius.lg)
                    // The copy button sits under the bubble, in space kept for it, so it never covers the text.
                    copyButton
                } else {
                    Text(message.content)
                        .font(NookDesign.Font.bodyRegular)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .nookControlSurface(tint: accent, in: NookDesign.Radius.shape(NookDesign.Radius.lg))
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.hover(hovering)) {
                isHovered = hovering
            }
        }
    }

    private var copyButton: some View {
        HStack {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCopied = false }
            } label: {
                HStack(spacing: 4) {
                    if showCopied { Image(systemName: "checkmark").frame(width: 16, height: 16) }
                    else { AnimatedIcon("copy", fallback: "doc.on.doc", size: 16, ink: .secondary) }
                    Text(showCopied ? "Copied" : "Copy")
                }
                .font(NookDesign.Font.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 22)
            }
            .buttonStyle(.plain)
            .opacity(isHovered || showCopied ? 1 : 0)
            Spacer(minLength: 0)
        }
        .frame(height: 22)
    }

    private func parseMarkdown(_ content: String) -> [AnyView] {
        var views: [AnyView] = []
        let lines = content.components(separatedBy: .newlines)
        var i = 0
        var inCodeBlock = false
        var codeBlockContent: [String] = []
        var codeBlockLanguage: String = ""

        while i < lines.count {
            let line = lines[i]

            if line.hasPrefix("```") {
                if inCodeBlock {
                    let code = codeBlockContent.joined(separator: "\n")
                    views.append(AnyView(codeBlockView(code, language: codeBlockLanguage)))
                    codeBlockContent = []
                    codeBlockLanguage = ""
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                    codeBlockLanguage = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                i += 1
                continue
            }

            if inCodeBlock {
                codeBlockContent.append(line)
                i += 1
                continue
            }

            if line.hasPrefix("### ") {
                views.append(AnyView(headerView(String(line.dropFirst(4)), level: 3)))
            } else if line.hasPrefix("## ") {
                views.append(AnyView(headerView(String(line.dropFirst(3)), level: 2)))
            } else if line.hasPrefix("# ") {
                views.append(AnyView(headerView(String(line.dropFirst(2)), level: 1)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                views.append(AnyView(bulletView(String(line.dropFirst(2)))))
            } else if line.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                let text = line.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
                views.append(AnyView(numberedView(text)))
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                views.append(AnyView(paragraphView(line)))
            }

            i += 1
        }

        return views
    }

    private func headerView(_ text: String, level: Int) -> some View {
        let fontSize: CGFloat = level == 1 ? 17 : level == 2 ? 15 : 14
        let weight: Font.Weight = level == 1 ? .bold : level == 2 ? .semibold : .medium

        return Text(parseInlineMarkdown(text))
            .font(.system(size: fontSize, weight: weight))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
    }

    private func paragraphView(_ text: String) -> some View {
        Text(parseInlineMarkdown(text))
            .font(NookDesign.Font.bodyRegular)
            .lineSpacing(4)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bulletView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(NookDesign.Font.body)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(parseInlineMarkdown(text))
                .font(NookDesign.Font.bodyRegular)
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func numberedView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
                .font(NookDesign.Font.body)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            Text(parseInlineMarkdown(text))
                .font(NookDesign.Font.bodyRegular)
                .lineSpacing(4)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func codeBlockView(_ code: String, language: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !language.isEmpty {
                Text(language)
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(NookDesign.Surface.fill)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
            }
            Text(code)
                .font(NookDesign.Font.secondary.monospaced())
                .foregroundStyle(.primary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NookDesign.Surface.fillPressed)
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        }
    }

    private func parseInlineMarkdown(_ text: String) -> AttributedString {
        do {
            return try AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        } catch {
            return AttributedString(text)
        }
    }
}

// MARK: - Citation View

struct CitationView: View {
    let citation: URLCitation
    @Environment(\.openURL) var openURL
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            if let url = URL(string: citation.url) {
                openURL(url)
            }
        }) {
            HStack(spacing: 6) {
                AnimatedIcon("link", fallback: "link", size: 16, ink: .secondary)
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(citation.domain)
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(isHovered ? .primary : .secondary)
                        .lineLimit(1)

                    if let title = citation.title, !title.isEmpty {
                        Text(title)
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                AnimatedIcon("arrow-up-right", fallback: "arrow.up.forward", size: 16, ink: .secondary)
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(isHovered ? .secondary : .tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                NookDesign.Radius.shape(NookDesign.Radius.sm)
                    .fill(isHovered ? NookDesign.Surface.fillPressed : NookDesign.Surface.fill)
            )
            .overlay(
                NookDesign.Radius.shape(NookDesign.Radius.sm)
                    .stroke(isHovered ? NookDesign.Surface.hairline : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.hover(hovering)) {
                isHovered = hovering
            }
        }
    }
}

private extension View {
    /// The chat's cards: a visible fill and a hairline edge, so the composer, starters and replies stand off the
    /// panel's tinted background instead of merging into it (the glass control surface was nearly invisible on dark).
    func chatSurface(radius: CGFloat) -> some View {
        let shape = NookDesign.Radius.shape(radius)
        return self
            .background(Color.primary.opacity(0.09), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.75))
    }
}


private struct ModelMenuRow: View {
    let title: String
    var checked = false
    var icon: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if checked { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
                    else if let icon { NookSymbol(icon, size: 16) }
                    else { Color.clear }
                }
                .frame(width: 16, height: 16)
                Text(title).font(NookDesign.Font.body).foregroundStyle(.primary)
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(hovering ? Color.primary.opacity(0.1) : .clear, in: NookDesign.Radius.shape(NookDesign.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
