# Vega changelog

What Vega changes on top of [Nook](https://github.com/nook-browser/Nook). Nook's own changes reach Vega through the daily upstream sync; they're in [CHANGELOG.md](CHANGELOG.md) and [Nook's releases](https://github.com/nook-browser/Nook/releases).

## Vega 1.7.3 (2026-11-14)

Icons that move, a calmer AI chat, and a reader view.

### New
- **Animated icons.** The sidebar, tabs, library, Settings and more use icons that move when you point at them. Menus show the same icons, still.
- **Reader view.** View › Show Reader (⌥⌘R), or the book button in the address bar, shows an article without the clutter: text size, a light, sepia or dark page, and Esc to leave. The page underneath is untouched.
- **Ask Vega, redone.** A clean header that names the page you're asking about, one-tap starters, a clearer input with the model picker lined up under it, and a copy button under each reply that never covers text.

### Faster
- **Lighter ad blocker.** Vega now hands the web engine at most 150,000 blocking rules, so pages open faster. The 108,000-rule malware list is optional.

### Fixes
- A page's own HTML no longer downloads when Vega reopens with a tab restored, or when you Option-click a link inside Peek.
- A download with no address no longer sits in the library keeping its ring on the library button.
- The Peek card's site name and buttons stay readable over any window; the buttons are now round glass buttons beside the card.
- The AI chat button is back in the bottom bar, with the space dots closer together.

## Vega 1.7.2 (2026-11-13)

Faster page loads, and a new home for updates.

### Fixes
- **Pages load faster.** Vega no longer stalls on every navigation while it re-checks the ad blocker's scripts.
- Updates now come from Vega's renamed GitHub repository. Copies installed before 1.7.2 may need a fresh download of this version.

## Vega 1.7.1 (2026-11-13)

Small fixes to updating.

### Updates
- **Check for Updates…** in the Vega menu works again.
- After an update, the "What's new" card opens the Updates page in Settings.
- The update window no longer shows a web page of release notes.

## Vega 1.7.0 (2026-11-13)

Your passwords, and your setup on every Mac.

### Passwords
- **Save and fill logins.** Vega offers to save a login after you sign in, and lists your saved logins under a login field. Nothing is filled until you click one. Private windows never save or fill.
- **Kept in your Mac's Keychain.** The new Passwords page in Settings opens only after Touch ID or your Mac's password, every time.
- **Manage them:** search, copy, edit, delete, add by hand, and import a file exported from Chrome or Safari.

### Sync between your Macs
- **Sync my Macs** keeps your spaces, favorites and pinned tabs the same everywhere. Open tabs stay on each Mac.
- **Choose where it syncs:** iCloud Drive, or a Google account (the files go in a hidden folder of your Google Drive that only Vega can open). Both work without any paid account.
- **Passwords sync too, encrypted** with a passphrase only you know, so neither iCloud nor Google can read them.

### Updates
- A new **Updates** page shows your version, an automatic-update switch, Check for Updates, and what changed in every version.
- The sidebar notice names the new version and links to What's New.

### Also
- File › New Little Window (renamed from its old name).

## Vega 1.6.0 (2026-11-13)

The first public Vega release, built on Nook 1.6.0.

### Sidebar and browsing
- **Sidebar** reworked: 247 pt wide, 32 pt buttons, tighter insets and title row, a cleaner address field, an 8 pt page frame.
- **Hover sidebar** (when the sidebar is collapsed) carries the window buttons inside the panel.
- **Command palette** redesigned: centred dark glass, your open tabs listed before you type (from every space, each labelled with its space), smaller text, an accent-filled selected row.
- **Page loading** shows as a tint in the space's colour sweeping across the address field.
- **Site Controls panel** redesigned, with per-site settings: JavaScript on or off, the mobile version of a site, automatic picture-in-picture.
- **Extensions:** pinned extensions show in the address field on hover; right-click one for Remove, Pin/Unpin, Manage and Permissions.
- **Notes** in the sidebar.
- **Menu bar commands:** Clear Today, Reset All Tabs in This Space, Reveal Tab in Sidebar, Stay on Top, Copy URL as Quote, Save Page As, a small floating window, Expand/Collapse Pinned Tabs, View Archive and Clear Archive, Add Split View, focus the next or previous split pane, Show Full URL, Merge All Windows and more.
- **Favorites** with 16 pt icons and a thinner page frame.

### New features
- **Picture-in-picture** opens in a floating window by default; drag it into the sidebar and Vega remembers, pull it out and it floats again.
- **Cast** (File › Cast…): AirPlay the page's video from a bar in the sidebar.
- **Capture** (File › Capture Visible Area / Capture Full Page) to PNG.
- **Media** in the Library: images and videos you downloaded, as a searchable grid.
- **Downloads:** a context menu (Copy Image, Messages, AirDrop, Preview, Show in Finder, Hide, Move to Trash), drag a file out of the list anywhere, a download ring in the footer.
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
- Notarization (no "Open Anyway" step) and web push notifications need the paid Apple Developer Program; the release script turns them on once it's set up.
