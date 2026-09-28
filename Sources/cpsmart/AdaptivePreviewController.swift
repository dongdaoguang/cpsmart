import AppKit

/// 文本和剪贴板图片的轻量预览。普通文件继续交给系统 Quick Look。
final class AdaptivePreviewController: NSObject {
    private let popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true
        return popover
    }()

    var isVisible: Bool { popover.isShown }

    /// 文本和剪贴板图片支持轻量预览；普通文件始终走系统 Quick Look。
    static func supports(entry: ClipboardEntry) -> Bool {
        switch entry.payload {
        case .text, .image: return true
        case .files: return false
        }
    }

    @discardableResult
    func show(
        entry: ClipboardEntry,
        relativeTo sourceView: NSView,
        palette: Palette,
        onExpand: @escaping () -> Void
    ) -> Bool {
        guard let window = sourceView.window,
              let screen = window.screen else { return false }

        let sourceFrame = window.convertToScreen(sourceView.convert(sourceView.bounds, to: nil))
        let content: (NSViewController, NSSize)

        switch entry.payload {
        case .text(let text):
            let font = Self.preferredFont(for: text)
            let size = AdaptivePreviewSizing.textSize(
                for: text,
                font: font,
                visibleFrame: screen.visibleFrame,
                sourceFrame: sourceFrame
            )
            content = (
                TextPreviewViewController(
                    text: text,
                    font: font,
                    palette: palette,
                    onExpand: onExpand
                ),
                size
            )

        case .image(let data, _):
            guard let image = NSImage(data: data) else { return false }
            let pixelSize = ImageMetadata.pixelSize(of: data) ?? image.size
            let size = AdaptivePreviewSizing.imageSize(
                pixelSize: pixelSize,
                visibleFrame: screen.visibleFrame,
                sourceFrame: sourceFrame
            )
            content = (
                ImagePreviewViewController(
                    image: image,
                    pixelSize: pixelSize,
                    palette: palette,
                    onExpand: onExpand
                ),
                size
            )

        case .files:
            return false
        }

        let (viewController, contentSize) = content
        viewController.preferredContentSize = contentSize
        viewController.view.frame = NSRect(origin: .zero, size: contentSize)
        popover.appearance = window.effectiveAppearance
        popover.contentViewController = viewController
        popover.contentSize = contentSize
        popover.show(
            relativeTo: sourceView.bounds,
            of: sourceView,
            preferredEdge: .maxY
        )
        return true
    }

    func close() {
        popover.close()
    }

    private static func preferredFont(for text: String) -> NSFont {
        let codeSignals = ["{", "}", "func ", "let ", "var ", "=>", "</", "#!/"]
        let looksLikeCode = text.contains("\n") && codeSignals.contains(where: text.contains)
        let looksLikeURL = text.hasPrefix("http://") || text.hasPrefix("https://")
        if looksLikeCode || looksLikeURL {
            return .monospacedSystemFont(ofSize: 13, weight: .regular)
        }
        return .systemFont(ofSize: 13.5)
    }
}

private class PreviewContentViewController: NSViewController {
    let palette: Palette
    private let onExpand: () -> Void

    init(palette: Palette, onExpand: @escaping () -> Void) {
        self.palette = palette
        self.onExpand = onExpand
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func makeRootView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        return root
    }

    func makeHeader(title: String, detail: String) -> NSView {
        let header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = palette.textPrimary

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        detailLabel.textColor = palette.textTertiary
        detailLabel.lineBreakMode = .byTruncatingTail

        let expandButton = NSButton(
            image: NSImage(
                systemSymbolName: "arrow.up.left.and.arrow.down.right",
                accessibilityDescription: L10n.tr("在 Quick Look 中打开")
            ) ?? NSImage(),
            target: self,
            action: #selector(expandPreview)
        )
        expandButton.translatesAutoresizingMaskIntoConstraints = false
        expandButton.bezelStyle = .inline
        expandButton.isBordered = false
        expandButton.contentTintColor = palette.textSecondary
        expandButton.toolTip = L10n.tr("在 Quick Look 中打开")

        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = palette.cardBorder.cgColor

        header.addSubview(titleLabel)
        header.addSubview(detailLabel)
        header.addSubview(expandButton)
        header.addSubview(separator)
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            detailLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            detailLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: expandButton.leadingAnchor,
                constant: -8
            ),

            expandButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            expandButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            expandButton.widthAnchor.constraint(equalToConstant: 24),
            expandButton.heightAnchor.constraint(equalToConstant: 24),

            separator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
        return header
    }

    @objc private func expandPreview() {
        onExpand()
    }
}

private final class TextPreviewViewController: PreviewContentViewController {
    private let text: String
    private let font: NSFont

    init(
        text: String,
        font: NSFont,
        palette: Palette,
        onExpand: @escaping () -> Void
    ) {
        self.text = text
        self.font = font
        super.init(palette: palette, onExpand: onExpand)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = makeRootView()
        let header = makeHeader(title: L10n.tr("文本"), detail: L10n.format("{0} 字符", [text.count]))
        let scrollView = NSTextView.scrollableTextView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        guard let textView = scrollView.documentView as? NSTextView else {
            self.view = root
            return
        }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textColor = palette.textPrimary
        textView.font = font
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textContainer?.lineFragmentPadding = 4
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.string = text
        textView.setAccessibilityLabel(L10n.tr("文本预览"))

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = 1.5
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: palette.textPrimary,
            .paragraphStyle: paragraphStyle
        ]
        textView.textStorage?.setAttributes(
            textView.typingAttributes,
            range: NSRange(location: 0, length: textView.string.utf16.count)
        )

        root.addSubview(header)
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        self.view = root
    }
}

private final class ImagePreviewViewController: PreviewContentViewController {
    private let image: NSImage
    private let pixelSize: NSSize

    init(
        image: NSImage,
        pixelSize: NSSize,
        palette: Palette,
        onExpand: @escaping () -> Void
    ) {
        self.image = image
        self.pixelSize = pixelSize
        super.init(palette: palette, onExpand: onExpand)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = makeRootView()
        let dimensions = "\(Int(pixelSize.width)) × \(Int(pixelSize.height))"
        let header = makeHeader(title: L10n.tr("图片"), detail: dimensions)

        let imageBackground = NSView()
        imageBackground.translatesAutoresizingMaskIntoConstraints = false
        imageBackground.wantsLayer = true
        imageBackground.layer?.backgroundColor = palette.thumbPlaceholder.cgColor
        imageBackground.layer?.cornerRadius = 6
        imageBackground.layer?.masksToBounds = true

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = image
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyDown
        imageView.animates = true
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setAccessibilityLabel(L10n.format("图片预览，尺寸 {0}", [dimensions]))

        imageBackground.addSubview(imageView)
        root.addSubview(header)
        root.addSubview(imageBackground)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),

            imageBackground.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            imageBackground.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            imageBackground.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            imageBackground.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),

            imageView.leadingAnchor.constraint(equalTo: imageBackground.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageBackground.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: imageBackground.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageBackground.bottomAnchor)
        ])
        self.view = root
    }
}
