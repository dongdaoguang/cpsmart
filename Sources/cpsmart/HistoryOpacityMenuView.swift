import AppKit
import Carbon.HIToolbox

final class HistoryOpacityMenuView: NSView {
    private final class PreviewSlider: NSSlider {
        var beginPreview: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            beginPreview?()
            super.mouseDown(with: event)
        }
    }

    private let slider = PreviewSlider()
    private let onChange: (Double) -> Void

    var value: Double {
        get { slider.doubleValue }
        set { slider.doubleValue = newValue }
    }

    init(value: Double, beginPreview: @escaping () -> Void, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 232, height: 70))
        autoresizingMask = [.width]

        let title = NSTextField(labelWithString: L10n.tr("浮窗背景透明度"))
        title.font = .menuFont(ofSize: 13)
        let opaque = NSTextField(labelWithString: L10n.tr("更不透明"))
        let transparent = NSTextField(labelWithString: L10n.tr("更透明"))
        for label in [opaque, transparent] {
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
        }

        slider.minValue = 0
        slider.maxValue = 1
        slider.doubleValue = value
        slider.isContinuous = true
        slider.beginPreview = beginPreview
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.setAccessibilityLabel(title.stringValue)

        for view in [title, slider, opaque, transparent] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            slider.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 3),
            slider.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            opaque.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: 1),
            opaque.leadingAnchor.constraint(equalTo: slider.leadingAnchor),
            transparent.firstBaselineAnchor.constraint(equalTo: opaque.firstBaselineAnchor),
            transparent.trailingAnchor.constraint(equalTo: slider.trailingAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    @objc private func sliderChanged() {
        // Keyboard and accessibility adjustments do not start with a mouse-down.
        slider.beginPreview?()
        onChange(value)
    }

    // Menu keyboard navigation focuses the custom item view.
    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_LeftArrow: value = max(0, value - 0.05)
        case kVK_RightArrow: value = min(1, value + 0.05)
        default:
            super.keyDown(with: event)
            return
        }
        sliderChanged()
    }
}
