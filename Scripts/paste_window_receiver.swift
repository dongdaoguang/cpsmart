import AppKit
import Carbon.HIToolbox

// A real responder-chain destination. Never invokes NSTextView.paste or reads the pasteboard.
final class PasteInput: NSTextView {
    var receipts = 0

    @objc func receiveTestPaste(_ sender: Any?) {
        receipts += 1
    }
}

final class Receiver: NSObject, NSApplicationDelegate {
    private let trials = [(0, "return"), (1, "return"), (0, "double-click"), (1, "double-click")]
    private var inputs: [PasteInput] = []
    private var windows: [NSWindow] = []
    private var trial = 0
    private var returnEvents = 0
    private var keyMonitor: Any?
    private var child: NSRunningApplication?
    private let originalPointer = CGEvent(source: nil)?.location
    private(set) var passed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.count == 3, NSScreen.screens.count >= 2 else {
            fail("Two physical displays, a cpsmart bundle and an isolated directory are required")
            return
        }
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let applicationItem = menu.addItem(withTitle: "Receiver", action: nil, keyEquivalent: "")
        applicationItem.submenu = NSMenu()
        let editItem = menu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = NSMenu()
        editItem.submenu?.autoenablesItems = false
        editItem.submenu?.addItem(withTitle: "Paste", action: #selector(PasteInput.receiveTestPaste(_:)), keyEquivalent: "v")
        NSApp.mainMenu = menu
        for (index, screen) in NSScreen.screens.prefix(2).enumerated() {
            let frame = NSRect(x: screen.visibleFrame.midX - 130, y: screen.visibleFrame.midY - 50, width: 260, height: 100)
            let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.title = "cpsmart paste receiver \(index)"
            let input = PasteInput(frame: NSRect(origin: .zero, size: frame.size))
            window.contentView = input
            window.orderFront(nil)
            inputs.append(input)
            windows.append(window)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
                self?.returnEvents += 1
                return nil
            }
            return event
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.startTrial() }
    }

    private func startTrial() {
        guard trial < trials.count else {
            passed = true
            NSApp.terminate(nil)
            return
        }
        let (screen, trigger) = trials[trial]
        let baseline = inputs.map(\.receipts)
        NSApp.activate(ignoringOtherApps: true)
        windows[screen].makeKeyAndOrderFront(nil)
        windows[screen].makeFirstResponder(inputs[screen])
        // Deliberately put the pointer on the other display. It only positions the history panel.
        let opposite = NSScreen.screens[1 - screen].frame
        CGWarpMouseCursorPosition(CGPoint(x: opposite.midX, y: NSScreen.screens[0].frame.maxY - opposite.midY))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard NSApp.isActive, self.windows[screen].isKeyWindow,
                  self.windows[screen].firstResponder === self.inputs[screen] else {
                self.fail("Receiver focus check failed on display \(screen): active=\(NSApp.isActive) key=\(self.windows[screen].isKeyWindow) input=\(self.windows[screen].firstResponder === self.inputs[screen])")
                return
            }
            let appURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            let isolatedHome = CommandLine.arguments[2]
            let store = URL(fileURLWithPath: isolatedHome).appendingPathComponent("store")
            let result = store.appendingPathComponent("paste-result")
            try? FileManager.default.removeItem(at: result)
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            config.activates = false
            config.addsToRecentItems = false
            config.promptsUserIfNeeded = false
            config.arguments = ["--package-smoke-test", "--test-paste-window", trigger]
            config.environment = [
                "CFFIXED_USER_HOME": isolatedHome,
                "CPSMART_PACKAGE_SMOKE_ROOT": store.path,
                "CPSMART_TEST_RECEIVER_PID": String(ProcessInfo.processInfo.processIdentifier)
            ]
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { app, error in
                DispatchQueue.main.async {
                    guard let app, app.bundleURL?.resolvingSymlinksInPath() == appURL.resolvingSymlinksInPath() else {
                        self.fail(error?.localizedDescription ?? "Could not launch isolated cpsmart")
                        return
                    }
                    self.child = app
                    let deadline = Date().addingTimeInterval(8)
                    Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
                        guard app.isTerminated else {
                            if Date() > deadline { self.fail("Paste test application timed out") }
                            return
                        }
                        timer.invalidate()
                        var expected = baseline
                        expected[screen] += 1
                        let actual = self.inputs.map(\.receipts)
                        let status = (try? String(contentsOf: result, encoding: .utf8)) ?? "no result"
                        print("display=\(screen) trigger=\(trigger) status=\(status) receipts=\(actual) expected=\(expected) returnEvents=\(self.returnEvents)")
                        guard status == "posted", actual == expected, self.returnEvents == 0 else {
                            self.fail("Paste was not received exclusively by the intended responder")
                            return
                        }
                        self.trial += 1
                        if self.trial == self.trials.count { print("All paste window trials passed") }
                        self.startTrial()
                    }
                }
            }
        }
    }

    private func fail(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        cleanUp()
        exit(1)
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanUp()
    }

    private func cleanUp() {
        if let child, !child.isTerminated { child.terminate() }
        if let originalPointer { CGWarpMouseCursorPosition(originalPointer) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }
}

let app = NSApplication.shared
let receiver = Receiver()
app.delegate = receiver
app.run()
exit(receiver.passed ? 0 : 1)
