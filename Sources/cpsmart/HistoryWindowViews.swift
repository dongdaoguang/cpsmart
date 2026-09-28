import AppKit
import Quartz

// MARK: - Theme（尺寸与动效 token）

enum HistoryWindowTheme {
    // 面板
    static let panelHeight: CGFloat = 248
    static let panelRadius = AppVisualTheme.panelRadius

    // 卡片
    static let cardSize = NSSize(width: 204, height: 150)
    static let cardRadius = AppVisualTheme.cardRadius
    static let thumbRadius: CGFloat = 8

    // 动效
    static let selectionDuration: TimeInterval = 0.14
    static let entranceDuration: TimeInterval = 0.18
    static let exitDuration: TimeInterval = 0.12

}

// MARK: - 图片元信息（轻量读取，不解码像素；缩略图本体见 ThumbnailProvider.swift）

enum ImageMetadata {
    /// 只读图片尺寸，不解码像素，可在主线程调用。
    static func pixelSize(of data: Data) -> NSSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }
        return NSSize(width: width, height: height)
    }
}

// MARK: - 基础控件

final class FloatingHistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class KeyboardCollectionView: NSCollectionView {
    var onBackgroundClick: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard indexPathForItem(at: point) != nil else {
            onBackgroundClick?()
            return
        }
        super.mouseDown(with: event)
    }
}

final class PinboardTabButton: NSButton {
    var onAcceptHistoryEntry: ((UUID) -> Void)? {
        didSet {
            if onAcceptHistoryEntry != nil {
                registerForDraggedTypes([PinboardDragDescriptor.pasteboardType])
            }
        }
    }

    var dropHighlightColor: NSColor = .controlAccentColor

    private var palette = AppVisualTheme.palette(isDark: true)
    private var isSelectedTab = false
    private var tintColor: NSColor?
    private var isHovered = false
    private var isDropHighlighted = false
    private var hoverTrackingArea: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 18
        size.height = 24
        return size
    }

    /// 无边框按钮默认把内容贴左绘制；背景、边框、内容全部在 draw 里手动居中绘制，
    /// 避免依赖 updateLayer 的调用时机。
    override func draw(_ dirtyRect: NSRect) {
        let fill: NSColor
        if isSelectedTab {
            fill = (tintColor ?? palette.accent).withAlphaComponent(0.18)
        } else if isHovered {
            fill = palette.cardFillHover
        } else {
            fill = palette.cardFill
        }
        let pill = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        fill.setFill()
        pill.fill()
        if isDropHighlighted {
            dropHighlightColor.setStroke()
            pill.lineWidth = 2
            pill.stroke()
        }

        guard let cell else { return }
        let contentSize = cell.cellSize
        guard contentSize.width > 0, contentSize.height > 0,
              contentSize.width < bounds.width else {
            super.draw(dirtyRect)
            return
        }
        let centered = NSRect(
            x: (bounds.width - contentSize.width) / 2,
            y: (bounds.height - contentSize.height) / 2,
            width: contentSize.width,
            height: contentSize.height
        )
        cell.draw(withFrame: centered, in: self)
    }

    /// 扁平药丸样式：未选中只有浅底，选中用收藏板颜色淡填，不再使用系统边框。
    func applyStyle(palette: Palette, selected: Bool, tint: NSColor?) {
        self.palette = palette
        isSelectedTab = selected
        tintColor = tint
        isBordered = false
        wantsLayer = true
        let weight: NSFont.Weight = selected ? .semibold : .medium
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: weight),
                .foregroundColor: selected ? palette.textPrimary : palette.textSecondary
            ]
        )
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let descriptor = PinboardDragDescriptor.read(from: sender.draggingPasteboard),
              descriptor.sourcePinboardID == nil,
              onAcceptHistoryEntry != nil else { return [] }
        setDropHighlighted(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let descriptor = PinboardDragDescriptor.read(from: sender.draggingPasteboard),
              descriptor.sourcePinboardID == nil,
              onAcceptHistoryEntry != nil else { return [] }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropHighlighted(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        PinboardDragDescriptor.read(from: sender.draggingPasteboard)?.sourcePinboardID == nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { setDropHighlighted(false) }
        guard let descriptor = PinboardDragDescriptor.read(from: sender.draggingPasteboard),
              descriptor.sourcePinboardID == nil,
              let onAcceptHistoryEntry else { return false }
        onAcceptHistoryEntry(descriptor.entryID)
        return true
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        // 拖拽被 Esc 取消时不会触发 draggingExited，需要兜底清理高亮。
        setDropHighlighted(false)
    }

    private func setDropHighlighted(_ isHighlighted: Bool) {
        isDropHighlighted = isHighlighted
        needsDisplay = true
    }
}

