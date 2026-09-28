import AppKit
import Carbon
import Foundation

enum ShortcutActionID: String, CaseIterable, Codable {
    case toggleHistory
    case selectPrevious
    case selectNext
    case toggleSearchFocus
    case pasteSelection
    case toggleQuickLook
    case togglePin
    case addToPinboard
    case deleteSelection
    case filterAll
    case filterText
    case filterImage
    case filterFiles
    case clearSearchOrClose

    enum Group: CaseIterable {
        case global
        case browsing
        case actions
        case filters
        case window
    }

    var displayName: String {
        switch self {
        case .toggleHistory: return L10n.tr("打开或关闭历史")
        case .selectPrevious: return L10n.tr("选择上一项")
        case .selectNext: return L10n.tr("选择下一项")
        case .toggleSearchFocus: return L10n.tr("切换卡片与搜索框")
        case .pasteSelection: return L10n.tr("粘贴所选内容")
        case .toggleQuickLook: return L10n.tr("Quick Look 预览")
        case .togglePin: return L10n.tr("置顶或取消置顶")
        case .addToPinboard: return L10n.tr("收藏到收藏板")
        case .deleteSelection: return L10n.tr("删除所选记录")
        case .filterAll: return L10n.tr("筛选：全部")
        case .filterText: return L10n.tr("筛选：文本")
        case .filterImage: return L10n.tr("筛选：图片")
        case .filterFiles: return L10n.tr("筛选：文件")
        case .clearSearchOrClose: return L10n.tr("清除搜索或关闭")
        }
    }

    var group: Group {
        switch self {
        case .toggleHistory: return .global
        case .selectPrevious, .selectNext, .toggleSearchFocus: return .browsing
        case .pasteSelection, .toggleQuickLook, .togglePin, .addToPinboard,
             .deleteSelection: return .actions
        case .filterAll, .filterText, .filterImage, .filterFiles: return .filters
        case .clearSearchOrClose: return .window
        }
    }

    static var localActions: [ShortcutActionID] {
        allCases.filter { $0 != .toggleHistory }
    }
}

struct ShortcutGesture: Codable, Hashable {
    let keyCode: UInt16
    let modifiersRawValue: UInt
    let recordedKeyLabel: String?

    init(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        recordedKeyLabel: String? = nil
    ) {
        self.keyCode = keyCode
        modifiersRawValue = Self.normalized(modifiers).rawValue
        self.recordedKeyLabel = recordedKeyLabel
    }

    var modifiers: NSEvent.ModifierFlags {
        Self.normalized(NSEvent.ModifierFlags(rawValue: modifiersRawValue))
    }

    static func from(event: NSEvent) -> ShortcutGesture {
        let label = event.charactersIgnoringModifiers.flatMap { characters -> String? in
            guard !characters.isEmpty,
                  characters.unicodeScalars.allSatisfy({
                      !CharacterSet.controlCharacters.contains($0)
                  }) else { return nil }
            return characters.uppercased()
        }
        return ShortcutGesture(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            recordedKeyLabel: label
        )
    }

    static func normalized(_ modifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        modifiers.intersection([.command, .option, .control, .shift])
    }

    static func == (lhs: ShortcutGesture, rhs: ShortcutGesture) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    var displayString: String {
        displayTokens.joined()
    }

    var displayTokens: [String] {
        var result: [String] = []
        if modifiers.contains(.control) { result.append("⌃") }
        if modifiers.contains(.option) { result.append("⌥") }
        if modifiers.contains(.shift) { result.append("⇧") }
        if modifiers.contains(.command) { result.append("⌘") }
        result.append(Self.keyLabel(for: keyCode, recordedKeyLabel: recordedKeyLabel))
        return result
    }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    static func isNonTextKey(_ keyCode: UInt16) -> Bool {
        nonTextKeyLabels[keyCode] != nil || keyCode == UInt16(kVK_Space)
    }

    private static func keyLabel(for keyCode: UInt16, recordedKeyLabel: String?) -> String {
        if keyCode == UInt16(kVK_Space) { return "Space" }
        if let label = nonTextKeyLabels[keyCode] { return label }
        if let recordedKeyLabel, !recordedKeyLabel.isEmpty { return recordedKeyLabel }
        return ansiKeyLabels[keyCode] ?? "Key \(keyCode)"
    }

