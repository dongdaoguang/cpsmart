import AppKit

enum HistoryPanelOpacity {
    private static let key = "historyPanelTransparency"
    static let defaultValue = 0.0

    static var value: Double {
        guard let saved = UserDefaults.standard.object(forKey: key) as? NSNumber else {
            return defaultValue
        }
        return normalized(saved.doubleValue)
    }

    static func setValue(_ value: Double) {
        UserDefaults.standard.set(normalized(value), forKey: key)
    }

    private static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : defaultValue
    }
}

/// Only the material and tint live here. Controls and card contents are drawn above this view.
final class HistoryPanelBackdrop: NSView {
    private let material = NSVisualEffectView()
    private let tint = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = HistoryWindowTheme.panelRadius
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        tint.wantsLayer = true
        for view in [material, tint] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(palette: Palette, transparency: Double) {
        // The midpoint keeps the original full-strength blur and the theme's original tint.
        let base = palette.panelTint.alphaComponent
        let offset = CGFloat(transparency * 2 - 1)
        let minimumTint: CGFloat = 0.08
        let tintAlpha = offset < 0 ? base - offset * (1 - base) : base + offset * (minimumTint - base)
        let remainingBlur = 1 - max(0, offset)
        material.alphaValue = remainingBlur * remainingBlur
        material.isHidden = material.alphaValue == 0
        tint.layer?.backgroundColor = palette.panelTint.withAlphaComponent(tintAlpha).cgColor
        layer?.borderColor = palette.panelBorder.cgColor
    }
}
