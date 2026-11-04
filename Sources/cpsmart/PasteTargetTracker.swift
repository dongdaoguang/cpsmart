import AppKit
import ApplicationServices

final class PasteTargetTracker {
    private(set) var target: PasteTarget?
    private var observer: AXObserver?

    func track(_ application: NSRunningApplication?) {
        precondition(Thread.isMainThread)
        guard let application, !application.isTerminated,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            stop()
            return
        }

        if target?.application != application {
            stop()
        }
        if observer == nil, AXIsProcessTrusted() {
            observeFocusedWindow(of: application)
        }
        target = PasteTarget(application: application)
    }

    func resumeObserving() {
        guard observer == nil, AXIsProcessTrusted(),
              let application = target?.application, !application.isTerminated else { return }
        observeFocusedWindow(of: application)
    }

    func stopObserving() {
        precondition(Thread.isMainThread)
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
    }

    func stop() {
        stopObserving()
        target = nil
    }

    deinit {
        stop()
    }

    private func observeFocusedWindow(of application: NSRunningApplication) {
        var windowObserver: AXObserver?
        let result = AXObserverCreate(application.processIdentifier, { observer, _, _, context in
            guard let context else { return }
            let tracker = Unmanaged<PasteTargetTracker>.fromOpaque(context).takeUnretainedValue()
            tracker.focusedWindowChanged(observer)
        }, &windowObserver)
        guard result == .success, let windowObserver else { return }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.15)
        guard AXObserverAddNotification(
            windowObserver,
            appElement,
            kAXFocusedWindowChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        ) == .success else { return }

        observer = windowObserver
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(windowObserver), .commonModes)
    }

    private func focusedWindowChanged(_ observer: AXObserver) {
        // 应用切换后可能还有排队的旧通知，只接受当前前台应用的焦点变化。
        guard observer === self.observer,
              let application = target?.application, !application.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier
        else { return }
        target = PasteTarget(application: application)
    }
}