    private static let nonTextKeyLabels: [UInt16: String] = [
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_Return): "Return",
        UInt16(kVK_ANSI_KeypadEnter): "Enter",
        UInt16(kVK_Escape): "Esc",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "Home",
        UInt16(kVK_End): "End",
        UInt16(kVK_PageUp): "Page Up",
        UInt16(kVK_PageDown): "Page Down",
        UInt16(kVK_Help): "Help",
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13",
        UInt16(kVK_F14): "F14",
        UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17",
        UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19",
        UInt16(kVK_F20): "F20"
    ]

    private static let ansiKeyLabels: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B",
        UInt16(kVK_ANSI_C): "C", UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I", UInt16(kVK_ANSI_J): "J",
        UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N",
        UInt16(kVK_ANSI_O): "O", UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U", UInt16(kVK_ANSI_V): "V",
        UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1",
        UInt16(kVK_ANSI_2): "2", UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8", UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_ANSI_Minus): "-", UInt16(kVK_ANSI_Equal): "=",
        UInt16(kVK_ANSI_LeftBracket): "[", UInt16(kVK_ANSI_RightBracket): "]",
        UInt16(kVK_ANSI_Backslash): "\\", UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Quote): "'", UInt16(kVK_ANSI_Comma): ",",
        UInt16(kVK_ANSI_Period): ".", UInt16(kVK_ANSI_Slash): "/",
        UInt16(kVK_ANSI_Grave): "`"
    ]
}

enum ShortcutDefaults {
    static let bindings: [ShortcutActionID: [ShortcutGesture]] = [
        .toggleHistory: [ShortcutGesture(
            keyCode: UInt16(kVK_ANSI_V),
            modifiers: [.shift, .command]
        )],
        .selectPrevious: [ShortcutGesture(keyCode: UInt16(kVK_LeftArrow))],
        .selectNext: [ShortcutGesture(keyCode: UInt16(kVK_RightArrow))],
        .toggleSearchFocus: [ShortcutGesture(keyCode: UInt16(kVK_Tab))],
        .pasteSelection: [
            ShortcutGesture(keyCode: UInt16(kVK_Return)),
            ShortcutGesture(keyCode: UInt16(kVK_ANSI_KeypadEnter))
        ],
        .toggleQuickLook: [ShortcutGesture(keyCode: UInt16(kVK_Space))],
        .togglePin: [ShortcutGesture(keyCode: UInt16(kVK_ANSI_P), modifiers: [.command])],
        .addToPinboard: [ShortcutGesture(keyCode: UInt16(kVK_ANSI_D), modifiers: [.command])],
        .deleteSelection: [
            ShortcutGesture(keyCode: UInt16(kVK_Delete), modifiers: [.command]),
            ShortcutGesture(keyCode: UInt16(kVK_ForwardDelete), modifiers: [.command])
        ],
        .filterAll: [ShortcutGesture(keyCode: UInt16(kVK_ANSI_1), modifiers: [.command])],
        .filterText: [ShortcutGesture(keyCode: UInt16(kVK_ANSI_2), modifiers: [.command])],
        .filterImage: [ShortcutGesture(keyCode: UInt16(kVK_ANSI_3), modifiers: [.command])],
        .filterFiles: [ShortcutGesture(keyCode: UInt16(kVK_ANSI_4), modifiers: [.command])],
        .clearSearchOrClose: [ShortcutGesture(keyCode: UInt16(kVK_Escape))]
    ]
}

enum ShortcutValidationIssue: Equatable {
    case requiresModifier
    case globalRequiresModifier
    case reservedByApplication
    case conflictsWith(ShortcutActionID)

    var message: String {
        switch self {
        case .requiresModifier:
            return L10n.tr("字母、数字或标点需要搭配 ⌘、⌥ 或 ⌃。")
        case .globalRequiresModifier:
            return L10n.tr("全局快捷键需要包含 ⌘、⌥ 或 ⌃。")
        case .reservedByApplication:
            return L10n.tr("该组合已被 cpsmart 或 macOS 保留，请选择其他快捷键。")
        case .conflictsWith(let action):
            return L10n.format("与“{0}”的快捷键冲突。", [action.displayName])
        }
    }
}

final class ShortcutStore: NSObject {
    static let didChangeNotification = Notification.Name("cpsmartShortcutStoreDidChange")
    static let defaultsKey = "keyboardShortcuts.v1"

    private struct PersistedOverrides: Codable {
        let version: Int
        let bindings: [String: [ShortcutGesture]]
    }

