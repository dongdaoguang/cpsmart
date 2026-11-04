import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum PasteResult {
    case posted
    case permissionRequired
    case targetUnavailable
}

/// 浮窗取得焦点前记录实际接收键盘输入的窗口。
struct PasteTarget {
    let application: NSRunningApplication
    let axApplication: AXUIElement
    let window: AXUIElement?

    init(application: NSRunningApplication) {
        self.application = application
        axApplication = AXUIElementCreateApplication(application.processIdentifier)
        // 限制同步 AX 调用的等待时间，避免未响应的应用卡住浮窗。
        AXUIElementSetMessagingTimeout(axApplication, 0.15)
        window = AXIsProcessTrusted() ? Self.focusedWindow(in: axApplication) : nil
        if let window {
            AXUIElementSetMessagingTimeout(window, 0.15)
        }
    }

    private static func focusedWindow(in application: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXFocusedWindowAttribute as CFString, &value
        ) == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    fileprivate var focus: PasteFocus {
        guard !application.isTerminated, let window else { return .unavailable }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if frontmostPID == nil || frontmostPID == ProcessInfo.processInfo.processIdentifier {
            return .waitingForActivation
        }
        guard frontmostPID == application.processIdentifier else { return .unavailable }
        guard let focusedWindow = Self.focusedWindow(in: axApplication) else {
            return .waitingForActivation
        }
        guard CFEqual(focusedWindow, window) else { return .differentWindow }
        return application.isActive ? .focused : .unavailable
    }

    fileprivate func restoreWindow() {
        guard let window else { return }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}

enum PasteFocus {
    case waitingForActivation
    case differentWindow
    case focused
    case unavailable
}

@MainActor
enum PasteController {
    static func paste(to target: PasteTarget?) async -> PasteResult {
        guard let target, !target.application.isTerminated,
              target.application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return .targetUnavailable
        }

        guard CGPreflightPostEventAccess() else {
            _ = CGRequestPostEventAccess()
            return .permissionRequired
        }
        guard AXIsProcessTrusted() else { return .permissionRequired }
        guard target.window != nil, !Task.isCancelled else { return .targetUnavailable }

        let pasteboardChange = NSPasteboard.general.changeCount
        if !target.application.isActive,
           !target.application.activate(options: [.activateIgnoringOtherApps]) {
            return .targetUnavailable
        }
        let posted = await Self.postWhenFocused(
            readFocus: { target.focus },
            restoreWindow: { target.restoreWindow() },
            post: {
                guard NSPasteboard.general.changeCount == pasteboardChange else { return false }
                return postCommandV(to: target.application.processIdentifier)
            }
        )
        return posted ? .posted : .targetUnavailable
    }

    static func postWhenFocused(
        readFocus: () -> PasteFocus,
        restoreWindow: () -> Void,
        post: () -> Bool
    ) async -> Bool {
        var requestedRestore = false
        let deadline = ContinuousClock.now + .seconds(1)
        while !Task.isCancelled && ContinuousClock.now < deadline {
            switch readFocus() {
            case .waitingForActivation:
                break
            case .differentWindow:
                if !requestedRestore {
                    restoreWindow()
                    requestedRestore = true
                }
            case .focused:
                return post()
            case .unavailable:
                return false
            }
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return false
            }
        }
        return false
    }

    private static func postCommandV(to processID: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_ANSI_V),
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: CGKeyCode(kVK_ANSI_V),
                  keyDown: false
              ) else {
            return false
        }

        keyDown.flags = [.maskCommand]
        keyUp.flags = [.maskCommand]
        keyDown.postToPid(processID)
        keyUp.postToPid(processID)
        return true
    }
}
