# User-configurable shortcuts: research findings and implementation plan

**English** | [简体中文](KEYBOARD_SHORTCUT_CUSTOMIZATION_PLAN.zh-CN.md)

> Status: The core feature and redesigned settings UI are implemented. Automated tests, Debug and Release builds, and a visual check on the currently available display have been completed; interactions on both primary and secondary displays with a real installed package remain unverified. This document retains the product scope, technical design, and acceptance criteria.

## Conclusion

User-configurable shortcuts are feasible without requesting additional system permissions such as Accessibility or Input Monitoring.

The change should go beyond replacing the current `keyCode` constants with values from `UserDefaults`. cpsmart has two keyboard-handling mechanisms:

- Carbon `RegisterEventHotKey` registers the global `⇧⌘V` shortcut.
- An AppKit `NSEvent` local monitor handles browsing, search, preview, paste, and other shortcuts inside the history window.

A window shortcut can also behave differently while browsing, typing in search, composing text with a Chinese input method, or using Quick Look. The proposed sequence is to build one shortcut model, matcher, and conflict validator before adding settings UI. This keeps behavior, window hints, menu titles, and the About page consistent when a user changes a binding.

## Proposed first-version scope

The first version lets a user assign one key combination per action. Mouse and trackpad operations remain fixed alternatives. User-defined multiple combinations for one action and modifier-only bindings are out of scope.

| Group | Action | Current default | Configurable in v1 | Notes |
|---|---|---:|---:|---|
| Global | Open or close history | `⇧⌘V` | Yes | Must include at least one of `⌘`, `⌥`, or `⌃` to avoid intercepting normal typing |
| Browsing | Select previous item | `←` | Yes | Can change to a non-text key such as `↑` |
| Browsing | Select next item | `→` | Yes | Can change to a non-text key such as `↓` |
| Browsing/search | Switch between cards and the search field | `Tab` | Yes | Must still protect marked input-method text while searching |
| Action | Paste selection | `Return` | Yes | Numeric keypad Enter also works by default; restoring defaults should preserve this |
| Action | Open or close Quick Look | `Space` | Yes | The same key should close it when Quick Look is open |
| Action | Pin or unpin | `⌘P` | Yes | Only works in the history window |
| Action | Delete selected records | `⌘⌫` | Yes | `⌘⌦` also works by default and should return when defaults are restored |
| Filter | All / Text / Images / Files | `⌘1`–`⌘4` | Yes | Four independent bindings, each checked for conflicts |
| Window | Clear search or close | `Esc` | Yes | Keep the context-sensitive behavior: clear search first, then close |

These are not bindable actions:

- Typing ordinary text in the search field; this is text input, not a shortcut action.
- Standard system menu commands such as `⌘Q` to quit.
- Mouse single-click, double-click, and trackpad behavior.
- Hardware keys such as volume, brightness, and eject, which may be intercepted below the app.

## Interaction design

### Entry point

Add Shortcut Settings… to the menu bar menu. Prefer the display containing the pointer for the settings window, and place it using that display's `visibleFrame` instead of assuming the primary display.

Use the same native frosted appearance, rounded cards, and blue accent as the history window. Group actions by frequency rather than flattening all 13 actions into a table:

- Emphasize the global activation shortcut separately so it does not get lost in a list.
- Offer both `← / →` and `↑ / ↓` presets under Browsing and Navigation while still allowing each action to be adjusted.
- Show Paste, Preview, and Close directly under Common Actions.
- Put Pin, Delete, and filters in an expandable More Shortcuts section; expand it automatically if any binding inside it has changed.
- Display current shortcuts as physical keycaps, with a state badge and individual restore control for changed items.
- Show the count of changed bindings in a fixed footer, along with Restore All Defaults. Use the system close button rather than a redundant Done button.

### Record a key combination

1. Clicking a shortcut control puts it into a “Press a new shortcut” state.
2. Clicking the recorder again or clicking outside cancels recording. `Esc` itself must be recordable as a shortcut.
3. Validate a recorded combination before applying and saving it.
4. On a conflict or registration failure, show the reason on the same row and keep the original shortcut working. If two in-app actions share a binding, offer to swap their shortcuts.
5. Do not allow an action to be cleared to None, which could remove its keyboard path unexpectedly. If disabling actions is needed later, design a separate toggle.

### Accepted combinations

