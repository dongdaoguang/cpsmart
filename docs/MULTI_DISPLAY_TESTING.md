# Multi-display and input testing checklist

**English** | [简体中文](MULTI_DISPLAY_TESTING.zh-CN.md)

Use this checklist to prevent window, mouse, and trackpad behavior from working only on the primary display. Run the relevant checks whenever changing window placement, collection views, clicks, previews, search, pasting, or Accessibility code.

## Why this needs separate testing

macOS views, windows, screens, Core Graphics, and Accessibility use different coordinate ranges and directions. A secondary display above or to the left of the primary often has negative coordinates. A card's local coordinates also change after the collection view scrolls. Comparing a point from one coordinate system directly with `bounds` in another can produce a bug where the keyboard works but the mouse does not.

## Display layout matrix

Cover at least two layouts that the available hardware can form. At least one must have negative coordinates.

| Layout | Priority | What to watch |
|---|---:|---|
| Secondary display above the primary | Required | Negative vertical coordinates and menu bar placement |
| Secondary display to the left | Recommended | Negative horizontal coordinates |
| Secondary display to the right or below | Recommended | Cross-display boundaries |
| Displays with different scaling factors | Recommended | Retina / non-Retina coordinate conversion |
| Change the primary display | Before release | Behavior when `NSScreen.main` changes |

## Functional checks on each display

1. Move the pointer to the target display, press `⇧⌘V`, and confirm that the history window appears within that display's visible area.
2. Confirm that card browsing has focus by default and `Space` previews the selected card.
3. Use `←` / `→` to select the first, a middle, and the last card.
4. Starting from the first card, extend the selection to a middle card with `Shift` + `→`, then shrink it again. Confirm that the selection is contiguous, the active card remains visible, and the selection stays within the current filtered results.
5. Single-click the first, a middle, and the last card. Confirm that the blue selection outline moves and the content is copied.
6. Use `Shift`-click to extend a contiguous selection, `⌘`-click to add and remove cards, and `⌘A` to select all current results. Check middle and last cards after horizontal scrolling too.
7. Save and delete multiple selected results. Select and remove multiple items in a pinboard. Confirm every selected item is handled once and unselected items remain untouched.
8. Double-click cards in different positions. Confirm the window closes and the item is pasted into the previous app. With multiple cards selected, confirm the active card is pasted.
9. Press `Tab` to enter search and type a query. Press `Tab` again or click outside the search field to return to card browsing.
10. With an empty search field, press `Space` and confirm it opens the preview rather than inserting a space into search.
11. Click the type filters and confirm All, Text, Images, and Files can each be selected.
12. Open and close both the adaptive preview and full Quick Look preview. Continue using single-click, double-click, and the keyboard to confirm focus is preserved.
13. Open About cpsmart. Confirm the window appears on the pointer's display and that its icon, text, and scrolling work.
14. Open Shortcut Settings. Confirm the window is within the visible area of the pointer's display. Change Previous Item, Next Item, Search, Preview, Paste, and Close individually, then return to history and confirm each change takes effect immediately.
15. Create a duplicate shortcut assignment and confirm the error appears on the correct row. Use Swap and confirm both actions work; then test restoring one shortcut and Restore All Defaults.
16. Switch between the left/right and up/down arrow presets. Confirm Previous Item and Next Item always change as a pair. Try a global shortcut already used by another app and confirm the original shortcut keeps working.
17. Create at least two pinboards with different colors. Confirm tabs can be selected and the right-click menu can rename, recolor, and delete them. Use `⌘⌥1`–`⌘⌥3` to jump to Recent and both pinboards. Use `⌃Tab` / `⌃⇧Tab` to verify forward and backward cycling, including wrapping at either end.
18. Switch pinboards while typing in search and while a preview is open. Confirm search clears, the preview closes, and card focus returns. With a new-pinboard or rename dialog open, confirm those shortcuts do not steal form input.
19. Drag the first, a middle, and the last history card onto a pinboard tab. Confirm the tab highlights, history retains the item, and the saved content appears only once.
20. Within a pinboard, drag its first, a middle, and the last card to other positions. Confirm the insertion points and that the order persists after quitting and reopening the app.
21. Turn on search or a type filter in a pinboard and confirm drag reordering is disabled. Clear the filter and confirm reordering works again.

## Mouse and trackpad

- Test both tap-to-click and physical trackpad clicks, where the system's Tap to click setting permits. For each, verify a normal click, `Shift` range selection, and `⌘` add/remove selection.
- If a mouse is available, repeat single-click and double-click with it.
- Repeat dragging to a pinboard and reordering within a pinboard using both trackpad and mouse, including middle and last cards after horizontal scrolling.
- Both devices should produce the same AppKit mouse events. If only one fails, record the system input settings and event log before deciding why.

## Automated installed-package validation

Run this first for routine UI and input changes:

```bash
bash Scripts/validate_multi_display_package.sh
```

The script rejects an environment with only one display, no negative coordinates, or identical scaling factors on every display. When the requirements are met, it:

1. Builds an Intel + Apple Silicon Universal DMG and verifies its signature and both architectures.
2. Mounts the DMG and copies the app into a randomly named temporary validation directory under `/Applications` without replacing the installed version.
3. Launches the installed package on each display with isolated demo data, without reading or changing real clipboard history.
4. Moves the pointer to the target display and lets the production placement logic choose the display without a test-only override. It then uses AppKit events to test the first, middle, and last cards, including hit testing after scrolling.
5. Tests `Shift`-click, `⌘`-click to add/remove both inactive and active items, `Shift` + arrow keys, `⌘A`, delete, and `⌘Z` undo. It confirms that the copied item changes with the active item.
6. Confirms `⌘⌥1` / `⌘⌥2` and `⌃Tab` / `⌃⇧Tab` jump to and cycle forward/backward between Recent and the demo pinboard.
7. Checks the actual display owning the window, window bounds, and `visibleFrame`, including negative coordinates and mixed scaling factors.
8. Quits automatically, unmounts the DMG, and removes the temporary installation directory.

This reduces repeated regression work, but it cannot replace a manual check of the actual release package on both the primary and a secondary display. It also does not cover TCC permission after signing or entitlement changes, pasting into a real external app, or pixel-level judgments about fonts, colors, and shadows.

## Regression checks

- In `NSView.hitTest(_:)`, convert a point from parent-view coordinates into the current view's coordinates before comparing it with `bounds`.
- Do not query collection-view indexes inside `hitTest(_:)` if that query triggers hit testing again; it can recurse.
- Use `NSScreen.frame` / `visibleFrame` for the display containing the pointer when positioning windows.
- Real pasting requires Accessibility permission. An automated smoke test does not replace permission testing on an installed package.
- Record and test shortcuts on both the primary and secondary displays. When a Chinese input method has marked text, candidate selection, confirmation, and cancellation must not be intercepted by custom commands.

## Before release

1. Run the project tests.
2. Run `Scripts/validate_multi_display_package.sh` to build the Universal DMG and perform automated installed-package validation with two physical displays.
3. Install the app from the DMG into an isolated directory. Complete the core flows and visual checks once on each of the primary and secondary displays.
4. Confirm the new app's Accessibility permission is effective in System Settings and perform a real paste into another app.
5. If pixel-level visual effects changed, collect targeted visual evidence according to the project's Screenshot and Visual Verification rules.
6. Record the display layouts covered by the script and anything truly untested in the release validation record. Do not commit temporary process notes.