/// 新建收藏板用的色点行选择器：直接点选颜色，选中项带描边圈。
final class PinboardColorPickerView: NSView {
    private(set) var selectedIndex: Int = 0 {
        didSet { updateSelection() }
    }

    private var buttons: [NSButton] = []

    init(colors: [NSColor], names: [String]) {
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 10
        for (index, color) in colors.enumerated() {
            let button = NSButton(
                image: Self.dotImage(color, diameter: 16),
                target: self,
                action: #selector(choose(_:))
            )
            button.tag = index
            button.isBordered = false
            button.wantsLayer = true
            button.toolTip = index < names.count ? names[index] : nil
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 22),
                button.heightAnchor.constraint(equalToConstant: 22)
            ])
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 22)
        ])
        updateSelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func select(index: Int) {
        guard buttons.indices.contains(index) else { return }
        selectedIndex = index
    }

    private func updateSelection() {
        for (index, button) in buttons.enumerated() {
            let selected = index == selectedIndex
            button.layer?.cornerRadius = 11
            button.layer?.borderWidth = selected ? 2 : 0
            button.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.55).cgColor
        }
    }

    @objc private func choose(_ sender: NSButton) {
        selectedIndex = sender.tag
    }

    private static func dotImage(_ color: NSColor, diameter: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: diameter - 2, height: diameter - 2)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

private final class ClickableCardView: NSView {
    var onClick: ((Int, NSEvent.ModifierFlags) -> Void)?
    var onDrag: ((NSEvent, NSView) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?
    private var didBeginDrag = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        onHoverChanged?(false)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// AppKit 传给 hitTest 的点属于父视图坐标系，必须先转换成卡片本地坐标。
    /// 直接与 bounds 比较会让横向滚动后的卡片命中区域整体错位。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let localPoint = convert(point, from: superview)
        return bounds.contains(localPoint) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        didBeginDrag = false
        window?.makeKey()
        onClick?(event.clickCount, event.modifierFlags)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didBeginDrag else { return }
        didBeginDrag = true
        onDrag?(event, self)
    }

    override func mouseUp(with event: NSEvent) {
        didBeginDrag = false
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?(1, [])
        return true
    }
}

// MARK: - 卡片

final class HistoryCollectionItem: NSCollectionViewItem {
    var onClick: ((Int, NSEvent.ModifierFlags) -> Void)? {
        didSet { cardView.onClick = onClick }
    }

    var onDrag: ((NSEvent, NSView) -> Void)? {
        didSet { cardView.onDrag = onDrag }
    }

    private let cardView = ClickableCardView()
    private let thumbView = NSView()
    private let dimPill = NSView()
    private let dimLabel = NSTextField(labelWithString: "")
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let sourceIconView = NSImageView()
    private let metaTypeLabel = NSTextField(labelWithString: "")
    private let metaRightLabel = NSTextField(labelWithString: "")
    private let pinImageView = NSImageView()

    private var textConstraints: [NSLayoutConstraint] = []
    private var imageConstraints: [NSLayoutConstraint] = []
    private var fileConstraints: [NSLayoutConstraint] = []
    private var metaLeadingDirect: NSLayoutConstraint!
    private var metaLeadingAfterIcon: NSLayoutConstraint!
    private var representedEntryID: UUID?
    private var palette = AppVisualTheme.palette(isDark: true)

    private var isHovered = false {
        didSet { updateAppearance() }
    }

    override var isSelected: Bool {
        didSet { updateAppearance() }
    }

