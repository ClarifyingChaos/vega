<div align="center">
  <h1><b>Vega</b></h1>
  <p>
    A fast, sidebar-first browser for macOS.
  </p>
</div>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-15.5+%20·%20Apple%20Silicon-blue" alt="macOS 15.5+, Apple Silicon"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0-green" alt="GPL-3.0"></a>
  <a href="https://github.com/ClarifyingChaos/vega-browser/releases/latest"><img src="https://img.shields.io/github/v/release/ClarifyingChaos/vega-browser?label=release" alt="Latest release"></a>
</p>

<p align="center">
  <a href="https://github.com/ClarifyingChaos/vega-browser/releases/latest"><img src="https://img.shields.io/badge/Download%20for-macOS-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS"></a>
</p>

## Install

1. Download `Vega-X.Y.Z.dmg` from the [latest release](https://github.com/ClarifyingChaos/vega-browser/releases/latest) and drag Vega to Applications.
2. Test builds aren't notarized yet, so the first open is blocked once: open Vega, then System Settings › Privacy & Security › **Open Anyway**.
3. After that Vega updates itself (Vega › Check for Updates… checks now).

Feedback and bugs: [Issues](https://github.com/ClarifyingChaos/vega-browser/issues).

## Features

- **Sidebar-first navigation**: vertical tabs, spaces, favorites and pinned tabs that stay out of your way, with a command palette that lists every open tab.
- **Site Controls** with per-site settings: JavaScript, the mobile version of a site, automatic picture-in-picture.
- **Picture-in-picture** that floats by default and docks in the sidebar when you drag it there. **Cast** to AirPlay, page **Capture**, and a **Media** grid of your downloads.
- **Passwords** saved in your Keychain, filled only when you pick them, locked behind Touch ID, and importable from Chrome or Safari.
- **Sync** of spaces, favorites and encrypted passwords between your Macs through iCloud Drive or a Google account. No paid account needed.
- **Built-in ad and tracker blocking**, notes in the sidebar, and richer downloads.
- **Settings that match macOS 27 System Settings**, Liquid Glass, Reduce Motion, Increase Contrast and VoiceOver support.
- **Updates itself**: Vega › Check for Updates… or just keep it open.

<p align="center">
  <img src="assets/screenshot.png" alt="Vega screenshot" width="900">
</p>

Full list of changes: [VEGA_CHANGELOG.md](VEGA_CHANGELOG.md).

## Launchers

Raycast, Alfred and scripts can drive Vega with `vega://` links. They are off until you turn on Allow vega:// links in Settings > Links.

- Open a page: `open "vega://open?url=https://example.com&space=Work&reuse=1"` (`space` and `reuse` are optional; `reuse=1` selects a tab that already shows the page)
- Search: `open "vega://search?q=swift%20concurrency&space=Work"`
- Switch space: `open "vega://space?name=Work"`

A space is matched by its exact name (any case) or its UUID. Only `http` and `https` pages open.

## Getting Started

### Download
[![Download for macOS](https://img.shields.io/badge/Download%20for-macOS-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/ClarifyingChaos/vega-browser/releases/latest)

### or, Build from Source

#### Prerequisites
- macOS 15.6 (Sequoia) or later, Apple Silicon. Xcode 26 needs 15.6; the built app runs on 15.5 and later
- On-device AI chat and Tab Organizer require macOS 26 or later with Apple Intelligence enabled
- [Xcode](https://developer.apple.com/xcode/) 26 or later, with the Metal Toolchain component (Xcode 26 no longer bundles it)
```bash
git clone https://github.com/ClarifyingChaos/vega-browser.git
cd vega-browser
xcodebuild -downloadComponent MetalToolchain
open Nook.xcodeproj
```

Vega builds for Apple Silicon only: the bundled adblock-rust framework ships an arm64 slice and nothing else. Xcode resolves the Swift packages on open.

You’ll need to set your personal Development Team in Signing to build locally.

## How Vega is kept

- `main` is Vega. `develop` mirrors the upstream project and is synced daily; changes arrive as a pull request into `main`.
- Fork-specific code is marked `// FORK:` so upstream merges stay readable.
- Releasing an update is one command: see [docs/RELEASING.md](docs/RELEASING.md).

## Project Structure

```
vega-browser/
├── App/                       # Entry point, AppDelegate, window scene, menu commands
├── Packages/                  # Local Swift packages shared with the planned iOS port
│   ├── NookTabsCore/          # Tab tree model: spaces, items, ordering, on-disk store
│   ├── NookSettings/          # Settings service and every persisted value type
│   ├── NookDesign/            # Design tokens: radii, spacing, type, motion, surfaces
│   ├── NookBlocker/           # Content blocker: filter lists, adblock-rust conversion, cosmetic engine
│   ├── NookTweaks/            # Site tweaks: YouTube, Facebook, social downloads, SponsorBlock, routing
│   ├── NookWeb/               # Tabs controller, page sessions, windows, history, favicons, search
│   └── NookUI/                # Shared SwiftUI: rows, context menus, spaces list, toasts, settings tabs
├── Nook/
│   ├── Managers/              # Feature managers (macOS side)
│   │   ├── BrowserManager/    # Central coordinator; conforms to the package seams
│   │   ├── ExtensionManager/  # WKWebExtension support
│   │   ├── AIManager/         # AI chat providers, MCP client, browser tools
│   │   ├── DevMCPServer/      # Local MCP server for driving the app from a coding agent
│   │   ├── TabOrganizerManager/ # On-device tab grouping with Apple Intelligence
│   │   ├── WebViewCoordinator/  # Web view pool for multi-window display
│   │   ├── DownloadManager/   # File downloads
│   │   ├── DialogManager/     # Modal dialogs
│   │   ├── PeekManager/       # Quick preview overlay
│   │   ├── SplitViewManager/  # Split-screen tab viewing
│   │   └── ...
│   ├── Models/                # macOS-only models and SwiftData entities
│   ├── Components/            # SwiftUI views: sidebar, website view, settings, drag and drop, dialogs
│   ├── Browser/               # macOS-only slice of the tab controller
│   ├── Utils/                 # WebKit helpers and utilities
│   └── ThirdParty/            # adblock-rust FFI crate and other embedded dependencies
├── CommandPalette/            # Command palette UI
├── Navigation/                # Sidebar structure: header, bottom bar, spaces list
├── Onboarding/                # First-run flow
├── NookiOS/                   # iOS app target, not released yet
├── UI/                        # Shared buttons and controls
├── docs/                      # Ad blocker architecture notes
├── scripts/                   # Filter list refresh, scriptlet and redirect generators, checks
└── assets/                    # Static assets
```

### Architecture Overview

Vega follows a manager-based architecture where:
- **Managers** handle business logic and coordinate between different parts of the app
- **Models** represent data and state using Swift's `@Observable` macro
- **Components** are SwiftUI views that reactively update based on model changes
- **BrowserManager** acts as the central coordinator, connecting all managers together
- **Packages** hold the model, blocker, tweak and shared view code that has no AppKit dependency, so it can be reused by an iOS app


---

<div align="center">

## Star History

<a href="https://www.star-history.com/#ClarifyingChaos/vega-browser&type=date&legend=bottom-right">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=ClarifyingChaos/vega-browser&type=date&theme=dark&legend=bottom-right" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=ClarifyingChaos/vega-browser&type=date&legend=bottom-right" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=ClarifyingChaos/vega-browser&type=date&legend=bottom-right" width="600" />
 </picture>
</a>

</div>

---

### LICENSES
With the exception of third-party libraries in Nook/ThirdParty, all code is under the GPL 3.0 License. The relevant third-party code is licensed per-folder under a variety of free, open-source software licenses. Vega is a fork and keeps the upstream project's copyright notices.
