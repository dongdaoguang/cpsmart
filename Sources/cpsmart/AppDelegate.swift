import AppKit
import Carbon
import CoreGraphics
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum PendingDeletionUndo {
        case history([RemovedClipboardEntry])
        case pinboard(UUID, [RemovedClipboardEntry])
    }

    private let isPackageSmokeTest = CommandLine.arguments.contains("--package-smoke-test")
    private let packageSmokeRoot = ProcessInfo.processInfo.environment[
        "CPSMART_PACKAGE_SMOKE_ROOT"
    ].map { URL(fileURLWithPath: $0, isDirectory: true) }
    private lazy var store: HistoryStore = {
        guard isPackageSmokeTest, let packageSmokeRoot else { return HistoryStore() }
        return HistoryStore(fileURL: packageSmokeRoot.appendingPathComponent("history.json"))
    }()
    private lazy var pinboardStore: PinboardStore = {
        guard isPackageSmokeTest, let packageSmokeRoot else { return PinboardStore() }
        return PinboardStore(fileURL: packageSmokeRoot.appendingPathComponent("pinboards.json"))
    }()
    private let monitor = ClipboardMonitor()
    private let pasteController = PasteController()
    private let shortcutStore = ShortcutStore()
    private let updateController = UpdateController()
    private lazy var historyWindow = HistoryWindowController(shortcutStore: shortcutStore)
    private lazy var aboutWindow = AboutWindowController(shortcutStore: shortcutStore)
    private lazy var shortcutSettingsWindow = ShortcutSettingsWindowController(
        shortcutStore: shortcutStore
    )
    private var hotKey: GlobalHotKey?
    private var shouldRegisterGlobalHotKey = true
    private var isRecordingShortcut = false
    private var statusItem: NSStatusItem!
    private var openHistoryMenuItem: NSMenuItem!
    private var pauseMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!
    private var appearanceMenuItem: NSMenuItem!
    private var languageMenuItem: NSMenuItem!
    private var checkForUpdatesMenuItem: NSMenuItem!
    private var automaticUpdatesMenuItem: NSMenuItem!
    private var pendingDeletionUndo: PendingDeletionUndo?
    private var pendingLanguageRefresh = false

    private var demoPinboardStore: PinboardStore?
    private var demoPinboardFileURL: URL?

    private var activePinboardStore: PinboardStore {
        if let demoPinboardStore { return demoPinboardStore }
        return pinboardStore
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureApplicationIcon()
        configureHistoryWindow()
        configureShortcutSettings()
        configureStatusItem()
        if !isPackageSmokeTest {
            configureClipboardMonitor()
        }
        updateController.onStateChange = { [weak self] in
            self?.refreshUpdateMenuItems()
        }

        // 演示模式（仅 DEBUG）：跳过快捷键注册，避免与正在运行的正式版冲突。
        let isDemoMode = CommandLine.arguments.contains("--demo-data")
        let shouldShowShortcutSettings = CommandLine.arguments.contains("--show-shortcut-settings")
        shouldRegisterGlobalHotKey = !isDemoMode && !isPackageSmokeTest

        if !isDemoMode && !isPackageSmokeTest {
            registerInitialGlobalHotKey()
            updateController.startAutomaticChecks()
        }

        if isPackageSmokeTest {
            startPackageSmokeTest()
            return
        }

        // Useful for automated UI smoke tests without requiring Accessibility permission.
        if CommandLine.arguments.contains("--show-history") {
            DispatchQueue.main.async { [weak self] in
                self?.showHistory()
            }
        }
        if CommandLine.arguments.contains("--show-about") {
            DispatchQueue.main.async { [weak self] in
                self?.aboutWindow.show()
            }
        }
        // Useful for packaged update-check smoke tests; the installed bundle provides the version
        // that is compared with the latest stable GitHub Release.
        if CommandLine.arguments.contains("--check-for-updates") {
            DispatchQueue.main.async { [weak self] in
                self?.updateController.checkForUpdates()
            }
        }
        if shouldShowShortcutSettings {
            DispatchQueue.main.async { [weak self] in
                self?.shortcutSettingsWindow.show()
            }
        }

        #if DEBUG
        // 开发用：`--demo-data` 用内置演示数据打开浮窗，不读写真实历史，便于截图审查 UI。
        // 可选 `--demo-query <词>` 预填搜索词；`--demo-light` 强制浅色外观（不写入设置）。
        if isDemoMode {
            monitor.isPaused = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !shouldShowShortcutSettings else { return }
                let demoPinboardFileURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "cpsmart-demo-pinboards-\(ProcessInfo.processInfo.processIdentifier).json"
                    )
                try? FileManager.default.removeItem(at: demoPinboardFileURL)
                self.demoPinboardFileURL = demoPinboardFileURL
                self.demoPinboardStore = PinboardStore(
                    fileURL: demoPinboardFileURL,
                    initialBoards: DemoData.makePinboards()
                )
                self.historyWindow.show(
                    entries: DemoData.makeEntries(),
                    pinboards: self.activePinboardStore.boards
                )
                if CommandLine.arguments.contains("--demo-light") {
                    self.historyWindow.applyAppearanceMode(.light)
                } else if CommandLine.arguments.contains("--demo-dark") {
                    self.historyWindow.applyAppearanceMode(.dark)
                }
                if let pinboardIndex = CommandLine.arguments.firstIndex(of: "--demo-pinboard"),
                   CommandLine.arguments.indices.contains(pinboardIndex + 1),
                   let index = Int(CommandLine.arguments[pinboardIndex + 1]) {
                    self.historyWindow.applyDemoPinboard(at: index)
                }
                if let queryIndex = CommandLine.arguments.firstIndex(of: "--demo-query"),
                   CommandLine.arguments.indices.contains(queryIndex + 1) {
                    self.historyWindow.applyDemoQuery(CommandLine.arguments[queryIndex + 1])
                }
                if let selectionIndex = CommandLine.arguments.firstIndex(of: "--demo-selection"),
                   CommandLine.arguments.indices.contains(selectionIndex + 2),
                   let anchorIndex = Int(CommandLine.arguments[selectionIndex + 1]),
                   let targetIndex = Int(CommandLine.arguments[selectionIndex + 2]) {
                    self.historyWindow.applyDemoSelection(
                        from: anchorIndex,
                        to: targetIndex
                    )
                }
                if let previewIndex = CommandLine.arguments.firstIndex(of: "--demo-preview-index"),
                   CommandLine.arguments.indices.contains(previewIndex + 1),
                   let index = Int(CommandLine.arguments[previewIndex + 1]) {
                    // 等集合视图完成首轮布局，确保选中卡片已经有可用于锚定的 window。
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.historyWindow.showDemoPreview(at: index)
                    }
                }
                if let sessionIndex = CommandLine.arguments.firstIndex(of: "--demo-preview-session"),
                   CommandLine.arguments.indices.contains(sessionIndex + 1),
                   let index = Int(CommandLine.arguments[sessionIndex + 1]) {
                    let logURL = URL(fileURLWithPath: "/tmp/cpsmart-preview-session.log")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.historyWindow.runDemoPreviewSession(textIndex: index, logURL: logURL)
                    }
                }
                if CommandLine.arguments.contains("--demo-new-pinboard-sheet") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.historyWindow.showDemoNewPinboardSheet()
                    }
                }
                if let snapshotIndex = CommandLine.arguments.firstIndex(of: "--demo-snapshot"),
                   CommandLine.arguments.indices.contains(snapshotIndex + 1) {
                    let snapshotURL = URL(
                        fileURLWithPath: CommandLine.arguments[snapshotIndex + 1]
                    )
                    var snapshotDelay = 0.6
                    if let delayIndex = CommandLine.arguments.firstIndex(of: "--demo-snapshot-delay"),
                       CommandLine.arguments.indices.contains(delayIndex + 1),
                       let configuredDelay = Double(CommandLine.arguments[delayIndex + 1]) {
                        snapshotDelay = max(0, configuredDelay)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + snapshotDelay) { [weak self] in
                        _ = self?.historyWindow.writeDemoSnapshot(to: snapshotURL)
                    }
                }
            }
        }
        #endif
    }

    private func startPackageSmokeTest() {
        guard let packageSmokeRoot,
        let reportArgumentIndex = CommandLine.arguments.firstIndex(
            of: "--package-smoke-report"
        ), CommandLine.arguments.indices.contains(reportArgumentIndex + 1),
        let screenArgumentIndex = CommandLine.arguments.firstIndex(
            of: "--expected-screen-index"
        ), CommandLine.arguments.indices.contains(screenArgumentIndex + 1),
        let expectedScreenIndex = Int(CommandLine.arguments[screenArgumentIndex + 1]) else {
            NSLog("cpsmart package smoke test requires report path and expected screen index")
            NSApp.terminate(nil)
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: packageSmokeRoot,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            NSLog("cpsmart could not create isolated package smoke directory: %@", error.localizedDescription)
            NSApp.terminate(nil)
            return
        }

        monitor.isPaused = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let screens = NSScreen.screens
            guard screens.indices.contains(expectedScreenIndex) else {
                NSLog("cpsmart package smoke screen index is unavailable")
                NSApp.terminate(nil)
                return
            }
            let targetScreen = screens[expectedScreenIndex]
            let demoPinboardFileURL = packageSmokeRoot.appendingPathComponent(
                "demo-pinboards.json"
            )
            try? FileManager.default.removeItem(at: demoPinboardFileURL)
            self.demoPinboardFileURL = demoPinboardFileURL
            self.demoPinboardStore = PinboardStore(
                fileURL: demoPinboardFileURL,
                initialBoards: DemoData.makePinboards()
            )
            self.store.clearAll()
            for entry in DemoData.makeEntries() {
                _ = self.store.add(
                    entry.payload,
                    sourceAppName: entry.sourceAppName,
                    sourceAppBundleID: entry.sourceAppBundleID,
                    at: entry.createdAt
                )
            }
            let reportURL = URL(
                fileURLWithPath: CommandLine.arguments[reportArgumentIndex + 1]
            )
            func showWhenPointerIsReady(remainingAttempts: Int) {
                let cocoaPoint = NSPoint(
                    x: targetScreen.frame.midX,
                    y: targetScreen.frame.midY
                )
                let quartzPoint = CGPoint(
                    x: cocoaPoint.x,
                    y: screens[0].frame.maxY - cocoaPoint.y
                )
                guard CGWarpMouseCursorPosition(quartzPoint) == .success else {
                    NSLog("cpsmart package smoke could not position the pointer")
                    NSApp.terminate(nil)
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self else { return }
                    guard targetScreen.frame.contains(NSEvent.mouseLocation) else {
                        if remainingAttempts > 1 {
                            showWhenPointerIsReady(remainingAttempts: remainingAttempts - 1)
                        } else {
                            NSLog("cpsmart package smoke pointer did not stay on the expected screen")
                            NSApp.terminate(nil)
                        }
                        return
                    }
                    // 不传测试专用屏幕参数：必须走正式的“鼠标所在屏幕”定位路径。
                    self.historyWindow.show(
                        entries: self.store.entries,
                        pinboards: self.activePinboardStore.boards
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                        guard let self else { return }
                        self.historyWindow.runPackageSmokeValidation(
                            expectedScreenIndex: expectedScreenIndex,
                            reportURL: reportURL
                        ) {
                            NSApp.terminate(nil)
                        }
                    }
                }
            }
            showWhenPointerIsReady(remainingAttempts: 3)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        if let demoPinboardFileURL {
            try? FileManager.default.removeItem(at: demoPinboardFileURL)
        }
    }

    private func configureApplicationIcon() {
        guard let iconURL = Bundle.main.url(forResource: "CPSmartAppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else { return }
        NSApp.applicationIconImage = icon
    }

    private func configureClipboardMonitor() {
        monitor.isPaused = UserDefaults.standard.bool(forKey: "capturePaused")
        monitor.onCapture = { [weak self] payload, sourceAppName, sourceAppBundleID in
            guard let self else { return }
            let capturedEntry = self.store.add(
                payload,
                sourceAppName: sourceAppName,
                sourceAppBundleID: sourceAppBundleID
            )
            self.historyWindow.refresh(
                entries: self.store.entries,
                selectingEntryID: capturedEntry.id
            )
        }
        monitor.start()
    }

    private func configureHistoryWindow() {
        historyWindow.onChoose = { [weak self] entry in
            guard let self else { return }
            guard !self.isPackageSmokeTest else { return }
            self.monitor.write(entry.payload)
        }
        historyWindow.onPaste = { [weak self] entry, targetApplication in
            guard let self else { return .targetUnavailable }
            let entryID = entry.id
            return self.pasteController.paste(to: targetApplication) { [weak self] in
                self?.store.promote(id: entryID)
            }
        }
        historyWindow.onDelete = { [weak self] entries in
            guard let self else { return 0 }
            let removed = self.store.remove(ids: Set(entries.map(\.id)))
            guard !removed.isEmpty else { return 0 }
            self.pendingDeletionUndo = .history(removed)
            self.historyWindow.refresh(entries: self.store.entries)
            return removed.count
        }
        historyWindow.onUndoDelete = { [weak self] in
            guard let self, let pendingDeletionUndo = self.pendingDeletionUndo else { return 0 }
            switch pendingDeletionUndo {
            case .history(let removed):
                self.store.restore(removed)
                self.historyWindow.refresh(
                    entries: self.store.entries,
                    selectingEntryID: removed.first?.entry.id
                )
                self.pendingDeletionUndo = nil
                return removed.count
            case .pinboard(let boardID, let removed):
                let store = self.activePinboardStore
                let restoredCount = store.restoreEntries(removed, to: boardID)
                guard restoredCount > 0 else { return 0 }
                self.historyWindow.refresh(pinboards: store.boards)
                self.pendingDeletionUndo = nil
                return restoredCount
            }
        }
        historyWindow.onTogglePin = { [weak self] entry in
            guard let self else { return }
            self.store.togglePin(id: entry.id)
            self.historyWindow.refresh(entries: self.store.entries)
        }
        historyWindow.onCreatePinboard = { [weak self] name, color in
            guard let self else { return nil }
            let store = self.activePinboardStore
            let board = store.create(name: name, color: color)
            self.historyWindow.refresh(pinboards: store.boards)
            return board
        }
        historyWindow.onRenamePinboard = { [weak self] id, name in
            guard let self else { return }
            let store = self.activePinboardStore
            store.rename(id: id, to: name)
            self.historyWindow.refresh(pinboards: store.boards)
        }
        historyWindow.onSetPinboardColor = { [weak self] id, color in
            guard let self else { return }
            let store = self.activePinboardStore
            store.setColor(id: id, color: color)
            self.historyWindow.refresh(pinboards: store.boards)
        }
        historyWindow.onDeletePinboard = { [weak self] id in
            guard let self else { return }
            self.pendingDeletionUndo = nil
            self.historyWindow.clearDeletionUndo()
            let store = self.activePinboardStore
            store.removeBoard(id: id)
            self.historyWindow.refresh(pinboards: store.boards)
        }
        historyWindow.onAddToPinboard = { [weak self] entries, boardID in
            guard let self else { return }
            let store = self.activePinboardStore
            store.add(entries, to: boardID)
            self.historyWindow.refresh(pinboards: store.boards)
        }
        historyWindow.onRemoveFromPinboard = { [weak self] entries, boardID in
            guard let self else { return 0 }
            let store = self.activePinboardStore
            let removed = store.removeEntries(ids: Set(entries.map(\.id)), from: boardID)
            guard !removed.isEmpty else { return 0 }
            self.pendingDeletionUndo = .pinboard(boardID, removed)
            self.historyWindow.refresh(pinboards: store.boards)
            return removed.count
        }
        historyWindow.onMovePinboardEntry = { [weak self] entryID, boardID, insertionIndex in
            guard let self else { return }
            let store = self.activePinboardStore
            store.moveEntry(
                id: entryID,
                toInsertionIndex: insertionIndex,
                in: boardID
            )
            self.historyWindow.refresh(pinboards: store.boards)
        }
    }

    private func configureShortcutSettings() {
        shortcutSettingsWindow.onAttemptChange = { [weak self] action, gesture in
            self?.attemptShortcutChange(action: action, gesture: gesture)
        }
        shortcutSettingsWindow.onAttemptReset = { [weak self] in
            self?.attemptShortcutReset()
        }
        shortcutSettingsWindow.onAttemptResetAction = { [weak self] action in
            self?.attemptShortcutReset(action: action)
        }
        shortcutSettingsWindow.onAttemptSwap = {
            [weak self] action, conflictingAction, gesture in
            self?.attemptShortcutSwap(
                action: action,
                with: conflictingAction,
                requestedGesture: gesture
            )
        }
        shortcutSettingsWindow.onRecordingStateChanged = { [weak self] recording in
            self?.setShortcutRecording(recording)
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "cpsmart"
            )
            button.toolTip = L10n.tr("cpsmart 剪贴板历史")
        }

        let menu = NSMenu()
        menu.delegate = self
        openHistoryMenuItem = NSMenuItem(
            title: openHistoryMenuTitle,
            action: #selector(showHistoryFromMenu),
            keyEquivalent: ""
        )
        menu.addItem(openHistoryMenuItem)
        menu.addItem(.separator())

        pauseMenuItem = NSMenuItem(
            title: L10n.tr("暂停记录"),
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        menu.addItem(pauseMenuItem)

        loginMenuItem = NSMenuItem(
            title: L10n.tr("登录时启动"),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        menu.addItem(loginMenuItem)

        menu.addItem(NSMenuItem(
            title: L10n.tr("快捷键设置…"),
            action: #selector(showShortcutSettings),
            keyEquivalent: ""
        ))

        // 外观：跟随系统 / 浅色 / 深色
        appearanceMenuItem = NSMenuItem(title: L10n.tr("外观"), action: nil, keyEquivalent: "")
        let appearanceSubmenu = NSMenu()
        for (index, mode) in AppearanceMode.allCases.enumerated() {
            let item = NSMenuItem(
                title: mode.displayName,
                action: #selector(selectAppearanceMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            appearanceSubmenu.addItem(item)
        }
        appearanceSubmenu.delegate = self
        appearanceMenuItem.submenu = appearanceSubmenu
        menu.addItem(appearanceMenuItem)

        languageMenuItem = NSMenuItem(title: L10n.tr("语言"), action: nil, keyEquivalent: "")
        let languageSubmenu = NSMenu()
        for (index, language) in AppLanguage.allCases.enumerated() {
            let item = NSMenuItem(
                title: language.displayName,
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            languageSubmenu.addItem(item)
        }
        languageSubmenu.delegate = self
        languageMenuItem.submenu = languageSubmenu
        menu.addItem(languageMenuItem)

        menu.addItem(NSMenuItem(
            title: L10n.tr("清空历史…"),
            action: #selector(clearHistory),
            keyEquivalent: ""
        ))
        // 按住 Option 出现：连置顶记录一起清空
        let clearAllItem = NSMenuItem(
            title: L10n.tr("清空全部历史（含置顶）…"),
            action: #selector(clearAllHistory),
            keyEquivalent: ""
        )
        clearAllItem.isAlternate = true
        clearAllItem.keyEquivalentModifierMask = [.option]
        menu.addItem(clearAllItem)
        menu.addItem(.separator())

        checkForUpdatesMenuItem = NSMenuItem(
            title: updateController.menuItemTitle,
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        menu.addItem(checkForUpdatesMenuItem)

        automaticUpdatesMenuItem = NSMenuItem(
            title: L10n.tr("自动检查更新"),
            action: #selector(toggleAutomaticUpdates),
            keyEquivalent: ""
        )
        menu.addItem(automaticUpdatesMenuItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: L10n.tr("关于 cpsmart"),
            action: #selector(showAbout),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: L10n.tr("退出 cpsmart"),
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === appearanceMenuItem.submenu {
            for item in menu.items {
                item.state = AppearanceMode.allCases[item.tag] == AppearanceMode.current
                    ? .on
                    : .off
            }
            return
        }
        if menu === languageMenuItem.submenu {
            for item in menu.items {
                item.state = AppLanguage.allCases[item.tag] == AppLanguage.selected()
                    ? .on
                    : .off
            }
            return
        }
        openHistoryMenuItem.title = openHistoryMenuTitle
        pauseMenuItem.state = monitor.isPaused ? .on : .off
        loginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        refreshUpdateMenuItems()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === statusItem.menu, pendingLanguageRefresh else { return }
        pendingLanguageRefresh = false
        DispatchQueue.main.async { [weak self] in
            self?.applyLanguageChange()
        }
    }

    private func refreshUpdateMenuItems() {
        guard checkForUpdatesMenuItem != nil, automaticUpdatesMenuItem != nil else { return }
        checkForUpdatesMenuItem.title = updateController.menuItemTitle
        checkForUpdatesMenuItem.isEnabled = updateController.activity == .idle
        automaticUpdatesMenuItem.state = updateController.automaticChecksEnabled ? .on : .off
    }

    @objc private func selectAppearanceMode(_ sender: NSMenuItem) {
        let mode = AppearanceMode.allCases[sender.tag]
        AppearanceMode.current = mode
        historyWindow.applyAppearanceMode()
        shortcutSettingsWindow.applyAppearanceMode()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard AppLanguage.allCases.indices.contains(sender.tag) else { return }
        let language = AppLanguage.allCases[sender.tag]
        guard language != AppLanguage.selected() else { return }
        AppLanguage.select(language)
        pendingLanguageRefresh = true
    }

    private func applyLanguageChange() {
        rebuildStatusMenu()
        historyWindow.refreshLocalization()
        aboutWindow.refreshLocalization()

        let oldSettings = shortcutSettingsWindow
        let wasVisible = oldSettings.window?.isVisible == true
        let previousFrame = oldSettings.window?.frame
        oldSettings.prepareForLanguageChange()
        shortcutSettingsWindow = ShortcutSettingsWindowController(shortcutStore: shortcutStore)
        configureShortcutSettings()
        if wasVisible {
            shortcutSettingsWindow.show()
            if let previousFrame {
                shortcutSettingsWindow.window?.setFrame(previousFrame, display: true)
            }
        }
    }

    private func showHistory() {
        historyWindow.show(entries: store.entries, pinboards: activePinboardStore.boards)
    }

    @objc private func showHistoryFromMenu() {
        showHistory()
    }

    @objc private func showShortcutSettings() {
        shortcutSettingsWindow.show()
    }

    private var openHistoryMenuTitle: String {
        L10n.format("打开剪贴板历史（{0}）", [shortcutStore.displayString(for: .toggleHistory)])
    }

    private func registerInitialGlobalHotKey() {
        let gesture = shortcutStore.primaryBinding(for: .toggleHistory)
        hotKey = makeGlobalHotKey(for: gesture)
        if hotKey == nil {
            showAlert(
                title: L10n.tr("快捷键注册失败"),
                message: L10n.format("{0} 可能已被系统或其他应用占用。你仍可从菜单栏打开 cpsmart，并在“快捷键设置”中更换。", [gesture.displayString])
            )
        }
    }

    private func makeGlobalHotKey(for gesture: ShortcutGesture) -> GlobalHotKey? {
        GlobalHotKey(gesture: gesture) { [weak self] in
            self?.showHistory()
        }
    }

    private func attemptShortcutChange(
        action: ShortcutActionID,
        gesture: ShortcutGesture
    ) -> String? {
        if let issue = shortcutStore.validate(gesture, for: action) {
            return issue.message
        }

        if action == .toggleHistory, shouldRegisterGlobalHotKey {
            if hotKey?.gesture != gesture {
                guard let candidate = makeGlobalHotKey(for: gesture) else {
                    return L10n.format("无法使用 {0}：该快捷键可能已被系统或其他应用占用。原快捷键仍然有效。", [gesture.displayString])
                }
                guard shortcutStore.set(gesture, for: action) == nil else {
                    return L10n.tr("无法保存该快捷键。")
                }
                hotKey = candidate
                openHistoryMenuItem?.title = openHistoryMenuTitle
                return nil
            }
        }

        if let issue = shortcutStore.set(gesture, for: action) {
            return issue.message
        }
        openHistoryMenuItem?.title = openHistoryMenuTitle
        return nil
    }

    private func attemptShortcutReset() -> String? {
        let defaultGlobal = ShortcutDefaults.bindings[.toggleHistory]!.first!
        if shouldRegisterGlobalHotKey, hotKey?.gesture != defaultGlobal {
            guard let candidate = makeGlobalHotKey(for: defaultGlobal) else {
                return L10n.format("无法恢复默认：{0} 可能已被系统或其他应用占用。当前设置保持不变。", [defaultGlobal.displayString])
            }
            shortcutStore.resetToDefaults()
            hotKey = candidate
        } else {
            shortcutStore.resetToDefaults()
        }
        openHistoryMenuItem?.title = openHistoryMenuTitle
        return nil
    }

    private func attemptShortcutReset(action: ShortcutActionID) -> String? {
        if let issue = shortcutStore.validateReset(for: action) {
            return L10n.format("无法恢复默认：{0}", [issue.message])
        }

        if action == .toggleHistory, shouldRegisterGlobalHotKey {
            let defaultGesture = shortcutStore.defaultBindings(for: action).first!
            guard let candidate = makeGlobalHotKey(for: defaultGesture) else {
                return L10n.format("无法恢复默认：{0} 可能已被系统或其他应用占用。当前设置保持不变。", [defaultGesture.displayString])
            }
            guard shortcutStore.resetToDefault(action) == nil else {
                return L10n.tr("无法恢复该快捷键。")
            }
            hotKey = candidate
        } else if let issue = shortcutStore.resetToDefault(action) {
            return issue.message
        }

        openHistoryMenuItem?.title = openHistoryMenuTitle
        return nil
    }

    private func attemptShortcutSwap(
        action: ShortcutActionID,
        with conflictingAction: ShortcutActionID,
        requestedGesture: ShortcutGesture
    ) -> String? {
        if let issue = shortcutStore.validateSwap(
            action,
            with: conflictingAction,
            requestedGesture: requestedGesture
        ) {
            return L10n.format("无法交换：{0}", [issue.message])
        }

        let replacementGesture = shortcutStore.primaryBinding(for: action)
        let newGlobalGesture: ShortcutGesture? = if action == .toggleHistory {
            requestedGesture
        } else if conflictingAction == .toggleHistory {
            replacementGesture
        } else {
            nil
        }

        var candidateHotKey: GlobalHotKey?
        if shouldRegisterGlobalHotKey, let newGlobalGesture {
            guard let candidate = makeGlobalHotKey(for: newGlobalGesture) else {
                return L10n.format("无法交换：{0} 不能注册为全局快捷键。当前设置保持不变。", [newGlobalGesture.displayString])
            }
            candidateHotKey = candidate
        }

        if let issue = shortcutStore.swap(
            action,
            with: conflictingAction,
            requestedGesture: requestedGesture
        ) {
            return L10n.format("无法交换：{0}", [issue.message])
        }
        if let candidateHotKey { hotKey = candidateHotKey }
        openHistoryMenuItem?.title = openHistoryMenuTitle
        return nil
    }

    private func setShortcutRecording(_ recording: Bool) -> String? {
        guard shouldRegisterGlobalHotKey else { return nil }
        if recording {
            guard !isRecordingShortcut else { return nil }
            isRecordingShortcut = true
            // Carbon 会先拦截当前全局组合；录制期间必须临时注销，录制控件才能收到它。
            hotKey = nil
            return nil
        }

        guard isRecordingShortcut else { return nil }
        isRecordingShortcut = false
        guard hotKey == nil else { return nil }
        let gesture = shortcutStore.primaryBinding(for: .toggleHistory)
        guard let restored = makeGlobalHotKey(for: gesture) else {
            return L10n.format("无法恢复 {0}：该快捷键可能刚被系统或其他应用占用。请重新录制一个全局快捷键。", [gesture.displayString])
        }
        hotKey = restored
        return nil
    }

    @objc private func togglePause() {
        monitor.isPaused.toggle()
        UserDefaults.standard.set(monitor.isPaused, forKey: "capturePaused")
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showAlert(
                title: L10n.tr("无法更改登录启动设置"),
                message: L10n.format("请先把 cpsmart 拖入“应用程序”文件夹，然后重试。\n\n{0}", [error.localizedDescription])
            )
        }
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("清空剪贴板历史？")
        alert.informativeText = L10n.tr("置顶的记录会保留。此操作无法撤销。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("清空"))
        alert.addButton(withTitle: L10n.tr("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        pendingDeletionUndo = nil
        historyWindow.clearDeletionUndo()
        store.clear()
        historyWindow.refresh(entries: store.entries)
    }

    @objc private func clearAllHistory() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("清空全部剪贴板历史（含置顶）？")
        alert.informativeText = L10n.tr("置顶的记录也会一并删除。此操作无法撤销。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("全部清空"))
        alert.addButton(withTitle: L10n.tr("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        pendingDeletionUndo = nil
        historyWindow.clearDeletionUndo()
        store.clearAll()
        historyWindow.refresh(entries: store.entries)
    }

    @objc private func showAbout() {
        aboutWindow.show()
    }

    @objc private func checkForUpdates() {
        updateController.checkForUpdates()
    }

    @objc private func toggleAutomaticUpdates() {
        updateController.setAutomaticChecksEnabled(!updateController.automaticChecksEnabled)
        refreshUpdateMenuItems()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("好"))
        alert.runModal()
    }
}