    override func loadView() {
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = HistoryWindowTheme.cardRadius
        cardView.layer?.borderWidth = 1
        cardView.layer?.masksToBounds = false
        cardView.layer?.shadowColor = NSColor.black.cgColor
        cardView.setAccessibilityRole(.button)
        view = cardView

        thumbView.translatesAutoresizingMaskIntoConstraints = false
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = HistoryWindowTheme.thumbRadius
        thumbView.layer?.masksToBounds = true
        thumbView.layer?.contentsGravity = .resizeAspectFill

        dimPill.translatesAutoresizingMaskIntoConstraints = false
        dimPill.wantsLayer = true
        dimPill.layer?.cornerRadius = 6
        dimPill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor

        dimLabel.translatesAutoresizingMaskIntoConstraints = false
        dimLabel.font = .systemFont(ofSize: 9, weight: .medium)
        dimLabel.textColor = NSColor.white.withAlphaComponent(0.92)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.wantsLayer = true
        titleLabel.layer?.masksToBounds = true
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 6

        metaTypeLabel.translatesAutoresizingMaskIntoConstraints = false
        metaTypeLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        metaTypeLabel.lineBreakMode = .byTruncatingTail

        metaRightLabel.translatesAutoresizingMaskIntoConstraints = false
        metaRightLabel.font = .systemFont(ofSize: 10, weight: .medium)
        metaRightLabel.alignment = .right

        sourceIconView.translatesAutoresizingMaskIntoConstraints = false
        sourceIconView.imageScaling = .scaleProportionallyUpOrDown
        sourceIconView.isHidden = true

        pinImageView.translatesAutoresizingMaskIntoConstraints = false
        pinImageView.image = NSImage(
            systemSymbolName: "pin.fill",
            accessibilityDescription: L10n.tr("已置顶")
        )
        pinImageView.imageScaling = .scaleProportionallyUpOrDown
        pinImageView.isHidden = true

        dimPill.addSubview(dimLabel)
        thumbView.addSubview(dimPill)
        cardView.addSubview(thumbView)
        cardView.addSubview(iconView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(sourceIconView)
        cardView.addSubview(metaTypeLabel)
        cardView.addSubview(metaRightLabel)
        cardView.addSubview(pinImageView)

        metaLeadingDirect = metaTypeLabel.leadingAnchor.constraint(
            equalTo: cardView.leadingAnchor, constant: 12
        )
        metaLeadingAfterIcon = metaTypeLabel.leadingAnchor.constraint(
            equalTo: sourceIconView.trailingAnchor, constant: 5
        )

        // 底部元信息行（所有类型共用）：来源应用图标 + 类型 · 详情，右侧相对时间
        NSLayoutConstraint.activate([
            metaLeadingDirect,

            sourceIconView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            sourceIconView.centerYAnchor.constraint(equalTo: metaTypeLabel.centerYAnchor),
            sourceIconView.widthAnchor.constraint(equalToConstant: 11),
            sourceIconView.heightAnchor.constraint(equalToConstant: 11),

            metaTypeLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -9),

            metaRightLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            metaRightLabel.centerYAnchor.constraint(equalTo: metaTypeLabel.centerYAnchor),
            metaRightLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: metaTypeLabel.trailingAnchor, constant: 8
            ),

            dimLabel.leadingAnchor.constraint(equalTo: dimPill.leadingAnchor, constant: 6),
            dimLabel.trailingAnchor.constraint(equalTo: dimPill.trailingAnchor, constant: -6),
            dimLabel.topAnchor.constraint(equalTo: dimPill.topAnchor, constant: 2),
            dimLabel.bottomAnchor.constraint(equalTo: dimPill.bottomAnchor, constant: -2),

            dimPill.trailingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: -6),
            dimPill.bottomAnchor.constraint(equalTo: thumbView.bottomAnchor, constant: -6),

            // 置顶标记固定在卡片右上角
            pinImageView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            pinImageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -9),
            pinImageView.widthAnchor.constraint(equalToConstant: 10),
            pinImageView.heightAnchor.constraint(equalToConstant: 10)
        ])

        // 文本卡：多行预览占据内容区
        textConstraints = [
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -12),
            titleLabel.widthAnchor.constraint(
                lessThanOrEqualToConstant: HistoryWindowTheme.cardSize.width - 24
            ),
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 11),
            titleLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: metaTypeLabel.topAnchor, constant: -6
            )
        ]

        // 图片卡：缩略图铺满内容区
        imageConstraints = [
            thumbView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
            thumbView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            thumbView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 8),
            thumbView.bottomAnchor.constraint(equalTo: metaTypeLabel.topAnchor, constant: -6)
        ]

        // 文件卡：大图标居中 + 文件名
        fileConstraints = [
            iconView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            iconView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 38),
            iconView.heightAnchor.constraint(equalToConstant: 38),

            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: metaTypeLabel.topAnchor, constant: -4
            )
        ]

        cardView.onHoverChanged = { [weak self] hovered in
            self?.isHovered = hovered
        }

        updateAppearance()
    }

    func configure(with entry: ClipboardEntry, thumbnails: ThumbnailProvider, palette: Palette) {
        self.palette = palette
        representedEntryID = entry.id
        NSLayoutConstraint.deactivate(textConstraints + imageConstraints + fileConstraints)
        thumbView.layer?.contents = nil
        thumbView.layer?.backgroundColor = palette.thumbPlaceholder.cgColor
        thumbView.isHidden = true
        dimPill.isHidden = true
        iconView.isHidden = true
        titleLabel.isHidden = true
        titleLabel.textColor = palette.textPrimary
        metaRightLabel.textColor = palette.textTertiary

        metaRightLabel.stringValue = Self.relativeDate.string(for: entry.recencyDate) ?? L10n.tr("刚刚")
        pinImageView.isHidden = entry.isPinned != true
        pinImageView.contentTintColor = palette.accent
        configureSourceApp(entry)

        switch entry.payload {
        case .text(let text):
            titleLabel.isHidden = false
            titleLabel.alignment = .left
            titleLabel.font = .systemFont(ofSize: 12)
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.maximumNumberOfLines = 6
            titleLabel.stringValue = Self.preview(text)
            metaTypeLabel.stringValue = L10n.format("文本 · {0} 字符", [text.count])
            metaTypeLabel.textColor = palette.typeText
            NSLayoutConstraint.activate(textConstraints)

        case .image(let data, _):
            thumbView.isHidden = false
            metaTypeLabel.stringValue = L10n.format("图片 · {0}", [Self.byteCount.string(fromByteCount: Int64(data.count))])
            metaTypeLabel.textColor = palette.typeImage
            if let size = ImageMetadata.pixelSize(of: data) {
                dimLabel.stringValue = "\(Int(size.width)) × \(Int(size.height))"
                dimPill.isHidden = false
            }
            NSLayoutConstraint.activate(imageConstraints)
            let entryID = entry.id
            thumbnails.thumbnail(for: entry) { [weak self] image in
                guard let self, self.representedEntryID == entryID, let image else { return }
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.15
                self.thumbView.layer?.add(fade, forKey: "thumbnailFade")
                self.thumbView.layer?.contents = image
            }

        case .files(let paths):
            iconView.isHidden = false
            titleLabel.isHidden = false
            iconView.image = NSWorkspace.shared.icon(forFile: paths.first ?? "")
            titleLabel.alignment = .center
            titleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
            titleLabel.lineBreakMode = .byTruncatingMiddle
            titleLabel.maximumNumberOfLines = 2
            if paths.count == 1 {
                titleLabel.stringValue = URL(fileURLWithPath: paths[0]).lastPathComponent
                metaTypeLabel.stringValue = L10n.tr("文件")
            } else {
                titleLabel.stringValue = paths
                    .map { URL(fileURLWithPath: $0).lastPathComponent }
                    .joined(separator: L10n.tr("fileList.separator"))
                metaTypeLabel.stringValue = L10n.format("{0} 个文件", [paths.count])
            }
            metaTypeLabel.textColor = palette.typeFile
            NSLayoutConstraint.activate(fileConstraints)
        }

        cardView.setAccessibilityLabel(titleLabel.stringValue)
    }

    /// 元信息行左侧展示来源应用图标；旧记录没有来源信息时不占位。
    private func configureSourceApp(_ entry: ClipboardEntry) {
        guard let bundleID = entry.sourceAppBundleID,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            sourceIconView.isHidden = true
            sourceIconView.image = nil
            metaLeadingAfterIcon.isActive = false
            metaLeadingDirect.isActive = true
            return
        }
        sourceIconView.image = NSWorkspace.shared.icon(forFile: appURL.path)
        sourceIconView.toolTip = entry.sourceAppName.map { L10n.format("来自 {0}", [$0]) }
        sourceIconView.isHidden = false
        metaLeadingDirect.isActive = false
        metaLeadingAfterIcon.isActive = true
    }

    private func updateAppearance() {
        guard isViewLoaded, let layer = cardView.layer else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(HistoryWindowTheme.selectionDuration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        if isSelected {
            layer.borderWidth = 1.5
            layer.borderColor = palette.accent.cgColor
            layer.backgroundColor = palette.cardFillSelected.cgColor
            layer.shadowOpacity = 0.45
            layer.shadowRadius = 12
            layer.shadowOffset = CGSize(width: 0, height: -4)
            layer.transform = CATransform3DMakeScale(1.03, 1.03, 1)
        } else {
            layer.borderWidth = 1
            layer.borderColor = palette.cardBorder.cgColor
            layer.backgroundColor = (isHovered ? palette.cardFillHover : palette.cardFill).cgColor
            layer.shadowOpacity = 0.22
            layer.shadowRadius = 5
            layer.shadowOffset = CGSize(width: 0, height: -2)
            layer.transform = CATransform3DIdentity
        }
        CATransaction.commit()
    }

    private static func preview(_ text: String) -> String {
        let normalized = String(text.prefix(2_000))
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(6)
            .joined(separator: "\n")

        let maximumCharacterCount = 360
        guard normalized.count > maximumCharacterCount else { return normalized }
        return String(normalized.prefix(maximumCharacterCount)) + "…"
    }

    private static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: L10n.languageCode)
        formatter.unitsStyle = .short
        return formatter
    }()

    private static let byteCount: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
