# cpsmart

**English** | [简体中文](README.zh-CN.md)

cpsmart is a lightweight, native macOS clipboard history app. Your clipboard data stays on your Mac. It saves copied text, images, and files, and opens a horizontal history window at the bottom of the current display with `⇧⌘V` by default.

## Features

- Keep a local history of copied text, images, and files without uploading clipboard contents.
- Browse cards when the window opens; press `Tab` to enter or leave search by default.
- Reassign the global shortcut and window actions. Choose an arrow-key layout, swap conflicting bindings, and restore one or all defaults.
- Select items with `←` / `→`, preview text and images with `Space` (with an option to open the full Quick Look preview), and paste with `Return`.
- Single-click a card to select and copy it; double-click to return to the previous app and paste it.
- Select ranges with `Shift`, add or remove cards with `⌘`-click, and select all current search results with `⌘A`. Delete, remove, or save multiple items to a pinboard at once.
- Undo the most recent deletion or removal from a pinboard with `⌘Z`, preserving the original order.
- Move an item toward the front of history when you paste it into another app. Pinned items remain ahead of other items.
- Filter by All, Text, Images, or Files. Search ignores case, diacritics, and character width.
- See image thumbnails and the source app's name and icon.
- Pin items with `⌘P` by default. Ordinary clearing, history limits, and retention periods do not delete pinned items.
- Create named, color-coded pinboards for text, commands, images, and files you want to keep.
- Drag a history card onto a pinboard tab to save it, and drag cards within a pinboard to reorder them.
- Use light mode, dark mode, or the system appearance.
- Choose Follow System, English, or Simplified Chinese from the menu bar's Language submenu. The interface updates immediately and keeps your choice across launches.
- Automatically skip clipboard contents marked by standard concealed, transient, or auto-generated flags.
- Pause recording or launch cpsmart at login.
- Check GitHub for the latest stable release once a day by default, or check from the menu bar. Download and open the official DMG from the app when an update is available.

History keeps 200 items by default, up to approximately 25 MB in total; a single image may be up to 8 MB. History and pinboard data are stored separately:

```text
~/Library/Application Support/cpsmart/history.json
~/Library/Application Support/cpsmart/pinboards.json
```

Pinboards store independent snapshots, so clearing history does not remove their contents.

## Install and get started

### 1. Install the app

