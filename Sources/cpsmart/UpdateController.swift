import AppKit
import Foundation

final class UpdateController {
    enum Activity {
        case idle
        case checking
        case downloading
    }

    private enum UpdateError: LocalizedError {
        case invalidInstalledVersion
        case invalidResponse
        case serverStatus(Int)
        case invalidRelease
        case untrustedDownload
        case downloadsDirectoryUnavailable
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .invalidInstalledVersion:
                return L10n.tr("无法读取当前应用版本。请使用正式安装包中的 cpsmart 再试。")
            case .invalidResponse:
                return L10n.tr("GitHub 返回了无法识别的响应。")
            case let .serverStatus(status):
                return L10n.format("GitHub 更新服务暂时不可用（HTTP {0}）。", [status])
            case .invalidRelease:
                return L10n.tr("最新 Release 没有有效的版本号。")
            case .untrustedDownload:
                return L10n.tr("安装包下载地址不属于 cpsmart 的官方 GitHub Release。")
            case .downloadsDirectoryUnavailable:
                return L10n.tr("找不到当前用户的“下载”文件夹。")
            case .downloadFailed:
                return L10n.tr("安装包下载失败或内容为空。")
            }
        }
    }

    private static let repositoryURL = URL(string: "https://github.com/dongdaoguang/cpsmart")!
    private static let latestReleasePage = URL(
        string: "https://github.com/dongdaoguang/cpsmart/releases/latest"
    )!
    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60
    private static let automaticCheckDelay: TimeInterval = 10
    private static let automaticChecksKey = "automaticallyChecksForUpdates"
    private static let lastAutomaticCheckKey = "lastAutomaticUpdateCheckDate"

    var onStateChange: (() -> Void)?
    private(set) var activity: Activity = .idle {
        didSet { onStateChange?() }
    }

    private let userDefaults: UserDefaults
    private var automaticTimer: Timer?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var menuItemTitle: String {
        switch activity {
        case .idle: return L10n.tr("检查更新…")
        case .checking: return L10n.tr("正在检查更新…")
        case .downloading: return L10n.tr("正在下载更新…")
        }
    }

    var automaticChecksEnabled: Bool {
        if userDefaults.object(forKey: Self.automaticChecksKey) == nil {
            return true
        }
        return userDefaults.bool(forKey: Self.automaticChecksKey)
    }

    func startAutomaticChecks() {
        scheduleNextAutomaticCheck()
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: Self.automaticChecksKey)
        automaticTimer?.invalidate()
        automaticTimer = nil
        if enabled {
            scheduleNextAutomaticCheck()
        }
    }

    func checkForUpdates() {
        performCheck(userInitiated: true)
    }

    private func scheduleNextAutomaticCheck() {
        guard automaticChecksEnabled, automaticTimer == nil else { return }

        let lastCheck = userDefaults.object(forKey: Self.lastAutomaticCheckKey) as? Date
        let elapsed = lastCheck.map { Date().timeIntervalSince($0) }
            ?? Self.automaticCheckInterval
        let delay = elapsed >= Self.automaticCheckInterval
            ? Self.automaticCheckDelay
            : Self.automaticCheckInterval - elapsed

        let timer = Timer(timeInterval: max(1, delay), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.automaticTimer = nil
            self.performCheck(userInitiated: false)
            self.scheduleNextAutomaticCheck()
        }
        RunLoop.main.add(timer, forMode: .common)
        automaticTimer = timer
    }

    private func performCheck(userInitiated: Bool) {
        guard activity == .idle else {
            if userInitiated {
                showInformation(
                    title: L10n.tr("更新任务正在进行"),
                    message: activity == .checking ? L10n.tr("正在检查 GitHub Release。") : L10n.tr("正在下载安装包。")
                )
            } else {
                // A manual check already covers this automatic interval. Defer the next timer
                // instead of retrying every 10 seconds while its alert or download is active.
                userDefaults.set(Date(), forKey: Self.lastAutomaticCheckKey)
            }
            return
        }

        guard let installedVersionString = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String,
        let installedVersion = AppVersion(installedVersionString) else {
            if userInitiated {
                showError(UpdateError.invalidInstalledVersion)
            } else {
                // 未打包的开发二进制没有应用版本；避免每 10 秒重新触发定时器。
                userDefaults.set(Date(), forKey: Self.lastAutomaticCheckKey)
            }
            return
        }

        // A manual check also satisfies the automatic interval. Reschedule the pending launch
        // timer so dismissing an update prompt quickly cannot trigger the same prompt again.
        userDefaults.set(Date(), forKey: Self.lastAutomaticCheckKey)
        if userInitiated, automaticChecksEnabled {
            automaticTimer?.invalidate()
            automaticTimer = nil
            scheduleNextAutomaticCheck()
        }

        activity = .checking
        var request = URLRequest(
            url: Self.latestReleasePage,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        request.httpMethod = "HEAD"
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("cpsmart/\(installedVersionString)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let result: Result<GitHubRelease, Error>
            if let error {
                result = .failure(error)
            } else if let response = response as? HTTPURLResponse,
                      !(200...299).contains(response.statusCode) {
                result = .failure(UpdateError.serverStatus(response.statusCode))
            } else if let finalURL = response?.url,
                      let release = GitHubRelease(latestReleaseURL: finalURL) {
                result = .success(release)
            } else {
                result = .failure(UpdateError.invalidResponse)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case let .success(release):
                    self.handle(
                        release: release,
                        installedVersion: installedVersion,
                        installedVersionString: installedVersionString,
                        userInitiated: userInitiated
                    )
                case let .failure(error):
                    self.writeDiagnostic("checkError=\(error.localizedDescription)")
                    if userInitiated { self.showError(error) }
                }
                // `handle` may start a download. Otherwise the check (including any modal alert)
                // is now fully finished and the menu can become available again.
                if self.activity == .checking {
                    self.activity = .idle
                }
            }
        }.resume()
    }

    private func handle(
        release: GitHubRelease,
        installedVersion: AppVersion,
        installedVersionString: String,
        userInitiated: Bool
    ) {
        guard let releaseVersion = release.version else {
            writeDiagnostic("release=\(release.tagName) validRelease=false")
            if userInitiated { showError(UpdateError.invalidRelease) }
            return
        }

        let assetName = release.installerAsset?.name ?? "none"
        writeDiagnostic(
            "installed=\(installedVersionString) release=\(release.tagName) "
                + "updateAvailable=\(installedVersion < releaseVersion) asset=\(assetName)"
        )

        guard installedVersion < releaseVersion else {
            if userInitiated {
                showInformation(
                    title: L10n.tr("cpsmart 已是最新版本"),
                    message: L10n.format("当前版本：{0}", [installedVersionString])
                )
            }
            return
        }

        showAvailableUpdate(release, version: release.tagName.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func showAvailableUpdate(_ release: GitHubRelease, version: String) {
        let alert = NSAlert()
        alert.messageText = L10n.format("发现 cpsmart 新版本 {0}", [version])
        alert.informativeText = L10n.tr("新版安装包将从 cpsmart 的官方 GitHub Release 下载，完成后会自动打开。")
        alert.alertStyle = .informational

        if let asset = release.installerAsset {
            alert.addButton(withTitle: L10n.tr("下载更新"))
            alert.addButton(withTitle: L10n.tr("更新日志"))
            alert.addButton(withTitle: L10n.tr("稍后"))
            switch runModal(alert) {
            case .alertFirstButtonReturn:
                download(asset, releaseVersion: version)
            case .alertSecondButtonReturn:
                NSWorkspace.shared.open(release.htmlURL)
            default:
                break
            }
        } else {
            alert.informativeText += L10n.tr("\n\n这个 Release 没有可下载的 DMG 安装包。")
            alert.addButton(withTitle: L10n.tr("更新日志"))
            alert.addButton(withTitle: L10n.tr("稍后"))
            if runModal(alert) == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.htmlURL)
            }
        }
    }

    private func download(_ asset: GitHubReleaseAsset, releaseVersion: String) {
        guard UpdateSupport.isTrustedReleaseDownloadURL(asset.browserDownloadURL) else {
            showError(UpdateError.untrustedDownload)
            return
        }

        activity = .downloading
        var request = URLRequest(
            url: asset.browserDownloadURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 60
        )
        request.setValue("cpsmart updater", forHTTPHeaderField: "User-Agent")

        URLSession.shared.downloadTask(with: request) { [weak self] temporaryURL, response, error in
            guard let self else { return }
            let result: Result<URL, Error>
            if let error {
                result = .failure(error)
            } else if let response = response as? HTTPURLResponse,
                      !(200...299).contains(response.statusCode) {
                result = .failure(UpdateError.serverStatus(response.statusCode))
            } else if let temporaryURL {
                do {
                    let values = try temporaryURL.resourceValues(forKeys: [.fileSizeKey])
                    let expectedSize = response?.expectedContentLength ?? NSURLSessionTransferSizeUnknown
                    guard let fileSize = values.fileSize,
                          fileSize > 0,
                          expectedSize <= 0 || Int64(fileSize) == expectedSize else {
                        throw UpdateError.downloadFailed
                    }
                    result = .success(try self.moveDownload(temporaryURL, named: asset.name))
                } catch {
                    result = .failure(error)
                }
            } else {
                result = .failure(UpdateError.downloadFailed)
            }

            DispatchQueue.main.async {
                self.activity = .idle
                switch result {
                case let .success(fileURL):
                    self.writeDiagnostic("downloaded=\(fileURL.lastPathComponent)")
                    let opened = NSWorkspace.shared.open(fileURL)
                    if !opened {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                    self.showDownloadedUpdate(
                        version: releaseVersion,
                        installerOpened: opened
                    )
                case let .failure(error):
                    self.writeDiagnostic("downloadError=\(error.localizedDescription)")
                    self.showError(error)
                }
            }
        }.resume()
    }

    private func moveDownload(_ temporaryURL: URL, named assetName: String) throws -> URL {
        guard let downloadsDirectory = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first else {
            throw UpdateError.downloadsDirectoryUnavailable
        }

        let safeName = URL(fileURLWithPath: assetName).lastPathComponent
        guard safeName.lowercased().hasSuffix(".dmg"), !safeName.isEmpty else {
            throw UpdateError.downloadFailed
        }

        let destination = uniqueDestination(in: downloadsDirectory, fileName: safeName)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func uniqueDestination(in directory: URL, fileName: String) -> URL {
        let initial = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: initial.path) else { return initial }

        let extensionName = initial.pathExtension
        let baseName = initial.deletingPathExtension().lastPathComponent
        for index in 2...999 {
            let candidate = directory.appendingPathComponent(
                "\(baseName) (\(index)).\(extensionName)"
            )
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return directory.appendingPathComponent("\(baseName)-\(UUID().uuidString).\(extensionName)")
    }

    private func showInformation(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("好"))
        runModal(alert)
    }

    private func showDownloadedUpdate(version: String, installerOpened: Bool) {
        let alert = NSAlert()
        alert.messageText = L10n.format("cpsmart {0} 已下载", [version])
        alert.informativeText = UpdateSupport.installationInstructions(
            installerOpened: installerOpened
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("退出 cpsmart"))
        alert.addButton(withTitle: L10n.tr("稍后"))
        if runModal(alert) == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("无法更新 cpsmart")
        alert.informativeText = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("好"))
        alert.addButton(withTitle: L10n.tr("打开 GitHub"))
        if runModal(alert) == .alertSecondButtonReturn {
            NSWorkspace.shared.open(Self.repositoryURL)
        }
    }

    @discardableResult
    private func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        let window = alert.window
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.contentView?.layoutSubtreeIfNeeded()
        if let screen = screenUnderMouse() {
            window.setFrame(
                UpdateSupport.centeredWindowFrame(
                    windowSize: window.frame.size,
                    visibleFrame: screen.visibleFrame
                ),
                display: false
            )
        }
        return alert.runModal()
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main
    }

    private func writeDiagnostic(_ message: String) {
        guard CommandLine.arguments.contains("--update-check-debug-log"),
              let data = "[cpsmart-update] \(message)\n".data(using: .utf8) else {
            return
        }
        try? FileHandle.standardOutput.write(contentsOf: data)
    }
}