- Non-text keys such as arrows, Tab, Return, Space, Esc, and Delete may be used without modifiers.
- Letters, digits, and punctuation require `⌘`, `⌥`, or `⌃` so they do not trigger commands while a user types into search.
- Global shortcuts require `⌘`, `⌥`, or `⌃`; Shift may be an additional modifier.
- Reject modifier-only combinations, Caps Lock, and media keys that the app does not receive.
- Before matching, retain only `⌘⌥⌃⇧` and ignore device-state flags such as Caps Lock and numeric keypad, so the same combination behaves consistently across keyboards.

## Conflicts and failures

### Conflicts inside the app

Use a strict, understandable rule: no two configurable actions may have exactly the same combination, even if they appear to be active in different UI states. This avoids hidden conflicts if the state machine changes later. When settings detects an in-app conflict, offer Swap. Validate both resulting bindings together before swapping so the change cannot be applied halfway.

The global activation shortcut must also differ from window actions, because its global registration may receive the key first even when cpsmart is in front.

### Conflicts with another app or the system

Actually attempt to register a global shortcut before saving it. The proposed switch is transactional:

1. Temporarily unregister the current global shortcut on entering recording so Carbon cannot intercept the same combination.
2. After recording, try to register the candidate shortcut.
3. Save the setting and keep the new registration only after registration succeeds.
4. On cancellation or failure, immediately register the original shortcut again and explain that the candidate may already be used by the system or another app.

A hard-coded list of reserved system shortcuts cannot be the sole test: actual conflicts depend on installed apps and system settings. Hard-coded rules should reject only clearly unsafe combinations; the registration result is authoritative.

### Restore defaults and arrow presets

Restore Defaults should also be transactional. First confirm the default global shortcut can be registered, then clear all custom values and refresh every UI surface in one operation. If another app currently uses `⇧⌘V`, keep the existing configuration intact and ask the user to resolve the conflict before restoring.

Restoring one action first checks whether its default conflicts with other current bindings. For the global action, it also tries registering the default combination. An arrow preset must validate and write Previous Item and Next Item as one batch, with no intermediate state where only one direction has changed.

## Data model

Use stable action identifiers instead of Chinese titles as storage keys:

```swift
enum ShortcutActionID: String, CaseIterable, Codable {
    case toggleHistory
    case selectPrevious
    case selectNext
    case toggleSearchFocus
    case pasteSelection
    case toggleQuickLook
    case togglePin
    case deleteSelection
    case filterAll
    case filterText
    case filterImage
    case filterFiles
    case clearSearchOrClose
}

struct ShortcutGesture: Codable, Hashable {
    let keyCode: UInt16
    let modifiers: UInt
}
```

The proposed storage is one versioned Codable dictionary in `UserDefaults`, such as `keyboardShortcuts.v1`. When reading, merge overrides with the built-in defaults:

- Use the default directly when an action has no override.
- Ignore unknown action identifiers for compatibility across versions.
- If one action's data is corrupt, fall back only that action to its default.
- Implement Restore Defaults by deleting the entire override dictionary, so users receive any new defaults added in future versions.

Return/numeric keypad Enter and `⌘⌫`/`⌘⌦` are multiple default gestures for the same actions. The internal default table can retain multiple gestures. Recording a custom shortcut replaces all defaults for that action with one gesture, and restoring the default brings the compatibility gestures back.

## Suggested code structure

### 1. Unified model and storage

Add `ShortcutAction.swift` and `ShortcutStore.swift`:

- Define actions, keys, defaults, and display names.
- Read, validate, and save overrides in `UserDefaults`.
- Provide `effectiveBindings`, conflict detection, and a full reset.
- Publish changes so menu titles, history hints, and the About window can refresh.

### 2. One event matcher

Add a separately testable `ShortcutMatcher`:

- Convert `NSEvent.keyCode` and normalized modifiers into a common gesture.
- Resolve actions by context: browsing, search, input-method composition, and Quick Look.
- While an input method has marked text, return events to system text input first except for explicit Command shortcuts.
- While Quick Look is open, Preview and Close should close only the preview, not the history window itself.
- Leave an event unconsumed if no action matches.

`HistoryWindowController.handleKeyboardEvent` should execute the resolved action instead of maintaining many hard-coded `keyCode` branches.

`KeyboardCollectionView.keyDown` currently duplicates some key handling. Remove its hard-coded dispatch or make it use the same matcher so there is one source of truth.

### 3. Rebindable global shortcut

Change `GlobalHotKey` so initialization or rebinding accepts a `ShortcutGesture` instead of hard-coding `kVK_ANSI_V + cmdKey + shiftKey`. Return explicit registration errors so settings can explain conflicts and roll back.

`AppDelegate` coordinates transactional rebinding and updates the “Open Clipboard History (…)” menu title immediately.

### 4. Settings window and recorder control

