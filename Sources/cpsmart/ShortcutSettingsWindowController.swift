import AppKit
import Carbon

private extension ShortcutActionID {
    var settingsDescription: String {
        switch self {
        case .toggleHistory: return L10n.tr("在任何应用中打开或收起剪贴板历史")
        case .selectPrevious: return L10n.tr("在卡片之间向前移动选择")
        case .selectNext: return L10n.tr("在卡片之间向后移动选择")
        case .toggleSearchFocus: return L10n.tr("在卡片列表和搜索框之间切换")
        case .pasteSelection: return L10n.tr("把当前卡片粘贴到之前使用的应用")
        case .toggleQuickLook: return L10n.tr("预览当前选中的内容")
        case .togglePin: return L10n.tr("保留常用内容，不受自动清理影响")
        case .addToPinboard: return L10n.tr("把当前内容保存到命名和着色的收藏板")
        case .deleteSelection: return L10n.tr("移除当前选中的历史记录")
        case .filterAll: return L10n.tr("显示所有类型的内容")
        case .filterText: return L10n.tr("只显示文本内容")
        case .filterImage: return L10n.tr("只显示图片内容")
        case .filterFiles: return L10n.tr("只显示文件内容")
        case .clearSearchOrClose: return L10n.tr("先清除搜索；再次按下时关闭窗口")
        }
    }
}

private final class ShortcutKeycapView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var palette = AppVisualTheme.palette(isDark: true)
    private let isSeparator: Bool

    init(token: String, separator: Bool = false) {
        isSeparator = separator
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = token
        label.alignment = .center
        label.font = separator
            ? .systemFont(ofSize: 11, weight: .medium)
            : .monospacedSystemFont(ofSize: token.count > 3 ? 10.5 : 12.5, weight: .semibold)
        addSubview(label)

        let width = max(separator ? 8 : 25, CGFloat(token.count) * (token.count > 3 ? 7 : 9) + 12)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(equalToConstant: separator ? 24 : 25),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: separator ? 0 : 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: separator ? 0 : -5),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyPalette(_ palette: Palette) {
        self.palette = palette
        label.textColor = isSeparator ? palette.textTertiary : palette.textPrimary
        needsDisplay = true
    }

    override func updateLayer() {
        guard !isSeparator else {
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
            return
        }
        layer?.cornerRadius = 6
        layer?.backgroundColor = palette.thumbPlaceholder.cgColor
        layer?.borderColor = palette.cardBorder.cgColor
        layer?.borderWidth = 0.75
    }
}

private final class ShortcutRecorderControl: NSControl {
    let shortcutAction: ShortcutActionID
    var onRecord: ((ShortcutActionID, ShortcutGesture) -> String?)?
    var onRecordingChanged: ((Bool) -> Void)?

    private let tokenStack = NSStackView()
    private let recordingLabel = NSTextField(labelWithString: L10n.tr("按下新快捷键…"))
    private var displayedBindings: [ShortcutGesture] = []
    private var palette = AppVisualTheme.palette(isDark: true)
    private var trackingAreaReference: NSTrackingArea?
    private var isHovered = false
    private(set) var isRecordingShortcut = false