1. Download `cpsmart-<version>-universal.dmg` from [GitHub Releases](https://github.com/dongdaoguang/cpsmart/releases).
2. Double-click the downloaded DMG.
3. Drag `cpsmart.app` into the `Applications` folder in the opened window.
4. Wait for the copy to finish, then eject the DMG.
5. Open Finder → Applications and double-click cpsmart. A clipboard icon appears in the menu bar after launch.

> macOS does not create a desktop icon automatically. If you want one, right-click cpsmart in Applications, choose Make Alias, and move the alias to the desktop. Keep the actual app in Applications.

### 2. If macOS blocks the app

A release signed with Developer ID and notarized by Apple should generally open normally. Releases from cpsmart 1.9.0 onward use a consistent self-signed certificate; macOS may still show an “unidentified developer” warning the first time you open one:

1. In Finder → Applications, right-click cpsmart and choose Open.
2. If macOS still blocks it, open System Settings → Privacy & Security.
3. Find cpsmart in the Security section near the bottom and click Open Anyway.

Do not run unknown “unblock” scripts or disable macOS security checks system-wide.

### 3. Allow automatic pasting

cpsmart needs Accessibility permission only when you use `Return` or double-click a card to paste automatically:

1. Open System Settings → Privacy & Security → Accessibility.
2. Click the `+` below the app list.
3. Select cpsmart from Applications.
4. Turn on the switch beside cpsmart.
5. Quit cpsmart completely and reopen it.

Recording, searching, previewing, and copying still work without this permission; automatic pasting does not.

### 4. Confirm the installation

1. Copy some text in any app.
2. Press `⇧⌘V` to open clipboard history.
3. Single-click the card to select and copy it, or press `Return` or double-click it to paste into the previous app.

## Update an existing installation

1. Choose Check for Updates… from the menu bar. cpsmart also checks automatically once a day by default; you can turn off automatic checks from the same menu.
2. When an update appears, choose Download Update. cpsmart saves the official DMG to Downloads and opens it.
3. Click Quit cpsmart in the download-complete prompt, then drag the new cpsmart into Applications and choose Replace if macOS asks.
4. Reopen cpsmart.

The updater reads version tags only from the [latest stable release](https://github.com/dongdaoguang/cpsmart/releases/latest) of `dongdaoguang/cpsmart` and accepts HTTPS DMG download URLs only from that repository's release. It does not use the rate-limited GitHub API or upload clipboard history or other local content.

If automatic pasting actually stops working after an update, try pasting again and choose “Clear Old Record, Open Settings and Quit.” cpsmart then uses a system command to remove only its own old Accessibility entry, opens the appropriate settings page, and quits. It is normal for cpsmart to disappear from the list after that step. Click `+`, select `/Applications/cpsmart.app`, enable it, and reopen the app. macOS does not let the app grant this permission for you. Do not clear the permission during a normal update.

## Use cpsmart

These are the default shortcuts. Choose Shortcut Settings… from the menu bar to reassign them. Changes take effect immediately and persist across launches. The settings window can switch between left/right and up/down arrow layouts, swap duplicate assignments, and restore individual or all defaults. The direct pinboard and cycle shortcuts are fixed window-navigation shortcuts and cannot be reassigned.

| Action | Keyboard | Mouse |
|---|---|---|
| Open or close history | `⇧⌘V` | Menu bar → Open Clipboard History |
| Select and copy | `←` / `→` | Single-click a card |
| Select a range | `Shift` + `←` / `→` | `Shift`-click a card |
| Add or remove from selection | — | `⌘`-click a card |
| Select all current results | `⌘A` | — |
| Paste | `Return` | Double-click a card |
| Preview the active item | `Space` | — |
| Search / return to browsing | `Tab` | Click in / outside the search field |
| Pin | `⌘P` | — |
| Save to a pinboard | `⌘D`, then choose a board | Drag a history card to a pinboard tab, or click Save to… |
| Jump to Recent / a pinboard | `⌘⌥1`–`⌘⌥9` | Click a pinboard tab |
| Cycle through pinboards | `⌃Tab` / `⌃⇧Tab` | Click a pinboard tab |
| Reorder pinboard items | — | Drag cards horizontally within a pinboard |
| Delete selected items | `⌘⌫` | — |
| Undo the last deletion / removal | `⌘Z` | — |
| Filter by type | `⌘1`–`⌘4` | Click a type filter |
| Clear search or close | `Esc` | — |

Ordinary Clear History keeps pinned items. Hold `⌥` while opening the menu to choose Clear All History (Including Pinned).

Click `+` to the right of the pinboard tabs to create a pinboard. `⌘⌥1` opens Recent, `⌘⌥2`–`⌘⌥9` open the first eight pinboards, and `⌃Tab` / `⌃⇧Tab` cycle through them. Right-click a pinboard tab to rename it, change its color, or delete it. Within a pinboard, `⌘⌫` removes all selected items. With multiple items selected, preview and paste still use the card with active focus. You cannot reorder pinboard items while search or a type filter is active; clear the filter to resume dragging.

## Develop and test

Requires macOS 13 or later and Apple Command Line Tools.

```bash
swift build
bash Scripts/run_tests.sh
```

With at least two physical displays connected, this command builds a Universal DMG, installs it in an isolated temporary directory under `/Applications`, and checks window placement, clicks on the first, middle, and last cards, Shift selection, Select All, and delete/undo on each display:

```bash
bash Scripts/validate_multi_display_package.sh
```

Validation uses isolated demo data and does not read or change your real clipboard history. It moves the pointer to the center of each display while running. Automated checks do not replace a manual check of the release package on both the primary and a secondary display. They also do not cover Accessibility authorization or real pasting between apps.

See the [multi-display and input testing checklist](docs/MULTI_DISPLAY_TESTING.md) for the full manual checks.

## Build a DMG

The version and build number are stored in `VERSION` and `BUILD_NUMBER`. Update both files and the [changelog](CHANGELOG.md) before a new release.

For a local test package:

```bash
bash Scripts/build_dmg.sh --local
```

The script builds optimized Intel and Apple Silicon binaries, combines them into a Universal 2 app, and writes:

```text
dist/cpsmart-<version>-universal.dmg
```

Without a Developer ID, the release maintainer can use a long-lived self-signed identity:

```bash
bash Scripts/build_dmg.sh --self-signed \
  --sign-identity "cpsmart Release Signing"
```

Users do not need to create or install a certificate. A consistent self-signed identity can preserve the app's code identity across versions, but it does not replace Developer ID signing, notarization, or Gatekeeper trust. See [self-signed release instructions](docs/SELF_SIGNED_RELEASE.md) for creating and backing up the certificate, importing it for collaborators, and checking permissions across versions.

For a Developer ID signed and notarized release:

```bash
bash Scripts/build_dmg.sh --release \
  --sign-identity "Developer ID Application: <name> (<Team ID>)" \
  --notary-profile "cpsmart-notary"
```

Formal Developer ID mode rejects ad hoc signing. It submits the DMG with `notarytool`, waits for the result, and staples the notarization ticket. Self-signed mode does not submit for notarization. Never commit signing certificates, private keys, `.p12` files, or notarization credentials.

## Release process

1. Update `VERSION`, `BUILD_NUMBER`, and the [changelog](CHANGELOG.md).
2. Build and run the tests.
3. Build and validate the release DMG.
4. Commit the release changes and create a descriptive tag, for example `v1.9.0`.
5. Push the branch and tag, then create a stable GitHub Release (not a prerelease).
6. Upload a DMG named `cpsmart-<version>-universal.dmg` and include the corresponding changelog and installation instructions from this page. The built-in updater reads the version tag and prefers this Universal DMG.

## Contribute

For forking, branching, testing, and pull requests, see [CONTRIBUTING.md](CONTRIBUTING.md). GitHub calls these Pull Requests (PRs); Merge Request (MR) is GitLab's term.

## Privacy

Clipboard history can contain sensitive information. cpsmart skips content with standard sensitive markers, but some apps do not set those markers correctly. Pause recording while handling sensitive data, and clear history regularly.

Clipboard history always stays on your Mac. When automatic update checks are enabled, cpsmart checks GitHub for the latest stable release tag at most once a day. Update-check requests contain no clipboard content. You can disable automatic checks from the menu bar.
