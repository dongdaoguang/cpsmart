import AppKit

final class PinboardInteractionCoordinator: NSObject {
    var onCreate: ((String, PinboardColor) -> Pinboard?)?
    var onRename: ((UUID, String) -> Void)?
    var onSetColor: ((UUID, PinboardColor) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onAddEntries: (([ClipboardEntry], UUID) -> Void)?
    var onSwitchSource: ((UUID) -> Void)?
    var onStatus: ((String, Bool) -> Void)?

    private var pinboards: [Pinboard] = []
    private var palette = AppVisualTheme.palette(isDark: true)
    private var pendingFavoriteEntries: [ClipboardEntry] = []
    private weak var presentationWindow: NSWindow?

    func update(pinboards: [Pinboard], palette: Palette, presentationWindow: NSWindow?) {
        self.pinboards = pinboards
        self.palette = palette
        self.presentationWindow = presentationWindow
    }

    func makeContextMenu(for board: Pinboard) -> NSMenu {
        let menu = NSMenu()

        let renameItem = NSMenuItem(
            title: L10n.tr("重命名…"),
            action: #selector(renameFromMenu(_:)),
            keyEquivalent: ""
        )
        renameItem.target = self
        renameItem.representedObject = board.id.uuidString
        menu.addItem(renameItem)

        let colorItem = NSMenuItem(title: L10n.tr("颜色"), action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        for color in PinboardColor.allCases {
            let item = NSMenuItem(
                title: color.displayName,
                action: #selector(changeColorFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = Self.colorDot(palette.pinboardColor(color))
            item.state = board.color == color ? .on : .off
            item.representedObject = "\(board.id.uuidString)|\(color.rawValue)"
            colorMenu.addItem(item)
        }
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)
        menu.addItem(.separator())

        let deleteItem = NSMenuItem(
            title: L10n.tr("删除收藏板…"),
            action: #selector(deleteFromMenu(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.representedObject = board.id.uuidString
        menu.addItem(deleteItem)
        return menu
    }

    func presentCreate(on window: NSWindow, adding entries: [ClipboardEntry]) {
        presentationWindow = window
        let alert = NSAlert()
        alert.messageText = L10n.tr("新建收藏板")
        alert.informativeText = L10n.tr("收藏板用于长期保存常用文本、命令、图片或文件。")
        alert.addButton(withTitle: L10n.tr("创建"))
        alert.addButton(withTitle: L10n.tr("取消"))

        let nameField = NSTextField(string: "")
        nameField.placeholderString = L10n.tr("名称，例如：常用命令")
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.widthAnchor.constraint(equalToConstant: 280).isActive = true
        let colorPicker = PinboardColorPickerView(
            colors: PinboardColor.allCases.map { palette.pinboardColor($0) },
            names: PinboardColor.allCases.map(\.displayName)
        )
        colorPicker.select(index: pinboards.count % PinboardColor.allCases.count)

        let form = NSStackView(views: [nameField, colorPicker])
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 10
        form.frame = NSRect(x: 0, y: 0, width: 280, height: 62)
        alert.accessoryView = form
        alert.window.initialFirstResponder = nameField

        alert.beginSheetModal(for: window) { [weak self, weak nameField, weak colorPicker] response in
            guard response == .alertFirstButtonReturn,
                  let self,
                  let name = nameField?.stringValue,
                  let selectedIndex = colorPicker?.selectedIndex,
                  PinboardColor.allCases.indices.contains(selectedIndex) else { return }
            guard let normalizedName = PinboardInteractionSupport.normalizedName(name) else {
                self.onStatus?(L10n.tr("收藏板名称不能为空"), true)
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, let window else { return }
                    self.presentCreate(on: window, adding: entries)
                }
                return
            }
            guard let board = self.onCreate?(
                normalizedName,
                PinboardColor.allCases[selectedIndex]
            ) else { return }
            if entries.isEmpty {
                self.onSwitchSource?(board.id)
            } else {
                self.onAddEntries?(entries, board.id)
                self.onStatus?(L10n.format("已收藏 {0} 项到“{1}”", [entries.count, board.name]), false)
            }
        }
    }

    func presentFavoriteMenu(
        from sender: NSButton,
        anchorView: NSView?,
        entries: [ClipboardEntry],
        on window: NSWindow
    ) {
        guard !entries.isEmpty else { return }
        presentationWindow = window
        pendingFavoriteEntries = entries
        defer { pendingFavoriteEntries.removeAll(keepingCapacity: false) }
        guard !pinboards.isEmpty else {
            presentCreate(on: window, adding: entries)
            return
        }

        let menu = NSMenu()
        let headerTitle = entries.count == 1 ? L10n.tr("收藏到收藏板") : L10n.format("收藏 {0} 项到收藏板", [entries.count])
        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.attributedTitle = NSAttributedString(
            string: headerTitle,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        menu.addItem(header)
        for board in pinboards {
            let item = NSMenuItem(
                title: board.name,
                action: #selector(addPendingSelection(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = Self.colorDot(palette.pinboardColor(board.color))
            item.representedObject = board.id.uuidString
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let createItem = NSMenuItem(
            title: L10n.tr("新建收藏板…"),
            action: #selector(createForPendingSelection(_:)),
            keyEquivalent: ""
        )
        createItem.target = self
        menu.addItem(createItem)

        let targetView = anchorView ?? sender
        let y = anchorView == nil ? sender.bounds.height + 3 : targetView.bounds.height + 4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: targetView)
    }

    @objc private func renameFromMenu(_ sender: NSMenuItem) {
        guard let id = PinboardInteractionSupport.boardID(from: sender.representedObject),
              let board = pinboards.first(where: { $0.id == id }),
              let presentationWindow else { return }
        let alert = NSAlert()
        alert.messageText = L10n.tr("重命名收藏板")
        alert.addButton(withTitle: L10n.tr("保存"))
        alert.addButton(withTitle: L10n.tr("取消"))
        let nameField = NSTextField(string: board.name)
        nameField.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = nameField
        alert.window.initialFirstResponder = nameField
        alert.beginSheetModal(for: presentationWindow) { [weak self, weak nameField] response in
            guard response == .alertFirstButtonReturn,
                  let name = nameField?.stringValue else { return }
            guard let normalizedName = PinboardInteractionSupport.normalizedName(name) else {
                self?.onStatus?(L10n.tr("收藏板名称不能为空"), true)
                return
            }
            self?.onRename?(id, normalizedName)
        }
    }

    @objc private func changeColorFromMenu(_ sender: NSMenuItem) {
        guard let (id, color) = PinboardInteractionSupport.boardColor(
            from: sender.representedObject
        ) else { return }
        onSetColor?(id, color)
    }

    @objc private func deleteFromMenu(_ sender: NSMenuItem) {
        guard let id = PinboardInteractionSupport.boardID(from: sender.representedObject),
              let board = pinboards.first(where: { $0.id == id }),
              let presentationWindow else { return }
        let alert = NSAlert()
        alert.messageText = L10n.format("删除收藏板“{0}”？", [board.name])
        alert.informativeText = L10n.format("其中的 {0} 项收藏会一并删除，此操作无法撤销。", [board.entries.count])
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("删除"))
        alert.addButton(withTitle: L10n.tr("取消"))
        alert.beginSheetModal(for: presentationWindow) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.onDelete?(id)
        }
    }

    @objc private func addPendingSelection(_ sender: NSMenuItem) {
        guard let id = PinboardInteractionSupport.boardID(from: sender.representedObject),
              let board = pinboards.first(where: { $0.id == id }),
              !pendingFavoriteEntries.isEmpty else { return }
        let addedCount = PinboardInteractionSupport.addedCount(
            entries: pendingFavoriteEntries,
            to: board
        )
        onAddEntries?(pendingFavoriteEntries, id)
        onStatus?(
            addedCount == 0
                ? L10n.format("所选内容已在“{0}”中", [board.name])
                : L10n.format("已收藏 {0} 项到“{1}”", [addedCount, board.name]),
            false
        )
    }

    @objc private func createForPendingSelection(_ sender: NSMenuItem) {
        guard let presentationWindow, !pendingFavoriteEntries.isEmpty else { return }
        presentCreate(on: presentationWindow, adding: pendingFavoriteEntries)
    }

    private static func colorDot(_ color: NSColor, diameter: CGFloat = 9) -> NSImage {
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        color.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: 0.5,
                y: 0.5,
                width: diameter - 1,
                height: diameter - 1
            )
        ).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