    init(shortcutAction: ShortcutActionID) {
        self.shortcutAction = shortcutAction
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        focusRingType = .exterior
        toolTip = L10n.tr("点击后按下新的快捷键")
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(L10n.format("{0}快捷键", [shortcutAction.displayName]))

        tokenStack.translatesAutoresizingMaskIntoConstraints = false
        tokenStack.orientation = .horizontal
        tokenStack.alignment = .centerY
        tokenStack.spacing = 4
        addSubview(tokenStack)

        recordingLabel.translatesAutoresizingMaskIntoConstraints = false
        recordingLabel.font = .systemFont(ofSize: 12, weight: .medium)
        recordingLabel.alignment = .center
        recordingLabel.isHidden = true
        addSubview(recordingLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 174),
            heightAnchor.constraint(equalToConstant: 38),
            tokenStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            tokenStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            tokenStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            tokenStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            recordingLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            recordingLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            recordingLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { needsDisplay = true }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign {
            cancelRecording()
            needsDisplay = true
        }
        return didResign
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isRecordingShortcut ? stopAndResign() : beginRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingShortcut else {
            if event.keyCode == UInt16(kVK_Space)
                || event.keyCode == UInt16(kVK_Return)
                || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
                beginRecording()
                return
            }
            super.keyDown(with: event)
            return
        }
        capture(event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func accessibilityPerformPress() -> Bool {
        isRecordingShortcut ? stopAndResign() : beginRecording()
        return true
    }

    func applyPalette(_ palette: Palette) {
        self.palette = palette
        recordingLabel.textColor = palette.accent
        tokenStack.arrangedSubviews.compactMap { $0 as? ShortcutKeycapView }
            .forEach { $0.applyPalette(palette) }
        needsDisplay = true
    }

    func updateDisplay(_ bindings: [ShortcutGesture]) {
        displayedBindings = bindings
        guard !isRecordingShortcut else { return }
        rebuildTokens()
        setAccessibilityValue(bindings.map(\.displayString).joined(separator: L10n.tr(" 或 ")))
    }

    func cancelRecording() {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        recordingLabel.isHidden = true
        tokenStack.isHidden = false
        rebuildTokens()
        onRecordingChanged?(false)
        needsDisplay = true
    }

    func capture(_ event: NSEvent) {
        guard isRecordingShortcut, !event.isARepeat else { return }
        let gesture = ShortcutGesture.from(event: event)
        if onRecord?(shortcutAction, gesture) != nil { NSSound.beep() }
        stopAndResign()
    }

    override func updateLayer() {
        let fill: NSColor
        let border: NSColor
        if isRecordingShortcut {
            fill = palette.cardFillSelected
            border = palette.accent.withAlphaComponent(0.9)
        } else if isHovered || window?.firstResponder === self {
            fill = palette.cardFillHover
            border = window?.firstResponder === self ? palette.accent : palette.panelBorder
        } else {
            fill = palette.cardFill
            border = palette.cardBorder
        }
        layer?.cornerRadius = AppVisualTheme.controlRadius
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = border.cgColor
        layer?.borderWidth = isRecordingShortcut ? 1.5 : 0.75
    }

    private func beginRecording() {
        guard !isRecordingShortcut else { return }
        isRecordingShortcut = true
        tokenStack.isHidden = true
        recordingLabel.isHidden = false
        onRecordingChanged?(true)
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func stopAndResign() {
        cancelRecording()
        window?.makeFirstResponder(nil)
    }

    private func rebuildTokens() {
        tokenStack.arrangedSubviews.forEach {
            tokenStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for (bindingIndex, binding) in displayedBindings.enumerated() {
            if bindingIndex > 0 {
                let separator = ShortcutKeycapView(token: "/", separator: true)
                separator.applyPalette(palette)
                tokenStack.addArrangedSubview(separator)
            }
            for token in binding.displayTokens {
                let keycap = ShortcutKeycapView(token: token)
                keycap.applyPalette(palette)
                tokenStack.addArrangedSubview(keycap)
            }
        }
    }
}

private final class ShortcutRowView: NSView {
    private enum FeedbackKind { case error, success }

    let shortcutAction: ShortcutActionID
    let recorder: ShortcutRecorderControl
    var onReset: ((ShortcutActionID) -> Void)?
    var onSwap: ((ShortcutActionID, ShortcutActionID, ShortcutGesture) -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let modifiedBadge = NSView()
    private let modifiedBadgeLabel = NSTextField(labelWithString: L10n.tr("已修改"))
    private let resetButton = NSButton()
    private let feedbackContainer = NSView()
    private let feedbackIcon = NSImageView()
    private let feedbackLabel = NSTextField(wrappingLabelWithString: "")
    private let swapButton = NSButton()
    private var pendingSwap: (ShortcutActionID, ShortcutGesture)?
    private var feedbackKind: FeedbackKind?
    private var feedbackHeightConstraint: NSLayoutConstraint!
    private var palette = AppVisualTheme.palette(isDark: true)

    init(action: ShortcutActionID) {
        shortcutAction = action
        recorder = ShortcutRecorderControl(shortcutAction: action)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = action.displayName
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .medium)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        detailLabel.stringValue = action.settingsDescription
        detailLabel.font = .systemFont(ofSize: 11.5)
        detailLabel.lineBreakMode = .byTruncatingTail

        let copy = NSStackView(views: [titleLabel, detailLabel])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 2
        copy.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // 徽标用容器加居中约束实现；直接拉高 NSTextField 会让文字贴顶。
        modifiedBadge.translatesAutoresizingMaskIntoConstraints = false
        modifiedBadge.wantsLayer = true
        modifiedBadge.isHidden = true
        modifiedBadge.setAccessibilityElement(true)
        modifiedBadge.setAccessibilityLabel(L10n.tr("已修改"))
        modifiedBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        modifiedBadgeLabel.font = .systemFont(ofSize: 9.5, weight: .semibold)
        modifiedBadgeLabel.alignment = .center
        modifiedBadge.addSubview(modifiedBadgeLabel)
        NSLayoutConstraint.activate([
            modifiedBadge.widthAnchor.constraint(equalToConstant: 42),
            modifiedBadge.heightAnchor.constraint(equalToConstant: 20),
            modifiedBadgeLabel.centerXAnchor.constraint(equalTo: modifiedBadge.centerXAnchor),
            modifiedBadgeLabel.centerYAnchor.constraint(equalTo: modifiedBadge.centerYAnchor)
        ])

        resetButton.title = L10n.tr("恢复")
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        resetButton.font = .systemFont(ofSize: 11, weight: .medium)
        resetButton.target = self
        resetButton.action = #selector(resetAction)
        resetButton.toolTip = L10n.tr("仅恢复这一项")
        resetButton.isHidden = true
        resetButton.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        copy.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let body = NSStackView(views: [copy, spacer, modifiedBadge, resetButton, recorder])
        body.translatesAutoresizingMaskIntoConstraints = false
        body.orientation = .horizontal
        body.alignment = .centerY
        body.spacing = 8
        addSubview(body)

        feedbackContainer.translatesAutoresizingMaskIntoConstraints = false
        feedbackContainer.isHidden = true
        addSubview(feedbackContainer)

        feedbackIcon.translatesAutoresizingMaskIntoConstraints = false
        feedbackIcon.imageScaling = .scaleProportionallyDown
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        feedbackLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        feedbackLabel.maximumNumberOfLines = 2
        feedbackLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        swapButton.translatesAutoresizingMaskIntoConstraints = false
        swapButton.bezelStyle = .inline
        swapButton.controlSize = .small
        swapButton.target = self
        swapButton.action = #selector(swapAction)
        swapButton.isHidden = true
        feedbackContainer.addSubview(feedbackIcon)
        feedbackContainer.addSubview(feedbackLabel)
        feedbackContainer.addSubview(swapButton)

        feedbackHeightConstraint = feedbackContainer.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 68),
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            body.topAnchor.constraint(equalTo: topAnchor, constant: 12),

            feedbackContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            feedbackContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            feedbackContainer.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 7),
            feedbackContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            feedbackHeightConstraint,

            feedbackIcon.leadingAnchor.constraint(equalTo: feedbackContainer.leadingAnchor),
            feedbackIcon.topAnchor.constraint(equalTo: feedbackContainer.topAnchor, constant: 1),
            feedbackIcon.widthAnchor.constraint(equalToConstant: 14),
            feedbackIcon.heightAnchor.constraint(equalToConstant: 14),
            feedbackLabel.leadingAnchor.constraint(equalTo: feedbackIcon.trailingAnchor, constant: 6),
            feedbackLabel.centerYAnchor.constraint(equalTo: feedbackIcon.centerYAnchor),
            feedbackLabel.trailingAnchor.constraint(lessThanOrEqualTo: swapButton.leadingAnchor, constant: -8),
            swapButton.trailingAnchor.constraint(equalTo: feedbackContainer.trailingAnchor),
            swapButton.centerYAnchor.constraint(equalTo: feedbackIcon.centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyPalette(_ palette: Palette) {
        self.palette = palette
        titleLabel.textColor = palette.textPrimary
        detailLabel.textColor = palette.textSecondary
        modifiedBadgeLabel.textColor = palette.accent
        modifiedBadge.layer?.backgroundColor = palette.cardFillSelected.cgColor
        modifiedBadge.layer?.cornerRadius = 6
        recorder.applyPalette(palette)
        if feedbackKind == .success { feedbackLabel.textColor = .systemGreen }
        if feedbackKind == .error { feedbackLabel.textColor = .systemRed }
    }

    func update(bindings: [ShortcutGesture], customized: Bool) {
        recorder.updateDisplay(bindings)
        modifiedBadge.isHidden = !customized
        resetButton.isHidden = !customized
    }

    func showIssue(
        _ message: String,
        conflictingAction: ShortcutActionID? = nil,
        requestedGesture: ShortcutGesture? = nil
    ) {
        feedbackKind = .error
        pendingSwap = if let conflictingAction, let requestedGesture {
            (conflictingAction, requestedGesture)
        } else {
            nil
        }
        feedbackIcon.image = NSImage(
            systemSymbolName: "exclamationmark.circle.fill",
            accessibilityDescription: L10n.tr("错误")
        )
        feedbackIcon.contentTintColor = .systemRed
        feedbackLabel.textColor = .systemRed
        feedbackLabel.stringValue = message
        swapButton.title = conflictingAction.map { L10n.format("与“{0}”交换", [$0.displayName]) } ?? ""
        swapButton.isHidden = pendingSwap == nil
        feedbackHeightConstraint.constant = 32
        feedbackContainer.isHidden = false
        setAccessibilityHelp(message)
    }

    func showSaved(_ message: String) {
        feedbackKind = .success
        pendingSwap = nil
        feedbackIcon.image = NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: L10n.tr("已保存")
        )
        feedbackIcon.contentTintColor = .systemGreen
        feedbackLabel.textColor = .systemGreen
        feedbackLabel.stringValue = message
        swapButton.isHidden = true
        feedbackHeightConstraint.constant = 32
        feedbackContainer.isHidden = false
        setAccessibilityHelp(message)
    }

    func clearFeedback() {
        feedbackKind = nil
        pendingSwap = nil
        feedbackHeightConstraint.constant = 0
        feedbackContainer.isHidden = true
        setAccessibilityHelp(nil)
    }

    @objc private func resetAction() {
        onReset?(shortcutAction)
    }

    @objc private func swapAction() {
        guard let pendingSwap else { return }
        onSwap?(shortcutAction, pendingSwap.0, pendingSwap.1)
    }
}

private final class ShortcutCardView: NSView {
    private let stack = NSStackView()
    private var palette = AppVisualTheme.palette(isDark: true)
    private let featured: Bool

    init(items: [NSView], featured: Bool = false) {
        self.featured = featured
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        addSubview(stack)

        for (index, item) in items.enumerated() {
            stack.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            if index < items.count - 1 {
                let separator = NSBox()
                separator.boxType = .separator
                separator.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -36).isActive = true
                separator.centerXAnchor.constraint(equalTo: stack.centerXAnchor).isActive = true
            }
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyPalette(_ palette: Palette) {
        self.palette = palette
        needsDisplay = true
    }

    override func updateLayer() {
        layer?.cornerRadius = AppVisualTheme.cardRadius
        layer?.backgroundColor = (featured ? palette.cardFillSelected : palette.cardFill).cgColor
        layer?.borderColor = (featured
            ? palette.accent.withAlphaComponent(0.32)
            : palette.cardBorder).cgColor
        layer?.borderWidth = featured ? 1 : 0.75
    }
}

private final class SettingsBackdropView: NSVisualEffectView {
    private var palette = AppVisualTheme.palette(isDark: true)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .sidebar
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func applyPalette(_ palette: Palette) {
        self.palette = palette
        needsDisplay = true
    }

    override func updateLayer() {
        layer?.backgroundColor = palette.panelTint.withAlphaComponent(0.42).cgColor
    }
}

final class ShortcutSettingsWindowController: NSWindowController, NSWindowDelegate {
    var onAttemptChange: ((ShortcutActionID, ShortcutGesture) -> String?)?
    var onAttemptReset: (() -> String?)?
    var onAttemptResetAction: ((ShortcutActionID) -> String?)?
    var onAttemptSwap: ((ShortcutActionID, ShortcutActionID, ShortcutGesture) -> String?)?
    var onRecordingStateChanged: ((Bool) -> String?)?

    private let shortcutStore: ShortcutStore
    private let preferredSize = NSSize(width: 700, height: 760)
    private var rows: [ShortcutActionID: ShortcutRowView] = [:]
    private var cards: [ShortcutCardView] = []
    private let backdrop = SettingsBackdropView()
    private let footerCountLabel = NSTextField(labelWithString: "")
    private let resetAllButton = NSButton(title: L10n.tr("恢复全部默认"), target: nil, action: nil)
    private let advancedButton = NSButton()
    private var advancedCard: ShortcutCardView!
    private var palette = AppVisualTheme.palette(isDark: true)
    private var shortcutObserver: NSObjectProtocol?
    private var recordingMonitor: Any?
    private weak var activeRecorder: ShortcutRecorderControl?

    init(shortcutStore: ShortcutStore) {
        self.shortcutStore = shortcutStore
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: preferredSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.title = L10n.tr("快捷键设置")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 640, height: 620)
        window.setContentSize(preferredSize)
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        window.contentView = makeContentView()
        applyAppearance()

        shortcutObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.didChangeNotification,
            object: shortcutStore,
            queue: .main
        ) { [weak self] _ in
            self?.reloadValues()
        }
        reloadValues()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        removeRecordingMonitor()
        if let shortcutObserver { NotificationCenter.default.removeObserver(shortcutObserver) }
    }

    func show() {
        guard let window else { return }
        cancelAllRecorders(except: nil)
        applyAppearance()
        reloadValues()
        if !window.isVisible { center(window: window, on: screenUnderMouse()) }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.recalculateKeyViewLoop()
        #if DEBUG
        // 开发用：滚动一段距离，验证内容不会进入红绿灯按钮区域。
        if CommandLine.arguments.contains("--demo-settings-scrolled") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak window] in
                guard let scrollView = window?.contentView?.subviews
                    .first(where: { $0 is NSScrollView }) as? NSScrollView else { return }
                scrollView.documentView?.scroll(NSPoint(x: 0, y: 300))
            }
        }
        #endif
    }

    func applyAppearanceMode() {
        applyAppearance()
    }

    func prepareForLanguageChange() {
        cancelAllRecorders(except: nil)
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        cancelAllRecorders(except: nil)
        NSApp.hide(nil)
    }

    private func makeContentView() -> NSView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)

        let documentView = FlippedShortcutSettingsView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let contentStack = NSStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        documentView.addSubview(contentStack)

        let hero = makeHero()
        contentStack.addArrangedSubview(hero)
        hero.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        contentStack.setCustomSpacing(22, after: hero)

        let globalRow = makeRow(for: .toggleHistory)
        addSection(
            title: L10n.tr("全局唤起"),
            subtitle: L10n.tr("无论当前在哪个应用，都能快速找到剪贴板内容。"),
            card: makeCard(items: [globalRow], featured: true),
            to: contentStack
        )

        let navigationCard = makeCard(items: [
            makeRow(for: .selectPrevious),
            makeRow(for: .selectNext),
            makeRow(for: .toggleSearchFocus)
        ])
        addSection(
            title: L10n.tr("浏览与定位"),
            subtitle: L10n.tr("在卡片之间移动选择，或在卡片和搜索框之间切换。"),
            card: navigationCard,
            to: contentStack
        )

        addSection(
            title: L10n.tr("常用操作"),
            subtitle: L10n.tr("粘贴、预览、收藏和退出是使用频率最高的窗口内动作。"),
            card: makeCard(items: [
                makeRow(for: .pasteSelection),
                makeRow(for: .toggleQuickLook),
                makeRow(for: .addToPinboard),
                makeRow(for: .clearSearchOrClose)
            ]),
            to: contentStack
        )

        configureAdvancedButton()
        contentStack.addArrangedSubview(advancedButton)
        advancedButton.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        advancedCard = makeCard(items: [
            makeRow(for: .togglePin),
            makeRow(for: .deleteSelection),
            makeRow(for: .filterAll),
            makeRow(for: .filterText),
            makeRow(for: .filterImage),
            makeRow(for: .filterFiles)
        ])
        advancedCard.isHidden = true
        contentStack.addArrangedSubview(advancedCard)
        advancedCard.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true

        let footer = makeFooter()
        backdrop.addSubview(scrollView)
        backdrop.addSubview(footer)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            // fullSizeContentView 下 contentInsets 只影响静止位置，滚动时内容
            // 仍会压到红绿灯按钮；钉在 safeArea（不含标题栏）之下才能根除。
            scrollView.topAnchor.constraint(equalTo: backdrop.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: backdrop.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 66),

            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 34),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -34),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 26),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24)
        ])
        return backdrop
    }

    private func makeHero() -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: "keyboard.badge.ellipsis",
            accessibilityDescription: L10n.tr("快捷键")
        )
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 12

        let title = NSTextField(labelWithString: L10n.tr("让每一次操作都更顺手"))
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        let subtitle = NSTextField(wrappingLabelWithString: L10n.tr("点击任意键帽开始录制。设置会立即保存，并同步到菜单提示与窗口操作。"))
        subtitle.font = .systemFont(ofSize: 12.5)
        subtitle.maximumNumberOfLines = 2
        let copy = NSStackView(views: [title, subtitle])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 5

        let hero = NSStackView(views: [icon, copy])
        hero.orientation = .horizontal
        hero.alignment = .centerY
        hero.spacing = 14
        hero.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 48),
            icon.heightAnchor.constraint(equalToConstant: 48)
        ])
        icon.identifier = NSUserInterfaceItemIdentifier("shortcutHeroIcon")
        title.identifier = NSUserInterfaceItemIdentifier("shortcutHeroTitle")
        subtitle.identifier = NSUserInterfaceItemIdentifier("shortcutHeroSubtitle")
        return hero
    }

    private func makeRow(for action: ShortcutActionID) -> ShortcutRowView {
        let row = ShortcutRowView(action: action)
        row.recorder.onRecordingChanged = { [weak self, weak recorder = row.recorder] recording in
            guard let self, let recorder else { return }
            if recording {
                self.cancelAllRecorders(except: recorder)
                self.activeRecorder = recorder
                self.installRecordingMonitor(for: recorder)
                self.rows[action]?.clearFeedback()
                if let error = self.onRecordingStateChanged?(true) {
                    self.rows[action]?.showIssue(error)
                }
            } else if self.activeRecorder === recorder {
                self.activeRecorder = nil
                self.removeRecordingMonitor()
                if let error = self.onRecordingStateChanged?(false) {
                    self.rows[action]?.showIssue(error)
                }
            }
        }
        row.recorder.onRecord = { [weak self] action, gesture in
            self?.attemptChange(action: action, gesture: gesture)
        }
        row.onReset = { [weak self] action in self?.reset(action: action) }
        row.onSwap = { [weak self] action, conflictingAction, gesture in
            self?.swap(action: action, with: conflictingAction, gesture: gesture)
        }
        rows[action] = row
        return row
    }

    private func makeCard(items: [NSView], featured: Bool = false) -> ShortcutCardView {
        let card = ShortcutCardView(items: items, featured: featured)
        cards.append(card)
        return card
    }

    private func addSection(
        title: String,
        subtitle: String,
        card: ShortcutCardView,
        to stack: NSStackView
    ) {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11.5)
        let heading = NSStackView(views: [titleLabel, subtitleLabel])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 3
        heading.identifier = NSUserInterfaceItemIdentifier("shortcutSectionHeading")
        stack.addArrangedSubview(heading)
        stack.setCustomSpacing(7, after: heading)
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(19, after: card)
    }

    private func configureAdvancedButton() {
        advancedButton.title = L10n.tr("更多快捷键")
        advancedButton.image = NSImage(
            systemSymbolName: "chevron.right",
            accessibilityDescription: nil
        )
        advancedButton.imagePosition = .imageLeading
        advancedButton.alignment = .left
        advancedButton.bezelStyle = .inline
        advancedButton.isBordered = false
        advancedButton.font = .systemFont(ofSize: 12.5, weight: .semibold)
        advancedButton.target = self
        advancedButton.action = #selector(toggleAdvanced)
        advancedButton.setAccessibilityHelp(L10n.tr("显示置顶、删除和内容筛选快捷键"))
    }

    private func makeFooter() -> NSView {
        let footer = NSVisualEffectView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.material = .sidebar
        footer.blendingMode = .withinWindow
        footer.state = .active
        footer.wantsLayer = true
        footer.layer?.borderWidth = 0

        let separator = NSBox()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        footer.addSubview(separator)

        footerCountLabel.translatesAutoresizingMaskIntoConstraints = false
        footerCountLabel.font = .systemFont(ofSize: 12, weight: .medium)
        footer.addSubview(footerCountLabel)

        resetAllButton.translatesAutoresizingMaskIntoConstraints = false
        resetAllButton.bezelStyle = .rounded
        resetAllButton.controlSize = .regular
        resetAllButton.target = self
        resetAllButton.action = #selector(resetToDefaults)
        footer.addSubview(resetAllButton)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            separator.topAnchor.constraint(equalTo: footer.topAnchor),
            footerCountLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 34),
            footerCountLabel.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            resetAllButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -34),
            resetAllButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])
        return footer
    }

    private func attemptChange(action: ShortcutActionID, gesture: ShortcutGesture) -> String? {
        guard let row = rows[action] else { return L10n.tr("无法找到这个快捷键项目。") }
        row.clearFeedback()
        if let issue = shortcutStore.validate(gesture, for: action) {
            if case .conflictsWith(let conflictingAction) = issue {
                row.showIssue(
                    issue.message,
                    conflictingAction: conflictingAction,
                    requestedGesture: gesture
                )
            } else {
                row.showIssue(issue.message)
            }
            return issue.message
        }
        if let error = onAttemptChange?(action, gesture) {
            row.showIssue(error)
            return error
        }
        row.showSaved(L10n.format("已保存为 {0}", [gesture.displayString]))
        return nil
    }

    private func reset(action: ShortcutActionID) {
        cancelAllRecorders(except: nil)
        guard let row = rows[action] else { return }
        row.clearFeedback()
        if let error = onAttemptResetAction?(action) {
            row.showIssue(error)
            return
        }
        row.showSaved(L10n.format("已恢复为 {0}", [shortcutStore.defaultDisplayString(for: action)]))
    }

    private func swap(
        action: ShortcutActionID,
        with conflictingAction: ShortcutActionID,
        gesture: ShortcutGesture
    ) {
        guard let row = rows[action] else { return }
        if let error = onAttemptSwap?(action, conflictingAction, gesture) {
            row.showIssue(error)
            return
        }
        row.showSaved(L10n.format("已与“{0}”交换", [conflictingAction.displayName]))
        rows[conflictingAction]?.clearFeedback()
    }

    @objc private func toggleAdvanced() {
        setAdvancedExpanded(advancedCard.isHidden)
    }

    private func setAdvancedExpanded(_ expanded: Bool) {
        advancedCard.isHidden = !expanded
        advancedButton.title = expanded ? L10n.tr("收起更多快捷键") : L10n.tr("更多快捷键")
        advancedButton.image = NSImage(
            systemSymbolName: expanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
        advancedButton.setAccessibilityValue(expanded ? L10n.tr("已展开") : L10n.tr("已收起"))
    }

    @objc private func resetToDefaults() {
        cancelAllRecorders(except: nil)
        let alert = NSAlert()
        alert.messageText = L10n.tr("恢复所有默认快捷键？")
        alert.informativeText = L10n.format("{0} 项快捷键会恢复为安装时的设置。", [ShortcutActionID.allCases.count])
        alert.addButton(withTitle: L10n.tr("恢复全部默认"))
        alert.addButton(withTitle: L10n.tr("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if let error = onAttemptReset?() {
            showWindowError(error)
            return
        }
        rows.values.forEach { $0.clearFeedback() }
    }

    private func showWindowError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("无法更改快捷键")
        alert.informativeText = message
        alert.addButton(withTitle: L10n.tr("好"))
        if let window { alert.beginSheetModal(for: window) }
    }

    private func reloadValues() {
        for (action, row) in rows {
            row.update(
                bindings: shortcutStore.bindings(for: action),
                customized: shortcutStore.isCustomized(action)
            )
        }
        let count = shortcutStore.customizationCount
        footerCountLabel.stringValue = count == 0 ? L10n.tr("正在使用默认设置") : L10n.format("已修改 {0} 项快捷键", [count])
        resetAllButton.isEnabled = count > 0
        let advancedActions: Set<ShortcutActionID> = [
            .togglePin, .deleteSelection, .filterAll, .filterText, .filterImage, .filterFiles
        ]
        if !advancedActions.isDisjoint(with: Set(ShortcutActionID.allCases.filter {
            shortcutStore.isCustomized($0)
        })) {
            setAdvancedExpanded(true)
        }
    }

    private func cancelAllRecorders(except activeRecorder: ShortcutRecorderControl?) {
        for row in rows.values where row.recorder !== activeRecorder {
            row.recorder.cancelRecording()
        }
    }

    private func installRecordingMonitor(for recorder: ShortcutRecorderControl) {
        removeRecordingMonitor()
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self, weak recorder] event in
            guard let self,
                  let recorder,
                  self.window?.isVisible == true,
                  self.activeRecorder === recorder,
                  recorder.isRecordingShortcut else {
                return event
            }
            recorder.capture(event)
            return nil
        }
    }

    private func removeRecordingMonitor() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
            self.recordingMonitor = nil
        }
    }

    private func applyAppearance() {
        let isDark = AppearanceMode.current.isDark
        palette = AppVisualTheme.palette(isDark: isDark)
        window?.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        backdrop.applyPalette(palette)
        cards.forEach { $0.applyPalette(palette) }
        rows.values.forEach { $0.applyPalette(palette) }
        footerCountLabel.textColor = palette.textSecondary
        resetAllButton.contentTintColor = palette.textSecondary
        advancedButton.contentTintColor = palette.textSecondary

        if let heroIcon = findView(identifier: "shortcutHeroIcon") as? NSImageView {
            heroIcon.contentTintColor = palette.accent
            heroIcon.layer?.backgroundColor = palette.cardFillSelected.cgColor
        }
        (findView(identifier: "shortcutHeroTitle") as? NSTextField)?.textColor = palette.textPrimary
        (findView(identifier: "shortcutHeroSubtitle") as? NSTextField)?.textColor = palette.textSecondary
        findViews(identifier: "shortcutSectionHeading").forEach { heading in
            guard let stack = heading as? NSStackView else { return }
            (stack.arrangedSubviews.first as? NSTextField)?.textColor = palette.textPrimary
            (stack.arrangedSubviews.last as? NSTextField)?.textColor = palette.textSecondary
        }
    }

    private func findView(identifier: String) -> NSView? {
        findViews(identifier: identifier).first
    }

    private func findViews(identifier: String) -> [NSView] {
        guard let root = window?.contentView else { return [] }
        var matches: [NSView] = []
        func visit(_ view: NSView) {
            if view.identifier?.rawValue == identifier { matches.append(view) }
            view.subviews.forEach(visit)
        }
        visit(root)
        return matches
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func center(window: NSWindow, on screen: NSScreen?) {
        guard let screen else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: max(visible.minX, min(visible.midX - size.width / 2, visible.maxX - size.width)),
            y: max(visible.minY, min(visible.midY - size.height / 2, visible.maxY - size.height))
        ))
    }
}

private final class FlippedShortcutSettingsView: NSView {
    override var isFlipped: Bool { true }
}