    private let userDefaults: UserDefaults
    private var overrides: [ShortcutActionID: [ShortcutGesture]] = [:]

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        super.init()
        load()
    }

    var hasCustomizations: Bool { !overrides.isEmpty }

    var customizationCount: Int { overrides.count }

    func isCustomized(_ action: ShortcutActionID) -> Bool {
        overrides[action] != nil
    }

    func bindings(for action: ShortcutActionID) -> [ShortcutGesture] {
        overrides[action] ?? ShortcutDefaults.bindings[action] ?? []
    }

    func primaryBinding(for action: ShortcutActionID) -> ShortcutGesture {
        bindings(for: action).first
            ?? ShortcutDefaults.bindings[action]!.first!
    }

    func displayString(for action: ShortcutActionID) -> String {
        bindings(for: action).map(\.displayString).joined(separator: " / ")
    }

    func defaultBindings(for action: ShortcutActionID) -> [ShortcutGesture] {
        ShortcutDefaults.bindings[action] ?? []
    }

    func defaultDisplayString(for action: ShortcutActionID) -> String {
        defaultBindings(for: action).map(\.displayString).joined(separator: " / ")
    }

    func action(
        matching gesture: ShortcutGesture,
        among actions: [ShortcutActionID]
    ) -> ShortcutActionID? {
        actions.first { bindings(for: $0).contains(gesture) }
    }

    func validate(
        _ gesture: ShortcutGesture,
        for action: ShortcutActionID
    ) -> ShortcutValidationIssue? {
        if let issue = Self.intrinsicValidationIssue(for: gesture, action: action) {
            return issue
        }
        for otherAction in ShortcutActionID.allCases where otherAction != action {
            if bindings(for: otherAction).contains(gesture) {
                return .conflictsWith(otherAction)
            }
        }
        return nil
    }

    @discardableResult
    func set(_ gesture: ShortcutGesture, for action: ShortcutActionID) -> ShortcutValidationIssue? {
        if let issue = validate(gesture, for: action) { return issue }
        setOverride([gesture], for: action)
        persistAndNotify()
        return nil
    }

    func validateReset(for action: ShortcutActionID) -> ShortcutValidationIssue? {
        validateBatch([action: defaultBindings(for: action)])
    }

    @discardableResult
    func resetToDefault(_ action: ShortcutActionID) -> ShortcutValidationIssue? {
        if let issue = validateReset(for: action) { return issue }
        overrides[action] = nil
        persistAndNotify()
        return nil
    }

    func validateSwap(
        _ action: ShortcutActionID,
        with conflictingAction: ShortcutActionID,
        requestedGesture: ShortcutGesture
    ) -> ShortcutValidationIssue? {
        let replacement = primaryBinding(for: action)
        return validateBatch([
            action: [requestedGesture],
            conflictingAction: [replacement]
        ])
    }

    @discardableResult
    func swap(
        _ action: ShortcutActionID,
        with conflictingAction: ShortcutActionID,
        requestedGesture: ShortcutGesture
    ) -> ShortcutValidationIssue? {
        if let issue = validateSwap(
            action,
            with: conflictingAction,
            requestedGesture: requestedGesture
        ) { return issue }
        let replacement = primaryBinding(for: action)
        setOverride([requestedGesture], for: action)
        setOverride([replacement], for: conflictingAction)
        persistAndNotify()
        return nil
    }

    func resetToDefaults() {
        overrides.removeAll()
        userDefaults.removeObject(forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func load() {
        guard let data = userDefaults.data(forKey: Self.defaultsKey),
              let persisted = try? JSONDecoder().decode(PersistedOverrides.self, from: data),
              persisted.version == 1 else { return }

        for action in ShortcutActionID.allCases {
            guard let gestures = persisted.bindings[action.rawValue], !gestures.isEmpty else { continue }
            overrides[action] = gestures
        }
        removeInvalidLoadedOverrides()
    }

    private func removeInvalidLoadedOverrides() {
        for action in ShortcutActionID.allCases where overrides[action] != nil {
            guard let gestures = overrides[action], gestures.count == 1 else {
                overrides[action] = nil
                continue
            }
            let gesture = gestures[0]
            if Self.intrinsicValidationIssue(for: gesture, action: action) != nil {
                overrides[action] = nil
            }
        }

        var removedConflict = true
        while removedConflict {
            removedConflict = false
            let actions = ShortcutActionID.allCases
            outer: for (index, first) in actions.enumerated() {
                for second in actions.dropFirst(index + 1) {
                    let firstBindings = bindings(for: first)
                    let secondBindings = bindings(for: second)
                    guard !Set(firstBindings).isDisjoint(with: Set(secondBindings)) else { continue }
                    if overrides[second] != nil {
                        overrides[second] = nil
                    } else if overrides[first] != nil {
                        overrides[first] = nil
                    }
                    removedConflict = true
                    break outer
                }
            }
        }
    }

    private func persistAndNotify() {
        if overrides.isEmpty {
            userDefaults.removeObject(forKey: Self.defaultsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
            return
        }
        let rawBindings = Dictionary(uniqueKeysWithValues: overrides.map {
            ($0.key.rawValue, $0.value)
        })
        let persisted = PersistedOverrides(version: 1, bindings: rawBindings)
        if let data = try? JSONEncoder().encode(persisted) {
            userDefaults.set(data, forKey: Self.defaultsKey)
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func setOverride(
        _ gestures: [ShortcutGesture],
        for action: ShortcutActionID
    ) {
        if ShortcutDefaults.bindings[action] == gestures {
            overrides[action] = nil
        } else {
            overrides[action] = gestures
        }
    }

    private func validateBatch(
        _ replacements: [ShortcutActionID: [ShortcutGesture]]
    ) -> ShortcutValidationIssue? {
        for (action, gestures) in replacements {
            for gesture in gestures {
                if let issue = Self.intrinsicValidationIssue(for: gesture, action: action) {
                    return issue
                }
            }
            for otherAction in ShortcutActionID.allCases where otherAction != action {
                let otherBindings = replacements[otherAction] ?? bindings(for: otherAction)
                if !Set(gestures).isDisjoint(with: Set(otherBindings)) {
                    return .conflictsWith(otherAction)
                }
            }
        }
        return nil
    }

    private static func intrinsicValidationIssue(
        for gesture: ShortcutGesture,
        action: ShortcutActionID
    ) -> ShortcutValidationIssue? {
        let commandLike = gesture.modifiers.intersection([.command, .option, .control])
        if action == .toggleHistory, commandLike.isEmpty {
            return .globalRequiresModifier
        }
        if action != .toggleHistory,
           !ShortcutGesture.isNonTextKey(gesture.keyCode),
           commandLike.isEmpty {
            return .requiresModifier
        }
        if PinboardShortcutRouting.command(
            keyCode: gesture.keyCode,
            modifiers: gesture.modifiers
        ) != nil {
            return .reservedByApplication
        }
        if isReservedSystemShortcut(gesture) {
            return .reservedByApplication
        }
        return nil
    }

    private static func isReservedSystemShortcut(_ gesture: ShortcutGesture) -> Bool {
        let modifiers = gesture.modifiers
        if modifiers.contains(.command) {
            let lifecycleKeys: Set<UInt16> = [
                UInt16(kVK_ANSI_Q), UInt16(kVK_ANSI_H),
                UInt16(kVK_ANSI_M), UInt16(kVK_ANSI_W)
            ]
            if lifecycleKeys.contains(gesture.keyCode) { return true }
            if gesture.keyCode == UInt16(kVK_Tab) || gesture.keyCode == UInt16(kVK_Space) {
                return true
            }
            let standardEditingKeys: Set<UInt16> = [
                UInt16(kVK_ANSI_A), UInt16(kVK_ANSI_C), UInt16(kVK_ANSI_V),
                UInt16(kVK_ANSI_X), UInt16(kVK_ANSI_Z), UInt16(kVK_ANSI_Comma)
            ]
            if modifiers == [.command], standardEditingKeys.contains(gesture.keyCode) {
                return true
            }
            if modifiers == [.shift, .command], gesture.keyCode == UInt16(kVK_ANSI_Z) {
                return true
            }
        }
        if gesture.keyCode == UInt16(kVK_Space), modifiers.contains(.control) {
            return true
        }
        return false
    }
}

enum ShortcutContext {
    case browsing
    case searching
    case composingSearchText
    case quickLook
}

struct ShortcutMatcher {
    let store: ShortcutStore

    func action(for event: NSEvent, context: ShortcutContext) -> ShortcutActionID? {
        let gesture = ShortcutGesture.from(event: event)
        // 空格在搜索框里永远是输入字符：即使用户把 Space 绑定给预览或粘贴，
        // 无 ⌘ 修饰的 Space 在搜索态也必须穿透，否则无法输入多词搜索。
        if context == .searching,
           gesture.keyCode == UInt16(kVK_Space),
           !gesture.modifiers.contains(.command) {
            return nil
        }
        let actions: [ShortcutActionID]
        switch context {
        case .browsing:
            actions = ShortcutActionID.localActions
        case .searching:
            actions = [
                .toggleSearchFocus, .pasteSelection, .toggleQuickLook, .togglePin, .addToPinboard,
                .deleteSelection, .filterAll, .filterText, .filterImage, .filterFiles,
                .clearSearchOrClose
            ]
        case .composingSearchText:
            guard gesture.modifiers.contains(.command) else { return nil }
            actions = [
                .toggleSearchFocus, .pasteSelection, .toggleQuickLook, .togglePin, .addToPinboard,
                .deleteSelection, .filterAll, .filterText, .filterImage, .filterFiles,
                .clearSearchOrClose
            ]
        case .quickLook:
            actions = [.selectPrevious, .selectNext, .toggleQuickLook, .clearSearchOrClose]
        }
        let action = store.action(matching: gesture, among: actions)
        if context == .searching,
           let action,
           [.toggleQuickLook, .togglePin, .addToPinboard, .deleteSelection, .filterAll,
            .filterText, .filterImage, .filterFiles]
            .contains(action),
           !gesture.modifiers.contains(.command) {
            // 搜索框中保留无修饰键的输入、编辑和光标行为（例如 Space 必须能输入空格）。
            // 此类自定义键仍可在浏览态使用。
            return nil
        }
        return action
    }
}
