import AppKit
import Carbon
import Quartz

private extension NSRect {
    func approximatelyEquals(_ other: NSRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

// MARK: - 外观模式与调色板

/// 外观模式：跟随系统 / 浅色 / 深色。存 UserDefaults，从菜单栏「外观」切换。
enum AppearanceMode: String, CaseIterable {
    case system
    case light
    case dark

    var displayName: String {
        switch self {
        case .system: return L10n.tr("跟随系统")
        case .light: return L10n.tr("浅色")
        case .dark: return L10n.tr("深色")
        }
    }

    static let defaultsKey = "appearanceMode"

    static var current: AppearanceMode {
        get {
            AppearanceMode(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "")
                ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }

    var isDark: Bool {
        switch self {
        case .dark: return true
        case .light: return false
        case .system:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }
}

// MARK: - 浮窗控制器

final class HistoryWindowController: NSWindowController,
    NSCollectionViewDataSource,
    NSCollectionViewDelegate,
    NSSearchFieldDelegate,
    NSWindowDelegate,
    QLPreviewPanelDataSource,
    QLPreviewPanelDelegate,
    NSDraggingSource
{
    var onChoose: ((ClipboardEntry) -> Void)?
    var onPaste: ((ClipboardEntry, NSRunningApplication?) -> PasteStartResult)?
    var onDelete: (([ClipboardEntry]) -> Int)?
    var onUndoDelete: (() -> Int)?
    var onTogglePin: ((ClipboardEntry) -> Void)?
    var onCreatePinboard: ((String, PinboardColor) -> Pinboard?)?
    var onRenamePinboard: ((UUID, String) -> Void)?
    var onSetPinboardColor: ((UUID, PinboardColor) -> Void)?
    var onDeletePinboard: ((UUID) -> Void)?
    var onAddToPinboard: (([ClipboardEntry], UUID) -> Void)?
    var onRemoveFromPinboard: (([ClipboardEntry], UUID) -> Int)?
    var onMovePinboardEntry: ((UUID, UUID, Int) -> Void)?

    private static let itemIdentifier = NSUserInterfaceItemIdentifier("HistoryCollectionItem")
    private let collectionView = KeyboardCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()
    private let thumbnailProvider = ThumbnailProvider()
    private let adaptivePreviewController = AdaptivePreviewController()
    private let pinboardInteractionCoordinator = PinboardInteractionCoordinator()
    private let shortcutStore: ShortcutStore
    private let shortcutMatcher: ShortcutMatcher
    private let searchField = NSSearchField()
    private var filterControl: NSSegmentedControl!
    private let favoriteButton = NSButton()
    private let boardStackView = NSStackView()
    private let countLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "")
    private var effectView: NSVisualEffectView!
    private var tintView: NSView!

    private var palette = AppVisualTheme.palette(isDark: true)
    private var historyEntries: [ClipboardEntry] = []
    private var pinboards: [Pinboard] = []
    private var pinboardSourceState = PinboardSourceState()
    private var selectedPinboardID: UUID? { pinboardSourceState.selectedPinboardID }
    private var allEntries: [ClipboardEntry] = []
    private var visibleEntries: [ClipboardEntry] = []
    private var filterState = HistoryFilterState()
    private var query: String { filterState.query }
    private var selectionState = HistorySelectionState<UUID>()
    private var visibleEntryIDs: [UUID] { visibleEntries.map(\.id) }
    private var selectedIndex: Int { selectionState.activeIndex(in: visibleEntryIDs) ?? 0 }
    private var selectedEntryIDs: Set<UUID> { selectionState.selectedIDs }
    private var hasPendingDeletionUndo = false
    private var previousApplication: NSRunningApplication?
    private var lastExternalApplication: NSRunningApplication?

    /// 粘贴与焦点归还的目标：用户最近一次操作的外部应用。
    /// 浮窗常驻期间用户可能点击了别的窗口，目标应跟随真实焦点，
    /// 而不是锁定在浮窗打开的那一刻。
    private var pasteTargetApplication: NSRunningApplication? {
        lastExternalApplication ?? previousApplication
    }
    private var suppressSelectionCallback = false
    private var keyboardMonitor: Any?
    private var mouseMonitor: Any?
    private let quickLookPreviewStore = QuickLookPreviewStore()
    private var previewSessionState = HistoryPreviewSessionState()
    private var quickLookPreviewURL: URL? { quickLookPreviewStore.previewURL }
    private var isPreviewSessionActive: Bool { previewSessionState.isActive }
    private var isPositioningQuickLookPanel = false
    private var activationObserver: NSObjectProtocol?
    private var systemThemeObserver: NSObjectProtocol?
    private var shortcutObserver: NSObjectProtocol?
    private var isDismissing = false
    private var dismissalGeneration = 0

    init(shortcutStore: ShortcutStore) {
        self.shortcutStore = shortcutStore
        shortcutMatcher = ShortcutMatcher(store: shortcutStore)
        let panel = FloatingHistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: HistoryWindowTheme.panelHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.tr("cpsmart 剪贴板历史")
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        super.init(window: panel)
        panel.delegate = self
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication)
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            self?.rememberExternalApplication(application)
        }
        // 系统深浅色切换时，「跟随系统」模式要跟着变
        systemThemeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyAppearanceMode()
        }
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.didChangeNotification,
            object: shortcutStore,
            queue: .main
        ) { [weak self] _ in
            self?.updateHintLabel()
        }
        configurePinboardInteractionCoordinator()
        buildInterface()
        applyAppearanceMode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        removeKeyboardMonitor()
        adaptivePreviewController.close()
        quickLookPreviewStore.clear()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let systemThemeObserver {
            DistributedNotificationCenter.default().removeObserver(systemThemeObserver)
        }
        if let shortcutObserver {
            NotificationCenter.default.removeObserver(shortcutObserver)
        }
    }

    /// 应用外观模式；传 nil 时读取当前设置。菜单切换或系统主题变化时调用。
    func applyAppearanceMode(_ mode: AppearanceMode? = nil) {
        let isDark = (mode ?? AppearanceMode.current).isDark
        palette = AppVisualTheme.palette(isDark: isDark)

        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        window?.appearance = appearance
        effectView?.appearance = appearance
        tintView?.layer?.backgroundColor = palette.panelTint.cgColor
        effectView?.layer?.borderColor = palette.panelBorder.cgColor

        countLabel.textColor = palette.textTertiary
        statusLabel.textColor = palette.textSecondary
        hintLabel.textColor = palette.textTertiary
        emptyLabel.textColor = palette.textTertiary

        // 卡片颜色由各 item 在 configure 时按 palette 重写
        rebuildPinboardTabs()
        reloadCollection(notify: false)
    }

    func refreshLocalization() {
        window?.title = L10n.tr("cpsmart 剪贴板历史")
        if let selectedPinboardID,
           let board = pinboards.first(where: { $0.id == selectedPinboardID }) {
            searchField.placeholderString = L10n.format("在“{0}”中搜索", [board.name])
        } else {
            searchField.placeholderString = L10n.tr("搜索剪贴板历史")
        }
        for (index, title) in ["全部", "文本", "图片", "文件"].enumerated() {
            filterControl.setLabel(L10n.tr(title), forSegment: index)
        }
        favoriteButton.image = NSImage(
            systemSymbolName: "star",
            accessibilityDescription: L10n.tr("收藏到收藏板")
        )
        favoriteButton.toolTip = L10n.tr("收藏到收藏板")
        applyAppearanceMode()
    }

    func show(
        entries: [ClipboardEntry],
        pinboards: [Pinboard] = []
    ) {
        if window?.isVisible == true {
            if isDismissing {
                // 退场动画进行中：作废旧动画的完成回调并立即复位，
                // 避免全局快捷键在 0.12s 动画窗口内被吞掉。
                dismissalGeneration += 1
                window?.orderOut(nil)
                window?.alphaValue = 1
                isDismissing = false
            } else {
                dismiss(restorePreviousApplication: true)
                return
            }
        }

        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if isExternalApplication(frontmostApplication) {
            previousApplication = frontmostApplication
            rememberExternalApplication(frontmostApplication)
        } else {
            previousApplication = lastExternalApplication
        }

        historyEntries = entries
        self.pinboards = pinboards
        pinboardSourceState.selectHistory()
        allEntries = entries
        filterState.reset()
        searchField.stringValue = ""
        searchField.placeholderString = L10n.tr("搜索剪贴板历史")
        filterControl.selectedSegment = 0
        selectionState.reset()
        rebuildPinboardTabs()

        guard let window else { return }
        let finalFrame = targetFrame()
        // 先摆到最终位置完成布局与数据加载，再偏移一点做入场动画。
        window.setFrame(finalFrame, display: false)
        updateContentInsets()
        refilter(fallbackIndex: 0)

        installKeyboardMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window.alphaValue = 0
        window.setFrame(finalFrame.offsetBy(dx: 0, dy: -10), display: false)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = HistoryWindowTheme.entranceDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(finalFrame, display: true)
            window.animator().alphaValue = 1
        }
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            window.makeFirstResponder(self.collectionView)
            self.updateHintLabel()
        }
    }

    func refresh(entries: [ClipboardEntry], selectingEntryID: UUID? = nil) {
        // 普通刷新保留当前选择；剪贴板捕获刷新则聚焦刚加入的记录，
        // 避免旧选择随着新记录插入不断右移并把最新内容留在屏幕左侧之外。
        let selectedID = selectingEntryID ?? (
            visibleEntries.indices.contains(selectedIndex)
                ? visibleEntries[selectedIndex].id
                : nil
        )
        historyEntries = entries
        guard selectedPinboardID == nil else {
            rebuildPinboardTabs()
            return
        }
        allEntries = entries
        refilter(
            selectingID: selectedID,
            fallbackIndex: selectingEntryID == nil ? selectedIndex : 0
        )
    }

    func refresh(pinboards: [Pinboard]) {
        let selectedID = visibleEntries.indices.contains(selectedIndex)
            ? visibleEntries[selectedIndex].id
            : nil
        self.pinboards = pinboards
        let wasShowingPinboard = !pinboardSourceState.isHistory
        if let board = pinboardSourceState.reconcile(with: pinboards) {
            allEntries = board.entries
            searchField.placeholderString = L10n.format("在“{0}”中搜索", [board.name])
            refilter(selectingID: selectedID, fallbackIndex: selectedIndex)
        } else if wasShowingPinboard {
            allEntries = historyEntries
            searchField.placeholderString = L10n.tr("搜索剪贴板历史")
            refilter(fallbackIndex: 0)
        }
        rebuildPinboardTabs()
        syncPreviewWithSelection()
    }

    // MARK: 界面搭建

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        effectView = NSVisualEffectView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = HistoryWindowTheme.panelRadius
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 0.5
        contentView.addSubview(effectView)

        // 色调罩层：盖在毛玻璃上保证深浅两种模式在任何壁纸下基调一致，
        // 具体颜色由 applyAppearanceMode() 按 palette 设置
        tintView = NSView()
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.wantsLayer = true
        effectView.addSubview(tintView)
        NSLayoutConstraint.activate([
            tintView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: effectView.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        // 头部：贴边布局（不要把宽度约束写死成某个值——完全确定的约束链会让
        // AppKit 算出固定的 fittingSize 并在 layout 时把窗口"回正"到那个尺寸，
        // 全宽浮窗必须让约束欠定，由窗口框架驱动布局）
        let headerContainer = NSView()
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(headerContainer)

        countLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = L10n.tr("搜索剪贴板历史")
        searchField.font = .systemFont(ofSize: 12)
        searchField.delegate = self

        filterControl = NSSegmentedControl(
            labels: [L10n.tr("全部"), L10n.tr("文本"), L10n.tr("图片"), L10n.tr("文件")],
            trackingMode: .selectOne,
            target: self,
            action: #selector(filterChanged(_:))
        )
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        filterControl.controlSize = .small
        filterControl.selectedSegment = 0

        favoriteButton.translatesAutoresizingMaskIntoConstraints = false
        favoriteButton.image = NSImage(
            systemSymbolName: "star",
            accessibilityDescription: L10n.tr("收藏到收藏板")
        )
        favoriteButton.imagePosition = .imageOnly
        favoriteButton.bezelStyle = .roundRect
        favoriteButton.controlSize = .small
        favoriteButton.target = self
        favoriteButton.action = #selector(showFavoriteMenu(_:))
        favoriteButton.toolTip = L10n.tr("收藏到收藏板")

        statusLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        statusLabel.alignment = .right
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        headerContainer.addSubview(countLabel)
        headerContainer.addSubview(searchField)
        headerContainer.addSubview(filterControl)
        headerContainer.addSubview(favoriteButton)
        headerContainer.addSubview(statusLabel)

        // 收藏板标签与头部合并为一行；历史记录固定在最左，收藏板过多时横向滚动。
        let boardScrollView = NSScrollView()
        boardScrollView.translatesAutoresizingMaskIntoConstraints = false
        boardScrollView.drawsBackground = false
        boardScrollView.hasHorizontalScroller = false
        boardScrollView.hasVerticalScroller = false
        boardScrollView.horizontalScrollElasticity = .automatic
        let boardMinimumWidthConstraint = boardScrollView.widthAnchor.constraint(
            greaterThanOrEqualToConstant: 150
        )
        boardMinimumWidthConstraint.priority = .defaultHigh
        boardMinimumWidthConstraint.isActive = true

        let boardDocumentView = NSView()
        boardDocumentView.translatesAutoresizingMaskIntoConstraints = false
        boardScrollView.documentView = boardDocumentView
        headerContainer.addSubview(boardScrollView)

        boardStackView.translatesAutoresizingMaskIntoConstraints = false
        boardStackView.orientation = .horizontal
        boardStackView.alignment = .centerY
        boardStackView.spacing = 7
        boardDocumentView.addSubview(boardStackView)
        NSLayoutConstraint.activate([
            boardDocumentView.leadingAnchor.constraint(equalTo: boardScrollView.contentView.leadingAnchor),
            boardDocumentView.topAnchor.constraint(equalTo: boardScrollView.contentView.topAnchor),
            boardDocumentView.bottomAnchor.constraint(equalTo: boardScrollView.contentView.bottomAnchor),
            boardDocumentView.widthAnchor.constraint(
                greaterThanOrEqualTo: boardScrollView.contentView.widthAnchor
            ),
            boardStackView.leadingAnchor.constraint(equalTo: boardDocumentView.leadingAnchor),
            boardStackView.trailingAnchor.constraint(
                lessThanOrEqualTo: boardDocumentView.trailingAnchor
            ),
            boardStackView.centerYAnchor.constraint(equalTo: boardDocumentView.centerYAnchor)
        ])

        // 卡片流
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        // 不显示滚动条：自定义 InvisibleScroller 会把 scrollerStyle 重置为 legacy 并占用布局高度
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.drawsBackground = false

        flowLayout.scrollDirection = .horizontal
        flowLayout.itemSize = HistoryWindowTheme.cardSize
        flowLayout.minimumInteritemSpacing = 10
        flowLayout.minimumLineSpacing = 10
        flowLayout.sectionInset = NSEdgeInsets(top: 4, left: 24, bottom: 4, right: 24)

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            HistoryCollectionItem.self,
            forItemWithIdentifier: Self.itemIdentifier
        )
        collectionView.registerForDraggedTypes([PinboardDragDescriptor.pasteboardType])
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collectionView.onBackgroundClick = { [weak self] in
            self?.focusCollectionView()
        }
        scrollView.documentView = collectionView

        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 12.5)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.alignment = .center
        hintLabel.font = .systemFont(ofSize: 10, weight: .medium)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        effectView.addSubview(scrollView)
        effectView.addSubview(emptyLabel)
        effectView.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: contentView.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            headerContainer.leadingAnchor.constraint(
                equalTo: effectView.leadingAnchor, constant: 24
            ),
            headerContainer.trailingAnchor.constraint(
                equalTo: effectView.trailingAnchor, constant: -24
            ),
            headerContainer.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 14),
            headerContainer.heightAnchor.constraint(equalToConstant: 28),

            countLabel.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            countLabel.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),

            searchField.leadingAnchor.constraint(equalTo: countLabel.trailingAnchor, constant: 12),
            searchField.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 240),

            boardScrollView.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 14),
            boardScrollView.trailingAnchor.constraint(equalTo: filterControl.leadingAnchor, constant: -14),
            boardScrollView.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            boardScrollView.heightAnchor.constraint(equalToConstant: 28),

            statusLabel.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 240),

            favoriteButton.trailingAnchor.constraint(
                equalTo: statusLabel.leadingAnchor, constant: -14
            ),
            favoriteButton.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),
            favoriteButton.widthAnchor.constraint(equalToConstant: 34),

            filterControl.trailingAnchor.constraint(equalTo: favoriteButton.leadingAnchor, constant: -8),
            filterControl.centerYAnchor.constraint(equalTo: headerContainer.centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: 12),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            hintLabel.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            hintLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 6),
            hintLabel.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -10)
        ])

        updateHintLabel()
        rebuildPinboardTabs()
    }

    // MARK: 收藏板

    private func configurePinboardInteractionCoordinator() {
        pinboardInteractionCoordinator.onCreate = { [weak self] name, color in
            self?.onCreatePinboard?(name, color)
        }
        pinboardInteractionCoordinator.onRename = { [weak self] id, name in
            self?.onRenamePinboard?(id, name)
        }
        pinboardInteractionCoordinator.onSetColor = { [weak self] id, color in
            self?.onSetPinboardColor?(id, color)
        }
        pinboardInteractionCoordinator.onDelete = { [weak self] id in
            self?.onDeletePinboard?(id)
        }
        pinboardInteractionCoordinator.onAddEntries = { [weak self] entries, id in
            self?.onAddToPinboard?(entries, id)
        }
        pinboardInteractionCoordinator.onSwitchSource = { [weak self] id in
            self?.switchSource(to: id)
        }
        pinboardInteractionCoordinator.onStatus = { [weak self] message, isWarning in
            guard let self else { return }
            self.statusLabel.stringValue = message
            self.statusLabel.textColor = isWarning ? .systemOrange : self.palette.accent
            if isWarning { NSSound.beep() }
        }
    }

    private func rebuildPinboardTabs() {
        guard isWindowLoaded else { return }
        pinboardInteractionCoordinator.update(
            pinboards: pinboards,
            palette: palette,
            presentationWindow: window
        )
        for view in boardStackView.arrangedSubviews {
            boardStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let historyButton = makeBoardButton(
            title: L10n.tr("最近"),
            color: nil,
            isSelected: selectedPinboardID == nil,
            action: #selector(selectHistoryTab(_:))
        )
        historyButton.toolTip = L10n.tr("最近复制的剪贴板历史 · ⌘⌥1 · ⌃Tab 循环切换")
        boardStackView.addArrangedSubview(historyButton)

        for (index, board) in pinboards.enumerated() {
            let button = makeBoardButton(
                title: board.name,
                color: board.color,
                isSelected: selectedPinboardID == board.id,
                action: #selector(selectPinboardTab(_:))
            )
            button.identifier = NSUserInterfaceItemIdentifier(board.id.uuidString)
            let shortcutHint = index < 8 ? " · ⌘⌥\(index + 2)" : ""
            button.toolTip = L10n.format("打开“{0}”{1}；右键可重命名、改色或删除", [board.name, shortcutHint])
            button.menu = pinboardInteractionCoordinator.makeContextMenu(for: board)
            button.dropHighlightColor = palette.pinboardColor(board.color)
            button.onAcceptHistoryEntry = { [weak self] entryID in
                DispatchQueue.main.async { [weak self] in
                    self?.addDraggedHistoryEntry(entryID, to: board.id)
                }
            }
            boardStackView.addArrangedSubview(button)
        }

        let addButton = makeBoardButton(
            title: "",
            color: nil,
            isSelected: false,
            action: #selector(createPinboardFromTab(_:))
        )
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: L10n.tr("新建收藏板"))
        addButton.imagePosition = .imageOnly
        addButton.toolTip = L10n.tr("新建收藏板")
        boardStackView.addArrangedSubview(addButton)
    }

    private func makeBoardButton(
        title: String,
        color: PinboardColor?,
        isSelected: Bool,
        action: Selector
    ) -> PinboardTabButton {
        let button = PinboardTabButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        if let color {
            let resolvedColor = palette.pinboardColor(color)
            button.image = Self.pinboardColorDot(resolvedColor)
            button.imagePosition = .imageLeading
            button.applyStyle(palette: palette, selected: isSelected, tint: resolvedColor)
        } else {
            button.applyStyle(palette: palette, selected: isSelected, tint: nil)
        }
        return button
    }

    private static func pinboardColorDot(_ color: NSColor, diameter: CGFloat = 9) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: 0.5, y: 0.5,
            width: diameter - 1, height: diameter - 1
        )).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func addDraggedHistoryEntry(_ entryID: UUID, to boardID: UUID) {
        guard let entry = historyEntries.first(where: { $0.id == entryID }),
              let board = pinboards.first(where: { $0.id == boardID }) else { return }
        let alreadyContainsEntry = board.entries.contains { $0.payload == entry.payload }
        onAddToPinboard?([entry], boardID)
        statusLabel.stringValue = alreadyContainsEntry
            ? L10n.format("这项内容已在“{0}”中", [board.name])
            : L10n.format("已收藏到“{0}”", [board.name])
        statusLabel.textColor = palette.accent
    }

    @objc private func selectHistoryTab(_ sender: NSButton) {
        switchSource(to: nil)
    }

    @objc private func selectPinboardTab(_ sender: NSButton) {
        guard let id = PinboardInteractionSupport.boardID(
            from: sender.identifier?.rawValue
        ) else { return }
        switchSource(to: id)
    }

    private func switchSource(to pinboardID: UUID?) {
        // 切换数据源后原预览指向的条目可能已不在列表中，先结束预览会话再重建状态。
        endPreviewSession(restoreBrowsingFocus: false)
        if let pinboardID,
           let board = pinboardSourceState.selectPinboard(pinboardID, from: pinboards) {
            allEntries = board.entries
            searchField.placeholderString = L10n.format("在“{0}”中搜索", [board.name])
        } else {
            pinboardSourceState.selectHistory()
            allEntries = historyEntries
            searchField.placeholderString = L10n.tr("搜索剪贴板历史")
        }
        filterState.reset()
        searchField.stringValue = ""
        filterControl.selectedSegment = 0
        selectionState.reset()
        rebuildPinboardTabs()
        refilter(fallbackIndex: 0)
        focusCollectionView()
    }

    private func handlePinboardShortcut(_ event: NSEvent) -> Bool {
        guard let command = PinboardShortcutRouting.command(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags
        ) else { return false }
        guard !event.isARepeat else { return true }

        switch command {
        case .selectSource(let index):
            if index == 0 {
                switchSource(to: nil)
            } else {
                let pinboardIndex = index - 1
                guard pinboards.indices.contains(pinboardIndex) else {
                    statusLabel.stringValue = L10n.format("还没有第 {0} 个收藏板", [index])
                    statusLabel.textColor = .systemOrange
                    NSSound.beep()
                    return true
                }
                switchSource(to: pinboards[pinboardIndex].id)
            }
        case .cycle(let offset):
            let currentIndex = selectedPinboardID.flatMap { selectedID in
                pinboards.firstIndex(where: { $0.id == selectedID }).map { $0 + 1 }
            } ?? 0
            guard let targetIndex = PinboardShortcutRouting.cycledSourceIndex(
                currentIndex: currentIndex,
                sourceCount: pinboards.count + 1,
                offset: offset
            ) else { return true }
            switchSource(to: targetIndex == 0 ? nil : pinboards[targetIndex - 1].id)
        }
        return true
    }

    @objc private func createPinboardFromTab(_ sender: NSButton) {
        guard let window else { return }
        pinboardInteractionCoordinator.presentCreate(on: window, adding: [])
    }

    @objc private func showFavoriteMenu(_ sender: NSButton) {
        guard pinboardSourceState.isHistory else {
            NSSound.beep()
            return
        }
        guard let window else { return }
        collectionView.layoutSubtreeIfNeeded()
        pinboardInteractionCoordinator.presentFavoriteMenu(
            from: sender,
            anchorView: collectionView.item(at: selectedIndex)?.view,
            entries: selectedEntries,
            on: window
        )
    }
    // MARK: 布局与定位

    private func targetFrame() -> NSRect {
        let screens = NSScreen.screens
        let mouseScreenIndex = DisplayGeometry.screenIndex(
            containing: NSEvent.mouseLocation,
            frames: screens.map(\.frame)
        )
        let screen = mouseScreenIndex.map { screens[$0] }
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            return NSRect(x: 0, y: 0, width: 960, height: HistoryWindowTheme.panelHeight)
        }
        return DisplayGeometry.historyFrame(
            visibleFrame: visibleFrame,
            height: HistoryWindowTheme.panelHeight
        )
    }

    private func updateContentInsets() {
        // 卡片流与头部一样通栏贴边，保持左缘对齐
        flowLayout.sectionInset = NSEdgeInsets(top: 4, left: 24, bottom: 4, right: 24)
        flowLayout.invalidateLayout()
    }

    func windowDidResize(_ notification: Notification) {
        if let panel = notification.object as? QLPreviewPanel {
            positionQuickLookPanel(panel)
            return
        }
        updateContentInsets()
    }

    func windowDidMove(_ notification: Notification) {
        guard let panel = notification.object as? QLPreviewPanel else { return }
        positionQuickLookPanel(panel)
    }

    // MARK: 过滤

    private func refilter(selectingID id: UUID? = nil, fallbackIndex: Int) {
        visibleEntries = filterState.apply(to: allEntries)
        selectionState.reconcile(
            with: visibleEntryIDs,
            preferredID: id,
            fallbackIndex: fallbackIndex
        )
        reloadCollection(notify: false)
    }

    private func reloadCollection(notify: Bool) {
        suppressSelectionCallback = true
        collectionView.reloadData()
        updateHeaderState()

        if let index = selectionState.activeIndex(in: visibleEntryIDs) {
            let indexPath = IndexPath(item: index, section: 0)
            collectionView.layoutSubtreeIfNeeded()
            collectionView.selectionIndexPaths = Set(
                selectionState.selectedIndexes(in: visibleEntryIDs).map {
                    IndexPath(item: $0, section: 0)
                }
            )
            collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredHorizontally)
        } else {
            collectionView.selectionIndexPaths = []
        }
        suppressSelectionCallback = false
        if notify, let index = selectionState.activeIndex(in: visibleEntryIDs) {
            chooseEntry(at: index)
        } else {
            statusLabel.stringValue = ""
        }
        if visibleEntries.isEmpty {
            closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: false)
            closeQuickLookIfNeeded(restoreBrowsingFocus: false)
        } else {
            syncPreviewWithSelection()
        }
    }

    private func updateHeaderState() {
        let isFiltering = filterState.isFiltering
        countLabel.stringValue = isFiltering
            ? L10n.format("匹配 {0} / {1}", [visibleEntries.count, allEntries.count])
            : L10n.format("{0} 项", [allEntries.count])

        // 按钮常驻避免布局跳动；收藏板视图下没有可收藏的对象，置灰即可。
        favoriteButton.isEnabled = selectedPinboardID == nil && !visibleEntries.isEmpty

        if allEntries.isEmpty {
            emptyLabel.stringValue = selectedPinboardID == nil
                ? L10n.tr("还没有记录 · 先复制一些文本、图片或文件")
                : L10n.tr("这个收藏板还是空的 · 回到“最近”选择内容并收藏")
            emptyLabel.isHidden = false
        } else if visibleEntries.isEmpty {
            emptyLabel.stringValue = query.isEmpty
                ? L10n.tr("该类型下没有记录")
                : L10n.format("没有匹配「{0}」的记录", [query])
            emptyLabel.isHidden = false
        } else {
            emptyLabel.isHidden = true
        }
        updateHintLabel()
    }

    private func updateHintLabel() {
        let search = shortcutStore.displayString(for: .toggleSearchFocus)
        let preview = shortcutStore.displayString(for: .toggleQuickLook)
        let paste = shortcutStore.displayString(for: .pasteSelection)
        let close = shortcutStore.displayString(for: .clearSearchOrClose)
        let favorite = shortcutStore.displayString(for: .addToPinboard)
        let delete = shortcutStore.displayString(for: .deleteSelection)
        let isFiltering = filterState.isFiltering
        if selectedPinboardID != nil, isFiltering, !isSearchFieldFocused {
            hintLabel.stringValue = L10n.tr("当前正在筛选 · 清除搜索并选择“全部”后可拖动调整顺序")
        } else if isSearchFieldFocused {
            let closeHint = query.isEmpty ? L10n.format("{0} 关闭", [close]) : L10n.format("{0} 清除搜索", [close])
            hintLabel.stringValue = L10n.format("输入筛选 · {0} 返回浏览 · {1} 预览 · {2} 粘贴 · {3}", [search, preview, paste, closeHint])
        } else if selectedPinboardID != nil {
            hintLabel.stringValue = L10n.format("⇧点选多选 · ⌘A 全选 · {0} 预览 · {1} 移出 · {2} 粘贴 · {3} 关闭", [preview, delete, paste, close])
        } else {
            hintLabel.stringValue = L10n.format("⇧点选多选 · ⌘A 全选 · {0} 预览 · {1} 收藏 · {2} 粘贴 · {3} 关闭", [preview, favorite, paste, close])
        }
    }

    // MARK: 选择与动作

    private var selectedEntries: [ClipboardEntry] {
        visibleEntries.filter { selectedEntryIDs.contains($0.id) }
    }

    private func moveSelection(by offset: Int, extendingSelection: Bool = false) {
        guard !visibleEntries.isEmpty else { return }
        focusCollectionView()
        let newIndex = min(max(selectedIndex + offset, 0), visibleEntries.count - 1)
        if extendingSelection {
            extendSelection(to: newIndex, notifyActiveEntry: true)
        } else {
            selectAndChoose(index: newIndex, notifyWhenUnchanged: true)
        }
    }

    private var isSearchFieldFocused: Bool {
        guard let editor = searchField.currentEditor() else { return false }
        return window?.firstResponder === editor
    }

    private var isComposingSearchText: Bool {
        guard isSearchFieldFocused,
              let editor = searchField.currentEditor() as? NSTextView else { return false }
        return editor.hasMarkedText()
    }

    private func focusCollectionView() {
        window?.makeFirstResponder(collectionView)
        updateHintLabel()
    }

    private func focusSearchField() {
        window?.makeFirstResponder(searchField)
        updateHintLabel()
    }
    // MARK: 自适应预览与 Quick Look

    private var isAdaptivePreviewVisible: Bool {
        adaptivePreviewController.isVisible
    }

    private var isQuickLookVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared()?.isVisible == true
    }

    private func togglePreview() {
        if isPreviewSessionActive {
            endPreviewSession(restoreBrowsingFocus: true)
            return
        }

        guard previewSessionState.start() else { return }
        if showAdaptivePreviewIfSupported() {
            return
        }
        // 文件不提供预览：Quick Look 对多数文件只展示图标，价值低，
        // 而且面板尺寸异步重算会产生明显闪动。会话保持开启，
        // 继续按方向键切到文本/图片时会恢复预览。
        previewSessionState.recordUnavailable()
        statusLabel.stringValue = L10n.tr("文件没有预览 · 双击直接粘贴")
        statusLabel.textColor = palette.textSecondary
    }

    /// 结束预览会话：Space/Esc 显式关闭、窗口收起或切换数据源时调用。
    /// 会话结束后方向键浏览不再自动恢复预览。
    private func endPreviewSession(restoreBrowsingFocus: Bool) {
        previewSessionState.end()
        closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: false)
        closeQuickLookIfNeeded(restoreBrowsingFocus: false)
        if restoreBrowsingFocus {
            window?.makeKeyAndOrderFront(nil)
            focusCollectionView()
        }
    }

    private func showAdaptivePreviewIfSupported() -> Bool {
        guard visibleEntries.indices.contains(selectedIndex) else { return false }
        guard AdaptivePreviewController.supports(entry: visibleEntries[selectedIndex]) else {
            return false
        }
        collectionView.layoutSubtreeIfNeeded()
        guard let itemView = collectionView.item(at: selectedIndex)?.view else { return false }

        // 快速连续切换时也只允许一种预览存在。顺序很关键：必须先弹气泡再关
        // Quick Look——先关会让 QLPreviewPanel 在 popover.show 时复活（实测确认）。
        let didShow = adaptivePreviewController.show(
            entry: visibleEntries[selectedIndex],
            relativeTo: itemView,
            palette: palette
        ) { [weak self] in
            guard let self else { return }
            self.closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: false)
            self.showQuickLook()
        }
        if didShow {
            previewSessionState.recordAdaptiveShown()
            closeQuickLookIfNeeded(restoreBrowsingFocus: false)
        }
        return didShow
    }

    /// 选择变化后让预览跟随当前条目：会话内文本/图片保持轻量气泡；文件不提供预览，
    /// 选中文件时只暂时关闭预览，会话保持，切回文本/图片自动恢复。锚点未就绪时有限重试。
    private func syncPreviewWithSelection(retriesRemaining: Int = 3) {
        guard isPreviewSessionActive else { return }
        // scrollToItems 的布局在当前事件尾部才稳定；等布局完成后再换锚点。
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.window?.isVisible == true,
                  self.visibleEntries.indices.contains(self.selectedIndex) else { return }
            let entry = self.visibleEntries[self.selectedIndex]

            if AdaptivePreviewController.supports(entry: entry) {
                // showAdaptivePreviewIfSupported 内部会先弹气泡再关掉 Quick Look。
                if !self.showAdaptivePreviewIfSupported(), retriesRemaining > 0 {
                    // 快速切换时新卡片可能尚未滚动到位、锚点视图还没生成，稍后重试。
                    self.syncPreviewWithSelection(retriesRemaining: retriesRemaining - 1)
                }
                return
            }

            // 文件没有预览：关掉当前预览即可。
            self.closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: false)
            self.closeQuickLookIfNeeded(restoreBrowsingFocus: false)
            self.previewSessionState.recordUnavailable()
        }
    }

    private func closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: Bool) {
        if isAdaptivePreviewVisible {
            adaptivePreviewController.close()
        }
        if previewSessionState.presentation == .adaptive {
            previewSessionState.recordPresentationClosed()
        }
        if restoreBrowsingFocus {
            window?.makeKeyAndOrderFront(nil)
            focusCollectionView()
        }
    }

    private func showQuickLook() {
        closeAdaptivePreviewIfNeeded(restoreBrowsingFocus: false)
        guard visibleEntries.indices.contains(selectedIndex),
              quickLookPreviewStore.prepare(for: visibleEntries[selectedIndex]) != nil,
              let panel = QLPreviewPanel.shared() else {
            previewSessionState.recordUnavailable()
            NSSound.beep()
            return
        }
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        positionQuickLookPanel(panel)
        panel.makeKeyAndOrderFront(nil)
        previewSessionState.recordQuickLookShown()
        // Quick Look 内容异步载入后可能重算窗口尺寸，再约束一次目标屏幕。
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, let panel, panel.isVisible else { return }
            self.positionQuickLookPanel(panel)
        }
    }

    private func positionQuickLookPanel(_ panel: QLPreviewPanel) {
        guard !isPositioningQuickLookPanel else { return }
        collectionView.layoutSubtreeIfNeeded()
        let selectedItemScreen = collectionView.item(at: selectedIndex)?.view.window?.screen
        guard let screen = selectedItemScreen ?? window?.screen else { return }

        let visibleFrame = screen.visibleFrame
        let targetFrame = AdaptivePreviewSizing.centeredQuickLookFrame(
            panelSize: panel.frame.size,
            visibleFrame: visibleFrame
        )
        guard !panel.frame.approximatelyEquals(targetFrame) else { return }
        isPositioningQuickLookPanel = true
        panel.setFrame(targetFrame, display: false)
        isPositioningQuickLookPanel = false
    }

    private func closeQuickLookIfNeeded(restoreBrowsingFocus: Bool) {
        if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared() {
            // QLPreviewPanel 不吃 orderOut（isVisible 不变），close 才会真正关闭。
            if panel.isVisible { panel.close() }
            panel.dataSource = nil
            panel.delegate = nil
        }
        quickLookPreviewStore.clear()
        if previewSessionState.presentation == .quickLook {
            previewSessionState.recordPresentationClosed()
        }

        if restoreBrowsingFocus {
            window?.makeKeyAndOrderFront(nil)
            focusCollectionView()
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookPreviewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        quickLookPreviewURL as? QLPreviewItem
    }
    func previewPanel(
        _ panel: QLPreviewPanel!,
        sourceFrameOnScreenFor item: QLPreviewItem!
    ) -> NSRect {
        guard let window, let itemView = collectionView.item(at: selectedIndex)?.view else {
            return .zero
        }
        return window.convertToScreen(itemView.convert(itemView.bounds, to: nil))
    }

    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        quickLookPreviewStore.clear()
        if previewSessionState.presentation == .quickLook {
            previewSessionState.recordPresentationClosed()
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window?.isVisible == true, !self.isDismissing else { return }
            self.window?.makeKeyAndOrderFront(nil)
            self.focusCollectionView()
        }
    }
    private func selectAndChoose(index: Int, notifyWhenUnchanged: Bool) {
        guard visibleEntries.indices.contains(index) else { return }
        let entryID = visibleEntries[index].id
        let selectionChanged = selectionState.selectSingle(entryID)
        guard selectionChanged || notifyWhenUnchanged else { return }
        applySelectionState(notifyActiveEntry: true)
    }

    private func extendSelection(to index: Int, notifyActiveEntry: Bool) {
        guard visibleEntries.indices.contains(index) else { return }
        selectionState.extendSelection(to: visibleEntries[index].id, in: visibleEntryIDs)
        applySelectionState(notifyActiveEntry: notifyActiveEntry)
    }

    private func selectAllVisibleEntries() {
        guard !visibleEntries.isEmpty else { return }
        selectionState.selectAll(in: visibleEntryIDs)
        applySelectionState(notifyActiveEntry: false)
    }

    private func toggleSelection(at index: Int) {
        guard visibleEntries.indices.contains(index) else { return }
        let entryID = visibleEntries[index].id
        let previousActiveID = selectionState.activeID
        let didAddTarget = selectionState.toggle(entryID, in: visibleEntryIDs)
        applySelectionState(
            notifyActiveEntry: didAddTarget || selectionState.activeID != previousActiveID
        )
    }

    private func applySelectionState(notifyActiveEntry: Bool) {
        guard let activeIndex = selectionState.activeIndex(in: visibleEntryIDs) else { return }
        let selectedIndexes = selectionState.selectedIndexes(in: visibleEntryIDs)
        guard !selectedIndexes.isEmpty else { return }
        suppressSelectionCallback = true
        let indexPaths = Set(selectedIndexes.map { IndexPath(item: $0, section: 0) })
        collectionView.selectionIndexPaths = indexPaths
        let activeIndexPath = IndexPath(item: activeIndex, section: 0)
        collectionView.scrollToItems(
            at: [activeIndexPath],
            scrollPosition: .centeredHorizontally
        )
        suppressSelectionCallback = false
        if notifyActiveEntry {
            chooseEntry(at: activeIndex)
        } else {
            updateSelectionStatus()
        }
        syncPreviewWithSelection()
    }

    private func chooseEntry(at index: Int) {
        guard visibleEntries.indices.contains(index) else { return }
        let entry = visibleEntries[index]
        onChoose?(entry)
        updateSelectionStatus()
    }

    private func updateSelectionStatus() {
        let selectedCount = selectedEntryIDs.count
        if selectedCount > 1 {
            statusLabel.stringValue = L10n.format("已选择 {0} 项 · 预览与粘贴使用当前卡片", [selectedCount])
        } else if selectedCount == 1 {
            statusLabel.stringValue = L10n.format("已选择并复制 {0} / {1} · 双击可粘贴", [selectedIndex + 1, visibleEntries.count])
        } else {
            statusLabel.stringValue = ""
        }
        statusLabel.textColor = palette.accent
    }

    private func confirmAndPaste() {
        guard visibleEntries.indices.contains(selectedIndex) else { return }
        let entry = visibleEntries[selectedIndex]
        onChoose?(entry)
        let result = onPaste?(entry, pasteTargetApplication) ?? .targetUnavailable
        switch result {
        case .started:
            dismiss(restorePreviousApplication: false)
        case .permissionRequired:
            statusLabel.stringValue = L10n.tr("请在“系统设置 → 隐私与安全性 → 辅助功能”中允许 cpsmart")
            statusLabel.textColor = .systemOrange
            NSSound.beep()
            showAccessibilityPermissionHelp()
        case .targetUnavailable:
            statusLabel.stringValue = L10n.tr("无法找到刚才使用的应用，请关闭浮窗后重试")
            statusLabel.textColor = .systemOrange
            NSSound.beep()
        }
    }

    private func showAccessibilityPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("自动粘贴需要“辅助功能”权限")
        alert.informativeText = L10n.tr("accessibility.repairInstructions")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("清除旧记录、打开设置并退出"))
        alert.addButton(withTitle: L10n.tr("仅打开设置"))
        alert.addButton(withTitle: L10n.tr("稍后"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if !AccessibilityPermissionSupport.resetCurrentApplication() {
                let failureAlert = NSAlert()
                failureAlert.messageText = L10n.tr("无法自动重置旧权限")
                failureAlert.informativeText = L10n.tr("请在接下来打开的辅助功能设置中手动删除旧 cpsmart，再点击“+”添加 /Applications/cpsmart.app。")
                failureAlert.alertStyle = .warning
                failureAlert.addButton(withTitle: L10n.tr("继续"))
                failureAlert.runModal()
            }
            AccessibilityPermissionSupport.openSettings()
            NSApp.terminate(nil)
        case .alertSecondButtonReturn:
            AccessibilityPermissionSupport.openSettings()
        default:
            break
        }
    }

    private func deleteSelection() {
        let entries = selectedEntries
        guard !entries.isEmpty else { return }
        guard entries.count > 1 else {
            performDelete(entries)
            return
        }
        guard let window else { return }
        let isRemovingFromPinboard = selectedPinboardID != nil
        let alert = NSAlert()
        alert.messageText = isRemovingFromPinboard
            ? L10n.format("从收藏板移出所选的 {0} 项？", [entries.count])
            : L10n.format("删除所选的 {0} 条历史记录？", [entries.count])
        alert.informativeText = L10n.tr("删除后可按 ⌘Z 恢复最近一次操作。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: isRemovingFromPinboard ? L10n.tr("移出") : L10n.tr("删除"))
        alert.addButton(withTitle: L10n.tr("取消"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.performDelete(entries)
        }
    }

    private func performDelete(_ entries: [ClipboardEntry]) {
        let removedCount: Int
        let statusKey: String
        if let selectedPinboardID {
            removedCount = onRemoveFromPinboard?(entries, selectedPinboardID) ?? 0
            statusKey = "已从收藏板移出 {0} 项 · ⌘Z 撤销"
        } else {
            removedCount = onDelete?(entries) ?? 0
            statusKey = "已删除 {0} 项 · ⌘Z 撤销"
        }
        guard removedCount > 0 else { return }
        hasPendingDeletionUndo = true
        statusLabel.stringValue = L10n.format(statusKey, [removedCount])
        statusLabel.textColor = palette.accent
    }

    private func undoLastDeletion() {
        guard hasPendingDeletionUndo else { return }
        let restoredCount = onUndoDelete?() ?? 0
        guard restoredCount > 0 else {
            hasPendingDeletionUndo = false
            statusLabel.stringValue = L10n.tr("最近删除已无法恢复")
            statusLabel.textColor = .systemOrange
            NSSound.beep()
            return
        }
        hasPendingDeletionUndo = false
        statusLabel.stringValue = L10n.format("已恢复 {0} 项", [restoredCount])
        statusLabel.textColor = palette.accent
    }

    func clearDeletionUndo() {
        hasPendingDeletionUndo = false
    }

    private func togglePinSelection() {
        // 收藏板内顺序由拖动排序管理，置顶没有语义；给出可感知反馈而不是静默吞键。
        guard selectedPinboardID == nil else {
            NSSound.beep()
            return
        }
        guard selectedEntryIDs.count == 1 else {
            statusLabel.stringValue = L10n.tr("批量置顶暂不支持，请只选择一项")
            statusLabel.textColor = .systemOrange
            NSSound.beep()
            return
        }
        guard visibleEntries.indices.contains(selectedIndex) else { return }
        onTogglePin?(visibleEntries[selectedIndex])
    }

    private func clearSearch() {
        searchField.stringValue = ""
        filterState.updateQuery("")
        refilter(fallbackIndex: selectedIndex)
        statusLabel.stringValue = ""
    }

    func runPackageSmokeValidation(
        expectedScreenIndex: Int,
        reportURL: URL,
        completion: @escaping () -> Void
    ) {
        let host = PackageSmokeHost(
            window: { [weak self] in self?.window },
            snapshot: { [unowned self] in
                PackageSmokeSnapshot(
                    visibleEntryIDs: visibleEntryIDs,
                    pinboardIDs: pinboards.map(\.id),
                    selectedPinboardID: selectedPinboardID,
                    selectedIndex: selectedIndex,
                    selectedEntryIDs: selectedEntryIDs,
                    hasPendingDeletionUndo: hasPendingDeletionUndo,
                    query: query,
                    historyEntryCount: historyEntries.count,
                    isSearchFieldFocused: isSearchFieldFocused,
                    isPreviewSessionActive: isPreviewSessionActive,
                    isAdaptivePreviewVisible: isAdaptivePreviewVisible,
                    isQuickLookVisible: isQuickLookVisible,
                    isWindowVisible: window?.isVisible == true
                )
            },
            selectIndex: { [weak self] index in
                self?.selectAndChoose(index: index, notifyWhenUnchanged: true)
            },
            postCardClick: { [weak self] index, modifiers, clickCount, callback in
                guard let self else {
                    callback(false)
                    return
                }
                self.postPackageSmokeCardClick(
                    at: index,
                    modifiers: modifiers,
                    clickCount: clickCount,
                    completion: callback
                )
            },
            postKey: { [weak self] keyCode, modifiers, characters, callback in
                guard let self else {
                    callback()
                    return
                }
                self.postPackageSmokeKey(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    characters: characters,
                    completion: callback
                )
            },
            installChooseObserver: { [weak self] observer in
                guard let self else { return {} }
                let originalOnChoose = self.onChoose
                self.onChoose = { entry in
                    observer(entry.id)
                    originalOnChoose?(entry)
                }
                return { [weak self] in
                    self?.onChoose = originalOnChoose
                }
            },
            installPasteStub: { [weak self] observer in
                self?.onPaste = { _, _ in
                    observer()
                    return .started
                }
            }
        )
        PackageSmokeValidationDriver(
            expectedScreenIndex: expectedScreenIndex,
            reportURL: reportURL,
            host: host,
            completion: completion
        ).run()
    }

    private func postPackageSmokeCardClick(
        at index: Int,
        modifiers: NSEvent.ModifierFlags,
        clickCount: Int = 1,
        completion: @escaping (Bool) -> Void
    ) {
        guard visibleEntries.indices.contains(index), let window else {
            completion(false)
            return
        }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredHorizontally)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak window] in
            guard let self, let window else {
                completion(false)
                return
            }
            self.collectionView.layoutSubtreeIfNeeded()
            guard let itemView = self.collectionView.item(at: index)?.view else {
                completion(false)
                return
            }
            let location = itemView.convert(
                NSPoint(x: itemView.bounds.midX, y: itemView.bounds.midY),
                to: nil
            )
            guard let mouseDown = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: location,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: clickCount,
                pressure: 1
            ), let mouseUp = NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: location,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 2,
                clickCount: clickCount,
                pressure: 0
            ) else {
                completion(false)
                return
            }
            NSApp.postEvent(mouseDown, atStart: false)
            NSApp.postEvent(mouseUp, atStart: false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                completion(true)
            }
        }
    }

    private func postPackageSmokeKey(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String,
        completion: @escaping () -> Void
    ) {
        guard let window,
              let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
              ) else {
            completion()
            return
        }
        NSApp.postEvent(event, atStart: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: completion)
    }

    // MARK: 搜索与筛选

    #if DEBUG
    /// 开发用：演示模式下预填搜索词，便于截图验证过滤渲染。
    func applyDemoQuery(_ demoQuery: String) {
        searchField.stringValue = demoQuery
        filterState.updateQuery(demoQuery)
        refilter(fallbackIndex: 0)
        focusSearchField()
    }

    /// 开发用：直接选中演示记录并打开预览，便于自动截图检查不同内容尺寸。
    func showDemoPreview(at index: Int) {
        guard visibleEntries.indices.contains(index) else { return }
        selectAndChoose(index: index, notifyWhenUnchanged: true)
        togglePreview()
    }

    func applyDemoPinboard(at index: Int) {
        guard pinboards.indices.contains(index) else { return }
        switchSource(to: pinboards[index].id)
    }

    /// 开发用：构造连续多选状态，供应用自身快照验证选中样式。
    func applyDemoSelection(from anchorIndex: Int, to targetIndex: Int) {
        guard visibleEntries.indices.contains(anchorIndex),
              visibleEntries.indices.contains(targetIndex) else { return }
        selectAndChoose(index: anchorIndex, notifyWhenUnchanged: true)
        extendSelection(to: targetIndex, notifyActiveEntry: false)
    }

    /// 开发用：验证预览会话——文本开预览 → 右移到文件（预览暂关、会话保持）
    /// → 左移回文本（预览自动恢复）。
    func runDemoPreviewSession(textIndex: Int, logURL: URL) {
        guard visibleEntries.indices.contains(textIndex),
              visibleEntries.indices.contains(textIndex + 1) else { return }
        var lines: [String] = []
        selectAndChoose(index: textIndex, notifyWhenUnchanged: true)
        togglePreview()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            lines.append("open text: pop=\(self.isAdaptivePreviewVisible) ql=\(self.isQuickLookVisible) session=\(self.isPreviewSessionActive)")
            self.moveSelection(by: 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                lines.append("-> file: pop=\(self.isAdaptivePreviewVisible) ql=\(self.isQuickLookVisible) session=\(self.isPreviewSessionActive)")
                self.moveSelection(by: -1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self else { return }
                    lines.append("-> text: pop=\(self.isAdaptivePreviewVisible) ql=\(self.isQuickLookVisible) session=\(self.isPreviewSessionActive)")
                    try? lines.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
                }
            }
        }
    }

    /// 开发用：直接弹出新建收藏板 sheet，验证表单布局（名称输入框 + 色点行）。
    func showDemoNewPinboardSheet() {
        guard let window else { return }
        pinboardInteractionCoordinator.presentCreate(on: window, adding: [])
    }

    /// 开发用：直接渲染浮窗内容，避免多屏坐标和窗口共享策略影响自动截图。
    @discardableResult
    func writeDemoSnapshot(to url: URL) -> Bool {
        guard let contentView = window?.contentView else { return false }
        contentView.layoutSubtreeIfNeeded()
        guard let representation = contentView.bitmapImageRepForCachingDisplay(
            in: contentView.bounds
        ) else { return false }
        contentView.cacheDisplay(in: contentView.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("cpsmart could not write demo snapshot: %@", error.localizedDescription)
            return false
        }
    }
    #endif

    func controlTextDidChange(_ notification: Notification) {
        filterState.updateQuery(searchField.stringValue)
        refilter(fallbackIndex: 0)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        updateHintLabel()
    }

    @objc private func filterChanged(_ sender: NSSegmentedControl) {
        filterState.updateType(rawValue: sender.selectedSegment)
        refilter(fallbackIndex: 0)
        focusCollectionView()
    }

    // MARK: 关闭

    private func dismiss(restorePreviousApplication: Bool) {
        guard let window, window.isVisible, !isDismissing else { return }
        isDismissing = true
        dismissalGeneration += 1
        let generation = dismissalGeneration
        removeKeyboardMonitor()
        endPreviewSession(restoreBrowsingFocus: false)
        thumbnailProvider.cancelAll()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = HistoryWindowTheme.exitDuration
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self, weak window] in
            guard let self else { return }
            // 动画期间若被重新唤起，此回调已作废，不能隐藏新窗口。
            guard generation == self.dismissalGeneration else { return }
            window?.orderOut(nil)
            window?.alphaValue = 1
            self.isDismissing = false
            if restorePreviousApplication,
               let targetApplication = self.pasteTargetApplication,
               targetApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                targetApplication.activate(options: [.activateIgnoringOtherApps])
            }
            self.previousApplication = nil
        })
    }

    // MARK: 键盘

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self,
                  self.window?.isVisible == true,
                  self.handleKeyboardEvent(event) else {
                return event
            }
            return nil
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            guard let self,
                  let window = self.window,
                  window.isVisible,
                  event.window === window else {
                return event
            }

            let pointInSearchField = self.searchField.convert(event.locationInWindow, from: nil)
            guard !self.searchField.bounds.contains(pointInSearchField) else { return event }

            // 让控件先完成自己的点击行为，再把键盘焦点交给卡片列表。
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, window.isVisible, !self.isDismissing else { return }
                self.focusCollectionView()
            }
            return event
        }
    }

    private func removeKeyboardMonitor() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    private func handleKeyboardEvent(_ event: NSEvent) -> Bool {
        // 浮窗上挂着 sheet（新建/重命名收藏板等）时，键盘属于 sheet 的输入框，
        // 不能按历史窗口的快捷键逻辑拦截，否则名称根本无法输入。
        if window?.attachedSheet != nil { return false }

        // 收藏板切换属于窗口级导航：在浏览、搜索和预览中都应生效，并由
        // switchSource 统一结束预览、清除筛选和恢复卡片焦点。
        if handlePinboardShortcut(event) { return true }

        if isAdaptivePreviewVisible {
            // 与 Quick Look 使用同一组上下文，确保自定义快捷键在轻量预览中同样生效。
            switch shortcutMatcher.action(for: event, context: .quickLook) {
            case .toggleQuickLook, .clearSearchOrClose:
                if !event.isARepeat {
                    endPreviewSession(restoreBrowsingFocus: true)
                }
                return true
            case .selectPrevious:
                moveSelection(by: -1)
                return true
            case .selectNext:
                moveSelection(by: 1)
                return true
            default:
                // 允许 ⌘C 等文本选择相关快捷键继续交给只读预览文本。
                return false
            }
        }

        if isQuickLookVisible {
            switch shortcutMatcher.action(for: event, context: .quickLook) {
            case .toggleQuickLook, .clearSearchOrClose:
                if !event.isARepeat {
                    endPreviewSession(restoreBrowsingFocus: true)
                }
            case .selectPrevious:
                // moveSelection 内部已经同步预览；不要再调一次 syncPreviewWithSelection——
                // 重复执行会让气泡重弹，把正在关闭的 Quick Look 面板复活。
                moveSelection(by: -1)
            case .selectNext:
                moveSelection(by: 1)
            default:
                break
            }
            return true
        }

        let context: ShortcutContext
        if isComposingSearchText {
            context = .composingSearchText
        } else if isSearchFieldFocused {
            context = .searching
        } else {
            context = .browsing
        }

        if context == .browsing {
            let modifiers = ShortcutGesture.normalized(event.modifierFlags)
            if hasPendingDeletionUndo,
               modifiers == [.command],
               event.keyCode == UInt16(kVK_ANSI_Z) {
                undoLastDeletion()
                return true
            }
            if modifiers == [.command], event.keyCode == UInt16(kVK_ANSI_A) {
                selectAllVisibleEntries()
                return true
            }
            if modifiers.contains(.shift),
               let navigationAction = shiftedNavigationAction(for: event) {
                moveSelection(
                    by: navigationAction == .selectPrevious ? -1 : 1,
                    extendingSelection: true
                )
                return true
            }
        }

        guard let action = shortcutMatcher.action(for: event, context: context) else {
            if context == .browsing, isPrintableTextInput(event) {
                // 浏览态必须先使用配置的搜索快捷键，避免无意按键改变筛选结果。
                return true
            }
            return false
        }

        switch action {
        case .selectPrevious:
            moveSelection(by: -1)
        case .selectNext:
            moveSelection(by: 1)
        case .toggleSearchFocus:
            if isSearchFieldFocused {
                focusCollectionView()
            } else {
                focusSearchField()
            }
        case .pasteSelection:
            confirmAndPaste()
        case .toggleQuickLook:
            if !event.isARepeat {
                togglePreview()
            }
        case .togglePin:
            togglePinSelection()
        case .addToPinboard:
            showFavoriteMenu(favoriteButton)
        case .deleteSelection:
            deleteSelection()
        case .filterAll:
            applyFilterShortcut(segment: 0)
        case .filterText:
            applyFilterShortcut(segment: 1)
        case .filterImage:
            applyFilterShortcut(segment: 2)
        case .filterFiles:
            applyFilterShortcut(segment: 3)
        case .clearSearchOrClose:
            if isPreviewSessionActive {
                // 会话内选中文件时没有可见预览，Esc 仍应先结束预览会话。
                endPreviewSession(restoreBrowsingFocus: true)
            } else if !query.isEmpty {
                clearSearch()
            } else {
                dismiss(restorePreviousApplication: true)
            }
        case .toggleHistory:
            return false
        }
        return true
    }

    private func shiftedNavigationAction(for event: NSEvent) -> ShortcutActionID? {
        let actions: [ShortcutActionID] = [.selectPrevious, .selectNext]
        let exactGesture = ShortcutGesture.from(event: event)
        if let action = shortcutStore.action(matching: exactGesture, among: actions) {
            return action
        }
        let modifiersWithoutShift = ShortcutGesture.normalized(event.modifierFlags)
            .subtracting(.shift)
        let baseGesture = ShortcutGesture(
            keyCode: event.keyCode,
            modifiers: modifiersWithoutShift,
            recordedKeyLabel: event.charactersIgnoringModifiers
        )
        return shortcutStore.action(matching: baseGesture, among: actions)
    }

    private func applyFilterShortcut(segment: Int) {
        filterControl.selectedSegment = segment
        filterChanged(filterControl)
    }

    private func isPrintableTextInput(_ event: NSEvent) -> Bool {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .function]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty,
              let characters = event.characters,
              !characters.isEmpty else { return false }
        return characters.unicodeScalars.contains {
            !CharacterSet.controlCharacters.contains($0)
        }
    }

    // MARK: 前台应用追踪

    private func rememberExternalApplication(_ application: NSRunningApplication?) {
        guard isExternalApplication(application) else { return }
        lastExternalApplication = application
    }

    private func isExternalApplication(_ application: NSRunningApplication?) -> Bool {
        guard let application, !application.isTerminated else { return false }
        return application.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    // MARK: NSCollectionViewDataSource / Delegate

    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        visibleEntries.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: Self.itemIdentifier,
            for: indexPath
        ) as! HistoryCollectionItem
        let representedEntry = visibleEntries[indexPath.item]
        item.configure(
            with: representedEntry,
            thumbnails: thumbnailProvider,
            palette: palette
        )
        item.onClick = { [weak self] clickCount, modifiers in
            guard let self else { return }
            self.focusCollectionView()
            let normalizedModifiers = ShortcutGesture.normalized(modifiers)
            if normalizedModifiers.contains(.shift) {
                self.extendSelection(to: indexPath.item, notifyActiveEntry: true)
            } else if normalizedModifiers.contains(.command) {
                self.toggleSelection(at: indexPath.item)
            } else {
                self.selectAndChoose(index: indexPath.item, notifyWhenUnchanged: true)
            }
            if clickCount >= 2 {
                self.confirmAndPaste()
            }
        }
        item.onDrag = { [weak self] event, sourceView in
            self?.beginCardDrag(entry: representedEntry, event: event, sourceView: sourceView)
        }
        return item
    }

    private func beginCardDrag(entry: ClipboardEntry, event: NSEvent, sourceView: NSView) {
        if selectedPinboardID != nil, !filterState.allowsPinboardReordering {
            NSSound.beep()
            statusLabel.stringValue = L10n.tr("清除搜索并选择“全部”后可调整收藏顺序")
            statusLabel.textColor = .systemOrange
            return
        }
        guard PinboardDragRules.canBeginDrag(
            selectedItemCount: selectedEntryIDs.count,
            itemIsVisible: visibleEntryIDs.contains(entry.id) && selectedEntryIDs.contains(entry.id),
            sourcePinboardID: selectedPinboardID,
            allowsPinboardReordering: filterState.allowsPinboardReordering
        ) else {
            NSSound.beep()
            statusLabel.stringValue = selectedEntryIDs.count > 1
                ? L10n.tr("暂不支持批量拖动，请只选择一项")
                : L10n.tr("请先选择要拖动的项目")
            statusLabel.textColor = .systemOrange
            return
        }

        let descriptor = PinboardDragDescriptor(
            entryID: entry.id,
            sourcePinboardID: selectedPinboardID
        )
        let draggingItem = NSDraggingItem(pasteboardWriter: descriptor.pasteboardItem())
        let frame = sourceView.convert(sourceView.bounds, to: collectionView)
        draggingItem.setDraggingFrame(frame, contents: snapshotImage(of: sourceView))
        let session = collectionView.beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func snapshotImage(of view: NSView) -> NSImage {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return NSImage(size: view.bounds.size)
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(representation)
        return image
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        PinboardDragRules.sourceOperation(sourcePinboardID: selectedPinboardID)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        canDragItemsAt indexPaths: Set<IndexPath>,
        with event: NSEvent
    ) -> Bool {
        let indexPath = indexPaths.first
        return PinboardDragRules.canBeginDrag(
            selectedItemCount: indexPaths.count,
            itemIsVisible: indexPath.map { visibleEntries.indices.contains($0.item) } ?? false,
            sourcePinboardID: selectedPinboardID,
            allowsPinboardReordering: filterState.allowsPinboardReordering
        )
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard visibleEntries.indices.contains(indexPath.item) else { return nil }
        return PinboardDragDescriptor(
            entryID: visibleEntries[indexPath.item].id,
            sourcePinboardID: selectedPinboardID
        ).pasteboardItem()
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        guard PinboardDragRules.reorderDescriptor(
            from: draggingInfo.draggingPasteboard,
            targetPinboardID: selectedPinboardID,
            allowsPinboardReordering: filterState.allowsPinboardReordering
        ) != nil else { return [] }
        proposedDropOperation.pointee = .before
        return .move
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        guard let boardID = selectedPinboardID,
              let descriptor = PinboardDragRules.reorderDescriptor(
                  from: draggingInfo.draggingPasteboard,
                  targetPinboardID: boardID,
                  allowsPinboardReordering: filterState.allowsPinboardReordering
              ) else { return false }
        onMovePinboardEntry?(descriptor.entryID, boardID, indexPath.item)
        return true
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        guard !suppressSelectionCallback else { return }
        let indexes = Set(indexPaths.map(\.item).filter { visibleEntries.indices.contains($0) })
        guard let activeIndex = indexes.sorted().first else { return }
        let selectedIDs = Set(indexes.map { visibleEntries[$0].id })
        selectionState.replaceSelection(
            selectedIDs,
            activeID: visibleEntries[activeIndex].id,
            anchorID: visibleEntries[activeIndex].id,
            in: visibleEntryIDs
        )
        applySelectionState(notifyActiveEntry: true)
    }
}
