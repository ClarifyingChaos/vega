# Vega changelog

What Vega changes on top of [Nook](https://github.com/nook-browser/Nook). Nook's own changes reach Vega through the daily upstream sync; they're in [CHANGELOG.md](CHANGELOG.md) and [Nook's releases](https://github.com/nook-browser/Nook/releases).

## Vega 1.6.0 (2026-11-13)

The first public Vega release, built on Nook 1.6.0.

### Feels like Arc
- **Sidebar** at Arc's measurements: 247 pt wide, 32 pt buttons, Arc's insets and title row, window buttons and tiles in Arc's positions, a cleaner address field, an 8 pt page frame.
- **Hover sidebar** (when the sidebar is collapsed) carries the window buttons inside the panel, like Arc.
- **Command palette** like Arc's: centred dark glass, your open tabs listed before you type (from every space, each labelled with its space), Arc's text sizes, an accent-filled selected row.
- **Page loading** shows as a tint in the space's colour sweeping across the address field.
- **Site Controls panel** redone after Arc's, with per-site settings: JavaScript on or off, the mobile version of a site, automatic picture-in-picture.
- **Extensions:** pinned extensions show in the address field on hover; right-click one for Arc's menu (Remove, Pin/Unpin, Manage, Permissions).
- **Notes** in the sidebar.
- **Arc's menu bar:** Clear Today, Reset All Tabs in This Space, Reveal Tab in Sidebar, Stay on Top, Copy URL as Quote, Save Page As, Little Arc window, Expand/Collapse Pinned Tabs, View Archive and Clear Archive, Add Split View and more.
- **From Dia:** focus the next or previous split pane, Show Full URL, Merge All Windows, Dia's thinner page frame.
- **Favorites** at Arc's 16 pt icon size.

### New features
- **Picture-in-picture** opens in a floating window by default; drag it into the sidebar and Vega remembers, pull it out and it floats again.
- **Cast** (File › Cast…): AirPlay the page's video from a bar in the sidebar.
- **Capture** (File › Capture Visible Area / Capture Full Page) to PNG.
- **Media** in the Library: images and videos you downloaded, as a searchable grid.
- **Downloads like Arc:** a context menu (Copy Image, Messages, AirDrop, Preview, Show in Finder, Hide, Move to Trash), drag a file out of the list anywhere, a download ring in the footer.
- **Blank Window** (File menu) and **Change Profile** (Spaces menu).

### Settings
- Redesigned to match macOS 27 System Settings: glass sidebar with search, a header card per page, back and forward like System Settings, calmer grouped pages.
- Profiles get an info sheet (rename, which spaces use it, website data); Site Search uses a + / − list; clearing history asks first.
- Reopens on the page you last used.

### Look and accessibility
- Liquid Glass for the palette, address panel, Site Controls and floating chrome, solid under Reduce Transparency.
- Reduce Motion and Increase Contrast respected throughout; VoiceOver names for favorites; no text below the 10 pt minimum.
- Sharp, same-size favicons with no coloured glow; icons found for sites that hid them.

### Fixes
- Favicons that were missing or blurry on favorites and pinned tabs.
- The sidebar's back, forward and reload buttons no longer vanish when the sidebar is narrow, and resizing it no longer drags the whole window.
- The downloads list stays open while you use its menu, drag a file out, or trash one.
- A private-window favicon leak, notes not saved on quit, and an icon cache that grew without limit.

### Under the hood
- Its own app: bundle ID `com.vega.browser` and the `vega://` scheme. Data from an existing Nook install moves over on first launch.
- Updates itself (Sparkle) from this repository's releases.
- One-command releases (`scripts/release.sh`, see [docs/RELEASING.md](docs/RELEASING.md)) and a daily sync with upstream Nook.

### Not yet
- Notarization (no "Open Anyway" step), web push notifications and password autofill: they need the paid Apple Developer Program; the release script turns them on once it's set up.
