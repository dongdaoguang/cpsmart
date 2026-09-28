# Changelog

**English** | [简体中文](CHANGELOG.zh-CN.md)

This project follows semantic versioning.

## Unreleased

## 1.12.0 — 2026-09-28

### Added

- Added English and Simplified Chinese interface text and documentation, with a Language menu for switching immediately between Follow System, English, and Simplified Chinese.

## 1.11.0 — 2026-08-27

### Added

- In the history window, use `⌘⌥1`–`⌘⌥9` to jump directly to Recent and the first eight pinboards, or `⌃Tab` / `⌃⇧Tab` to cycle forward and backward.

## 1.10.0 — 2026-08-27

### Added

- Select a contiguous range with `Shift`, add or remove items with `⌘`-click, and select all current filtered results with `⌘A`.
- Delete, remove from pinboards, and save to pinboards in batches. Preview and paste always act on the current active card.
- Undo the most recent deletion or removal from a pinboard with `⌘Z`, restoring the original order.

### Fixed

- Fixed card mouse hit targets shifting after horizontal scrolling, and made coordinate conversion consistent across the primary display, secondary displays, and displays with negative coordinates.
- Fixed the copied target failing to update when `⌘`-click removes the active item, and the active item being lost when a selection became inconsistent.
- Prevented accidentally dragging a single card while multiple items are selected. Temporary contents are released when the save-to-pinboard menu closes, avoiding long-term retention of large image data.

### Improved

- Split history-window selection, filtering, preview, pinboard interaction, drag rules, view components, and installed-package validation into separate modules to reduce regression risk.
- Moved core tests to a standard SwiftPM XCTest target, with a compatible runner for systems that only have Command Line Tools.
- Added repeatable validation of a real installed package on two displays, covering negative coordinates, mixed scaling, first/middle/last cards, multiple selection, undo, search, and preview.

## 1.9.0 — 2026-08-26

### Added

- Recent now uses least-recently-used ordering: after `Return` or double-click sends a paste to the target app, that entry moves to the front of its group and the order is saved. Single-click copying, previewing, insufficient permission, and an unavailable target do not change the order. Pinned items still take priority.
- Added GitHub Release update checks, automatically once a day by default or manually from the menu bar. Available updates can download and open the official Universal DMG directly.
- Added an Automatic Update Checks menu toggle. Update alerts appear on the display containing the pointer, including secondary displays with negative coordinates.

### Improved

- Replaced the post-download message with clear three-step installation instructions and added guidance for repairing permissions when automatic pasting fails.
- When automatic paste permission fails, added “Clear Old Record, Open Settings and Quit.” It clears only cpsmart's old Accessibility entry and opens System Settings; the user must still enable the permission switch.
- Added a Quit cpsmart button to the download prompt. Permission repair also quits after opening Settings, avoiding an alert that blocks installation or repeated attempts in the old process before permission takes effect.
- Added a consistent, long-lived self-signed release mode and a secure import process for collaborators. The permission-repair action was renamed “Clear Old Record, Open Settings and Quit” to make clear that normal updates should not proactively reset permission.

## 1.8.0 — 2026-08-26

### Added

- A Shortcut Settings window where every shortcut can be recorded and changed, with conflict swapping, restore-one and restore-all actions, and persistence across launches.
- Pinboards: a fixed History tab and multiple custom boards with names, colors, rename, and delete. History cards can be dragged into a pinboard with copy semantics, and pinboard cards can be reordered by dragging. Added a Save to… menu and `⌘D`.

### Fixed

- Fixed `Space` accidentally opening preview while the search field was focused, preventing multiword queries. Space always enters a character in the search field, even when rebound to another action elsewhere.
- Fixed inability to type a name when creating or renaming a pinboard.
- Fixed the compact preview occasionally expanding into the large Quick Look panel during rapid preview switching.
- Fixed Quick Look panel closing behavior: `QLPreviewPanel` does not respond to `orderOut`, and showing a popover while it closes could revive it. Switching cards with arrow keys no longer leaves both preview types open.
- Fixed content scrolling under the top-left window controls in Shortcut Settings, and corrected the vertical alignment of the Modified badge.
- Fixed preview failing to follow mouse selection of another card or a pinboard switch while Quick Look was open.
- Fixed the About page failing to reflect shortcut changes and its GitHub link not opening.
- Fixed content scrolling under the top-left window controls in About and Shortcut Settings by using safe-area constraints, so it cannot enter the title-bar area.
- Fixed a duplicated row in the About page's two-column shortcut list.
- Fixed a missing name field in the new-pinboard form: after moving the color dots into a stack layout, the field had no width constraint and collapsed into a thin line.
- Paste target and focus restoration on closing the window now follow the user's most recently active window. If another app is clicked while history is open, pasting goes to that app instead of the app that was active when history opened.
- Preview now behaves as a session: after `Space` opens it, arrow-key browsing continues to preview text and images. Switching to a file suspends preview; returning to text or an image resumes it. Press `Space` or `Esc` again to end the session.
- Fixed stale search placeholder text after deleting a pinboard or reopening the window.
- Fixed the global shortcut being swallowed during the history window's closing animation.

### Improved

- Renamed the History tab to Recent.
- Changed the save button to a star icon that stays in the top-right corner; it is disabled rather than hidden in pinboard view.
- The save-to-pinboard menu (`⌘D`) opens below the selected card and shows a Save to Pinboard heading with each board's color dot.
- The new-pinboard color choices are now a directly clickable row of dots.
- Pinboard tabs now use a flat filled style, centered color dot, hover feedback, and no harsh border in light mode.
- Removed the arrow-key preset switch from Shortcut Settings and changed the restore-one control to a text button.
- Changed the pinboard search placeholder to “Search in {board name}” to make clear that search covers only the current board.
- Removed file previews: Quick Look showed only an icon for most files, while asynchronous panel resizing caused visible flicker. Text and images can still expand to full Quick Look.

## 1.7.0 — 2026-08-25

### Added

- Card browsing is the default when opening history; use `Tab` to enter or leave search.
- Preview text, images, and files with `Space`. Text and images size to their content and can expand to full Quick Look.
- Pin entries with `⌘P`. Pinned entries are exempt from ordinary clearing and retention limits.
- Show the source app and icon for copied content.
- Added All, Text, Images, and Files filters.
- Added light, dark, and system appearance options.

### Improved

- Single-click selects and copies a card; double-click pastes it directly. The first click works even when the window is inactive.
- Fixed mouse and trackpad clicks missing cards when the secondary display is above or to the left of the primary.
- Clicking outside the search field returns to card browsing, and `Space` previews when search is empty.
- The Accessibility permission prompt now gives the full System Settings path and can open the settings page.
- Expanded About cpsmart into a native usage guide and adopted the new ceramic clipboard icon throughout.
- Ordinary clearing retains pinned entries. Hold `⌥` while opening the menu to clear everything.
- The DMG build script now reads the version file and distinguishes local packages from Developer ID signed and notarized releases.

### Removed

- Removed the confusing app-exclusion menu and its background logic.