Add `ShortcutSettingsWindowController` and a small `ShortcutRecorderControl`. A third-party dependency is unnecessary for recording, keyboard focus, VoiceOver labels, and error messages; native AppKit controls can handle them.

Match physical `keyCode` values because Carbon global registration also requires virtual key codes. The display layer converts arrows, Tab, Return, Space, Esc, and similar keys into stable names. For letters and punctuation, save a readable label from `charactersIgnoringModifiers` when recording. After a keyboard-layout change, the original physical key still triggers the action and the UI retains the recorded label. Re-record the shortcut to use the new layout's meaning. Test layout switching separately on real devices.

### 5. Generate every hint from the configuration

These places must not keep hard-coded defaults:

- The history window's footer hints.
- The menu bar's “Open Clipboard History (…)” item.
- The shortcut cards in About cpsmart.
- The default shortcut descriptions in the README.

The footer has limited space; it should not try to show every custom combination in one line. Show only the common Preview, Search, Paste, and Close actions while browsing, with the rest available in settings and About.

## Issues addressed during implementation

- `HistoryWindowController` previously handled keys in both a local event monitor and `KeyboardCollectionView.keyDown`. Handling has been consolidated into one matcher.
- The About page previously said “just start typing to search,” although search required focusing the search field. It now shows the user's current search shortcut.
- Several checks previously tested only whether Command was present, causing `⌥⌘P` to trigger `⌘P`. Matching now uses exact normalized combinations.
- A global shortcut registration failure previously showed an alert only at launch. Settings now shows a non-destructive error and restores the old binding.

## Implementation sequence

### Phase 1: core model and automated tests

1. Add actions, gestures, defaults, storage, and display formatting.
2. Add a pure-logic matcher and contexts.
3. Test defaults, reading and writing, corrupt-data fallback, modifier normalization, conflict detection, swap, arrow presets, individual and full restore, and input-method precedence.
4. Keep all existing default behavior unchanged.

### Phase 2: existing events and global registration

1. Move the history window's hard-coded branches to the common matcher.
2. Remove duplicate shortcut dispatch in `KeyboardCollectionView`.
3. Make `GlobalHotKey` accept configuration and support transactional rebinding.
4. Add an injectable test point for global registration failure.
5. Run existing core tests and build checks.

### Phase 3: settings window and dynamic copy

1. Add the menu entry, settings window, and recorder control.
2. Implement row-level conflict messages, shortcut swap, arrow presets, cancel recording, immediate effect, and individual and full restore.
3. Update the history window, menu, About page, and README.
4. Check keyboard access and VoiceOver names.

### Phase 4: validation of a real installed package

Run the full [multi-display and input testing checklist](MULTI_DISPLAY_TESTING.md), plus these checks:

- Open Shortcut Settings from both primary and secondary displays; keep it within the visible area of the display containing the pointer.
- On both displays, test default and custom Previous Item, Next Item, Search, Preview, Paste, and Close bindings.
- Test the first, middle, and last cards in a scrolled collection view.
- With marked text from a Chinese input method, confirm custom shortcuts do not steal candidate selection, confirmation, or cancellation.
- Switch between at least two keyboard layouts and check the recorded gesture, displayed label, and actual trigger.
- Set a global combination already used by another app and confirm the old one still works.
- Restore defaults and restart the app to confirm no custom settings remain.
- After installing from the DMG into `/Applications`, test global activation and a real paste again.

Automated tests cannot replace this phase. Until the primary/secondary display and installed-package checks are complete, delivery notes must say “Not verified” (未验证).

## Acceptance criteria

- Users can change every cpsmart shortcut listed in the table.
- Changes take effect immediately and persist across launches.
- The same combination cannot bind two actions.
- Failure to register a global combination does not break the currently working one.
- Swap, arrow presets, and Restore Defaults are atomic, and hints update after restoration.
- Default behavior remains the same, including numeric keypad Enter, `⌘⌦`, input-method composition, and Quick Look.
- The required primary-display, secondary-display, mouse, trackpad, and keyboard regressions are complete.
- No new system permission is required, and users who never customize a shortcut are unaffected.

## Effort and risk

This is a medium-sized change. The settings window itself is relatively simple; the main risks are event context, global registration rollback, keyboard-layout labels, and removing duplicate dispatch. The suggested approach is four phases rather than combining the core refactor, UI, and release validation in one commit.

If the first version needs a narrower scope, start with the seven most-used categories: global activation, Previous Item, Next Item, Search, Paste, Preview, and Close. Pin, Delete, and the four filters could follow later. However, once a full action table exists, the marginal cost of the latter bindings is small, so the recommendation is to support them in the first version.
