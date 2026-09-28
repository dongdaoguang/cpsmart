import AppKit

final class AboutWindowController: NSWindowController, NSWindowDelegate {
    private let preferredSize = NSSize(width: 680, height: 760)
    private let shortcutStore: ShortcutStore
    private var shortcutObserver: NSObjectProtocol?

    init(shortcutStore: ShortcutStore) {
        self.shortcutStore = shortcutStore
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: preferredSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.title = L10n.tr("关于 cpsmart")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 620, height: 640)
        window.setContentSize(preferredSize)
        window.center()
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentView = makeContentView()
        window.delegate = self
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: ShortcutStore.didChangeNotification,
            object: shortcutStore,
            queue: .main
        ) { [weak self] _ in
            guard let self, let window = self.window, window.isVisible else { return }
            self.rebuildContent(window)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let shortcutObserver {
            NotificationCenter.default.removeObserver(shortcutObserver)
        }
    }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            // 快捷键变更通知只在窗口可见时重建界面；重开时先重建，保证展示的是最新快捷键。
            rebuildContent(window)
            center(window: window, on: screenUnderMouse())
        }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        #if DEBUG
        // 开发用：滚动一段距离，验证内容不会进入红绿灯按钮区域。
        if CommandLine.arguments.contains("--demo-about-scrolled") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak window] in
                guard let scrollView = window?.contentView?.subviews
                    .first(where: { $0 is NSScrollView }) as? NSScrollView else { return }
                scrollView.documentView?.scroll(NSPoint(x: 0, y: 300))  // FlippedView：y 增大向下滚
            }
        }
        #endif
    }

    /// 替换窗口内容并把滚动位置重置回顶部——替换 contentView 后 NSScrollView
    /// 的初始滚动位置会停在错误偏移，导致顶部图标区被滚出视野。
    private func rebuildContent(_ window: NSWindow) {
        window.contentView = makeContentView()
        window.layoutIfNeeded()
        let scrollView = window.contentView?.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView
        scrollView?.contentView.scroll(to: .zero)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.hide(nil)
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
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        ))
    }

    // MARK: - 内容

    private func makeContentView() -> NSView {
        let background = NSVisualEffectView()
        background.material = .sidebar
        background.blendingMode = .behindWindow
        background.state = .active

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        let contentStack = NSStackView()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = 14
        documentView.addSubview(contentStack)

        let cards = [
            makeQuickStartCard(),
            makeKeyboardCard(),
            makePointerCard(),
            makePrivacyCard()
        ]
        contentStack.addArrangedSubview(makeHero())
        contentStack.setCustomSpacing(18, after: contentStack.arrangedSubviews.last!)
        for card in cards {
            contentStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }
        contentStack.addArrangedSubview(makeFooter())
        contentStack.setCustomSpacing(6, after: contentStack.arrangedSubviews[cards.count])

        background.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            // fullSizeContentView 下内容一直延伸到窗口顶；contentInsets 只影响回到
            // 顶部时的静止位置，滚动时内容仍会压到红绿灯按钮。把滚动视图钉在
            // safeArea（不含标题栏）之下，内容物理上不可能进入按钮区域。
            scrollView.topAnchor.constraint(equalTo: background.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 32),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -32),
            // 滚动视图顶部已在 safeArea（标题栏）之下，这里只是内容间距
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 26),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24)
        ])
        return background
    }

    // MARK: Hero

    private func makeHero() -> NSView {
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = loadApplicationIcon()
        icon.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 84),
            icon.heightAnchor.constraint(equalToConstant: 84)
        ])

        let name = label("cpsmart", size: 24, weight: .semibold)

        // 版本徽标：胶囊底 + 次要色文字
        let versionText = label(displayVersion, size: 11, weight: .medium, color: .secondaryLabelColor)
        versionText.translatesAutoresizingMaskIntoConstraints = false
        let versionBadge = NSView()
        versionBadge.translatesAutoresizingMaskIntoConstraints = false
        versionBadge.wantsLayer = true
        versionBadge.layer?.cornerRadius = 9
        versionBadge.layer?.backgroundColor = NSColor.quaternaryLabelColor
            .withAlphaComponent(0.14).cgColor
        versionBadge.addSubview(versionText)
        NSLayoutConstraint.activate([
            versionText.leadingAnchor.constraint(equalTo: versionBadge.leadingAnchor, constant: 9),
            versionText.trailingAnchor.constraint(equalTo: versionBadge.trailingAnchor, constant: -9),
            versionText.topAnchor.constraint(equalTo: versionBadge.topAnchor, constant: 2.5),
            versionText.bottomAnchor.constraint(equalTo: versionBadge.bottomAnchor, constant: -2.5)
        ])

        let tagline = label(L10n.tr("快速找到刚刚复制的内容"), size: 14, weight: .medium)
        let privacy = label(
            L10n.tr("轻量、原生、完全本地。剪贴板历史不会上传。"),
            size: 12,
            color: .secondaryLabelColor
        )

        let hero = NSStackView(views: [icon, name, versionBadge, tagline, privacy])
        hero.orientation = .vertical
        hero.alignment = .centerX
        hero.spacing = 4
        hero.setCustomSpacing(14, after: icon)
        hero.setCustomSpacing(8, after: name)
        hero.setCustomSpacing(14, after: versionBadge)
        hero.setCustomSpacing(5, after: tagline)
        return hero
    }

    // MARK: 卡片

    private func makeQuickStartCard() -> NSView {
        makeCard(
            title: L10n.tr("快速开始"),
            symbol: "sparkles",
            rows: [
                ("", L10n.tr("在任何应用中复制文本、图片或文件。")),
                ("", L10n.format("按 {0} 打开历史浮窗，再按 {1} 进入搜索。", [shortcutStore.displayString(for: .toggleHistory), shortcutStore.displayString(for: .toggleSearchFocus)])),
                ("", L10n.format("选中后按 {0}，或双击卡片，粘贴回原来的应用。", [shortcutStore.displayString(for: .pasteSelection)]))
            ].map { (step: $0.0, detail: $0.1) }
        ) { [weak self] _, detail in
            let line = self?.label(detail, size: 12.5) ?? NSTextField()
            line.maximumNumberOfLines = 0
            line.lineBreakMode = .byWordWrapping
            return line
        }
    }

    private func makeKeyboardCard() -> NSView {
        let rows: [(key: String, detail: String)] = [
            (shortcutStore.displayString(for: .toggleHistory), L10n.tr("打开或关闭剪贴板历史")),
            (shortcutStore.displayString(for: .selectPrevious), L10n.tr("选择上一张卡片")),
            (shortcutStore.displayString(for: .selectNext), L10n.tr("选择下一张卡片")),
            (shortcutStore.displayString(for: .toggleQuickLook), L10n.tr("自适应预览所选内容")),
            (shortcutStore.displayString(for: .toggleSearchFocus), L10n.tr("在卡片与搜索框之间切换")),
            (shortcutStore.displayString(for: .pasteSelection), L10n.tr("粘贴所选内容到原应用")),
            (shortcutStore.displayString(for: .togglePin), L10n.tr("置顶或取消置顶")),
            ("⌘⌥1…9", L10n.tr("直接切换最近或前八个收藏板")),
            ("⌃Tab / ⌃⇧Tab", L10n.tr("向前或向后循环切换收藏板")),
            (shortcutStore.displayString(for: .deleteSelection), L10n.tr("删除所选记录")),
            (shortcutStore.displayString(for: .filterAll), L10n.tr("筛选全部记录")),
            (shortcutStore.displayString(for: .filterText), L10n.tr("筛选文本")),
            (shortcutStore.displayString(for: .filterImage), L10n.tr("筛选图片")),
            (shortcutStore.displayString(for: .filterFiles), L10n.tr("筛选文件")),
            (shortcutStore.displayString(for: .clearSearchOrClose), L10n.tr("先清除搜索，再关闭窗口"))
        ]
        return makeCard(
            title: L10n.tr("键盘快捷键"),
            symbol: "keyboard",
            rows: rows.map { (step: $0.key, detail: $0.detail) },
            twoColumns: true
        ) { [weak self] key, detail in
            self?.makeKeyRow(key: key, detail: detail) ?? NSView()
        }
    }

    private func makePointerCard() -> NSView {
        makeCard(
            title: L10n.tr("鼠标与触控板"),
            symbol: "cursorarrow.click.2",
            rows: [
                (L10n.tr("单击"), L10n.tr("选择卡片并复制内容")),
                (L10n.tr("双击"), L10n.tr("选择卡片并直接粘贴")),
                (L10n.tr("点搜索框"), L10n.tr("进入搜索输入")),
                (L10n.tr("点空白处"), L10n.tr("退出搜索，恢复空格预览"))
            ].map { (step: $0.0, detail: $0.1) },
            note: L10n.tr("主屏幕与副屏幕均支持以上操作；触控板与鼠标的点击行为一致。")
        ) { [weak self] lead, detail in
            self?.makeLeadRow(lead: lead, detail: detail) ?? NSView()
        }
    }

    private func makePrivacyCard() -> NSView {
        makeCard(
            title: L10n.tr("权限、隐私与清理"),
            symbol: "hand.raised.fill",
            rows: [
                (L10n.tr("辅助功能"), L10n.tr("仅在粘贴时用来向原应用发送一次 ⌘V。")),
                (L10n.tr("本地存储"), L10n.tr("历史只保存在这台 Mac，不经过网络。")),
                (L10n.tr("排除应用"), L10n.tr("菜单栏可排除指定应用，不再记录其复制内容。")),
                (L10n.tr("清空历史"), L10n.tr("默认保留置顶记录；按住 ⌥ 打开菜单可全部清空。"))
            ].map { (step: $0.0, detail: $0.1) },
            note: L10n.tr("权限路径：系统设置 → 隐私与安全性 → 辅助功能。")
        ) { [weak self] lead, detail in
            self?.makeLeadRow(lead: lead, detail: detail) ?? NSView()
        }
    }

    // MARK: 行样式

    /// 快捷键行：快捷键加粗文字 + 说明，列宽固定保证多行对齐
    private func makeKeyRow(key: String, detail: String) -> NSView {
        let keyLabel = label(key, size: 12.5, weight: .semibold)
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        keyLabel.alignment = .right
        keyLabel.widthAnchor.constraint(equalToConstant: 82).isActive = true

        let detailLabel = label(detail, size: 12.5, color: .secondaryLabelColor)
        detailLabel.maximumNumberOfLines = 0
        detailLabel.lineBreakMode = .byWordWrapping

        let row = NSStackView(views: [keyLabel, detailLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        return row
    }

    /// 加粗引导词行（步骤与非按键场景）
    private func makeLeadRow(lead: String, detail: String) -> NSView {
        let leadLabel = label(lead, size: 12.5, weight: .semibold)
        leadLabel.translatesAutoresizingMaskIntoConstraints = false
        leadLabel.alignment = .left
        leadLabel.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let detailLabel = label(detail, size: 12.5, color: .secondaryLabelColor)
        detailLabel.maximumNumberOfLines = 0
        detailLabel.lineBreakMode = .byWordWrapping

        let row = NSStackView(views: [leadLabel, detailLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        return row
    }

    // MARK: 卡片容器

    private func makeCard(
        title: String,
        symbol: String,
        rows: [(step: String, detail: String)],
        note: String? = nil,
        twoColumns: Bool = false,
        rowBuilder: (String, String) -> NSView
    ) -> NSView {
        let card = AboutCardView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let symbolView = NSImageView()
        symbolView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        symbolView.contentTintColor = .controlAccentColor
        symbolView.symbolConfiguration = .init(pointSize: 12.5, weight: .semibold)
        NSLayoutConstraint.activate([
            symbolView.widthAnchor.constraint(equalToConstant: 20),
            symbolView.heightAnchor.constraint(equalToConstant: 20)
        ])

        let heading = NSStackView(views: [symbolView, label(title, size: 13.5, weight: .semibold)])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        heading.spacing = 7

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.addArrangedSubview(heading)
        stack.setCustomSpacing(12, after: heading)

        if twoColumns, rows.count > 1 {
            // 双栏网格：长列表折成两列，避免窗口过高
            let midpoint = (rows.count + 1) / 2
            let columns = NSStackView()
            columns.orientation = .horizontal
            columns.alignment = .top
            columns.spacing = 26
            columns.distribution = .fillEqually
            // 奇数行时 prefix 多取一行，suffix 必须取剩余部分，否则会重复中间一行。
            for chunk in [Array(rows.prefix(midpoint)), Array(rows.suffix(rows.count - midpoint))] {
                let column = NSStackView()
                column.orientation = .vertical
                column.alignment = .leading
                column.spacing = 8
                for row in chunk {
                    let rowView = rowBuilder(row.step, row.detail)
                    column.addArrangedSubview(rowView)
                    rowView.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
                }
                columns.addArrangedSubview(column)
            }
            stack.addArrangedSubview(columns)
            columns.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        } else {
            for row in rows {
                let rowView = rowBuilder(row.step, row.detail)
                stack.addArrangedSubview(rowView)
                rowView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }

        if let note {
            let noteLabel = label(note, size: 11.5, color: .secondaryLabelColor)
            noteLabel.maximumNumberOfLines = 0
            noteLabel.lineBreakMode = .byWordWrapping
            stack.setCustomSpacing(11, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(noteLabel)
            noteLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 15),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        return card
    }

    // MARK: 页脚

    private func makeFooter() -> NSView {
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 6

        let signature = label(L10n.tr("cpsmart · 为 macOS 设计 ·"), size: 11, color: .tertiaryLabelColor)
        // NSTextField 的 .link 属性在不可选中的 label 里不会响应点击，
        // 用无边框按钮实现真正的跳转。
        let link = NSButton(
            title: "GitHub",
            target: self,
            action: #selector(openRepository)
        )
        link.isBordered = false
        link.attributedTitle = NSAttributedString(
            string: "GitHub",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .cursor: NSCursor.pointingHand
            ]
        )
        link.toolTip = repositoryURL.absoluteString
        footer.addArrangedSubview(signature)
        footer.addArrangedSubview(link)
        return footer
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/dongdaoguang/cpsmart")!
    }

    @objc private func openRepository() {
        NSWorkspace.shared.open(repositoryURL)
    }

    // MARK: 工具

    private func loadApplicationIcon() -> NSImage? {
        if let url = Bundle.main.url(forResource: "CPSmartAppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApp.applicationIconImage
    }

    private var displayVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let version else { return L10n.tr("开发版") }
        guard let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return L10n.format("版本 {0}", [version])
        }
        return L10n.format("版本 {0}（构建 {1}）", [version, build])
    }

    private func label(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class AboutCardView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        layer?.borderWidth = 0.5
        layer?.cornerRadius = 12
    }
}
