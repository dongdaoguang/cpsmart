import AppKit
import Carbon
import Foundation
#if canImport(cpsmart)
@testable import cpsmart
#endif

enum CoreTestSupport {
    private static let testDefaultsSuiteName = "cpsmartCoreTests-\(UUID().uuidString)"
    private static let testDefaults = UserDefaults(suiteName: testDefaultsSuiteName)!

    static func resetDefaults() {
        testDefaults.removePersistentDomain(forName: testDefaultsSuiteName)
    }

    static func runLegacySuite() throws {
        testDefaults.removePersistentDomain(forName: testDefaultsSuiteName)
        defer { testDefaults.removePersistentDomain(forName: testDefaultsSuiteName) }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cpsmartTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        try testDeduplication(in: temporaryDirectory)
        try testUsagePromotion(in: temporaryDirectory)
        try testPersistence(in: temporaryDirectory)
        try testLimits(in: temporaryDirectory)
        try testRemoveAndClear(in: temporaryDirectory)
        try testRangeSelection()
        try testDisplayGeometry()
        try testSearchFiltering()
        try testThumbnailProvider()
        try testLegacyHistoryCompatibility(in: temporaryDirectory)
        try testDeduplicationUsesLatestSourceApplication(in: temporaryDirectory)
        try testPinBehavior(in: temporaryDirectory)
        try testPinnedEntriesSurviveLimitsAndClear(in: temporaryDirectory)
        try testPinnedFieldLegacyCompatibility(in: temporaryDirectory)
        try testRetentionPreferences(in: temporaryDirectory)
        try testExpiredEntries(in: temporaryDirectory)
        try testAdaptivePreviewSizing()
        try testPreviewSessionAndQuickLookStore(in: temporaryDirectory)
        try testUpdateSupport()
        try testLocalization()
        try testShortcutDefaultsAndValidation()
        try testShortcutPersistenceAndReset()
        try testShortcutResetAndSwap()
        try testShortcutMatcherContexts()
        try testInvalidShortcutPersistenceFallsBackToDefaults()
        try testPinboardLifecycle(in: temporaryDirectory)
        try testPinboardEntryPersistence(in: temporaryDirectory)
        try testPinboardBatchOperations(in: temporaryDirectory)
        try testPinboardReordering(in: temporaryDirectory)
        try testPinboardNameValidation(in: temporaryDirectory)
        try testPinboardInteractionSupport()
    }

    static func runRangeSelection() throws { try testRangeSelection() }
    static func runDisplayGeometry() throws { try testDisplayGeometry() }
    static func runAdaptivePreviewSizing() throws { try testAdaptivePreviewSizing() }
    static func runPreviewSessionAndQuickLookStore(in directory: URL) throws {
        try testPreviewSessionAndQuickLookStore(in: directory)
    }
    static func runUpdateSupport() throws { try testUpdateSupport() }
    static func runLocalization() throws { try testLocalization() }
    static func runDeduplication(in directory: URL) throws { try testDeduplication(in: directory) }
    static func runUsagePromotion(in directory: URL) throws { try testUsagePromotion(in: directory) }
    static func runPinboardLifecycle(in directory: URL) throws { try testPinboardLifecycle(in: directory) }
    static func runPinboardEntryPersistence(in directory: URL) throws { try testPinboardEntryPersistence(in: directory) }
    static func runPinboardBatchOperations(in directory: URL) throws { try testPinboardBatchOperations(in: directory) }
    static func runPinboardNameValidation(in directory: URL) throws { try testPinboardNameValidation(in: directory) }
    static func runPinboardInteractionSupport() throws { try testPinboardInteractionSupport() }
    static func runPinboardReordering(in directory: URL) throws { try testPinboardReordering(in: directory) }
    static func runPersistence(in directory: URL) throws { try testPersistence(in: directory) }
    static func runLimits(in directory: URL) throws { try testLimits(in: directory) }
    static func runRemoveAndClear(in directory: URL) throws { try testRemoveAndClear(in: directory) }
    static func runSearchFiltering() throws { try testSearchFiltering() }
    static func runThumbnailProvider() throws { try testThumbnailProvider() }
    static func runLegacyHistoryCompatibility(in directory: URL) throws { try testLegacyHistoryCompatibility(in: directory) }
    static func runDeduplicationUsesLatestSourceApplication(in directory: URL) throws { try testDeduplicationUsesLatestSourceApplication(in: directory) }
    static func runPinBehavior(in directory: URL) throws { try testPinBehavior(in: directory) }
    static func runPinnedEntriesSurviveLimitsAndClear(in directory: URL) throws { try testPinnedEntriesSurviveLimitsAndClear(in: directory) }
    static func runPinnedFieldLegacyCompatibility(in directory: URL) throws { try testPinnedFieldLegacyCompatibility(in: directory) }
    static func runRetentionPreferences(in directory: URL) throws { try testRetentionPreferences(in: directory) }
    static func runExpiredEntries(in directory: URL) throws { try testExpiredEntries(in: directory) }
    static func runShortcutDefaultsAndValidation() throws { try testShortcutDefaultsAndValidation() }
    static func runShortcutPersistenceAndReset() throws { try testShortcutPersistenceAndReset() }
    static func runShortcutResetAndSwap() throws { try testShortcutResetAndSwap() }
    static func runShortcutMatcherContexts() throws { try testShortcutMatcherContexts() }
    static func runInvalidShortcutPersistenceFallsBackToDefaults() throws { try testInvalidShortcutPersistenceFallsBackToDefaults() }

    private static func testRangeSelection() throws {
        let ids = (0..<6).map { _ in UUID() }
        var state = HistorySelectionState<UUID>()
        try require(state.activeID == nil && state.selectedIDs.isEmpty, "selection did not start empty")

        try require(state.selectSingle(ids[2]), "single selection did not report a change")
        try require(
            state.activeID == ids[2]
                && state.anchorID == ids[2]
                && state.selectedIDs == [ids[2]],
            "single selection did not set active, anchor, and selected IDs"
        )

        state.extendSelection(to: ids[5], in: ids)
        try require(
            state.activeID == ids[5]
                && state.anchorID == ids[2]
                && state.selectedIDs == Set(ids[2...5]),
            "forward range selection did not preserve its anchor"
        )

        state.extendSelection(to: ids[1], in: ids)
        try require(
            state.activeID == ids[1]
                && state.anchorID == ids[2]
                && state.selectedIDs == Set(ids[1...2]),
            "reverse range selection did not shrink around the original anchor"
        )

        try require(state.toggle(ids[4], in: ids), "Command-click did not add a visible ID")
        try require(
            state.activeID == ids[4]
                && state.anchorID == ids[4]
                && state.selectedIDs == Set([ids[1], ids[2], ids[4]]),
            "Command-click add produced an invalid selection state"
        )
        try require(!state.toggle(ids[4], in: ids), "Command-click removal reported an addition")
        try require(
            state.activeID == ids[1]
                && state.selectedIDs == Set([ids[1], ids[2]]),
            "Command-click removal did not choose the first remaining visible item"
        )

        state.selectAll(in: ids)
        try require(
            state.activeID == ids[1]
                && state.selectedIDs == Set(ids)
                && state.anchorID == ids[4],
            "select all did not preserve the active item and valid anchor"
        )

        state.reconcile(with: [ids[0], ids[3], ids[5]], fallbackIndex: 1)
        try require(
            state.activeID == ids[0]
                && state.selectedIDs == Set([ids[0], ids[3], ids[5]])
                && state.anchorID == ids[0],
            "filter reconciliation did not retain visible selections in visible order"
        )

        state.reconcile(with: [ids[3], ids[5]], preferredID: ids[5], fallbackIndex: 0)
        try require(
            state.activeID == ids[5]
                && state.selectedIDs == [ids[5]]
                && state.anchorID == ids[5],
            "preferred selection did not collapse selection to the requested ID"
        )

        state.reconcile(with: [], fallbackIndex: 0)
        try require(
            state.activeID == nil && state.anchorID == nil && state.selectedIDs.isEmpty,
            "empty results did not clear selection state"
        )

        state.selectSingle(ids[3])
        try require(
            !state.toggle(ids[3], in: ids)
                && state.activeID == ids[3]
                && state.selectedIDs == [ids[3]],
            "Command-click removed the final selected item"
        )
        state.reconcile(with: [ids[5], ids[3]], fallbackIndex: 0)
        try require(
            state.activeID == ids[3] && state.selectedIDs == [ids[3]],
            "reordering visible results changed a retained active selection"
        )

        state.reset()
        state.reconcile(with: [ids[0], ids[1]], fallbackIndex: 99)
        try require(
            state.activeID == ids[1] && state.selectedIDs == [ids[1]],
            "selection fallback did not clamp an oversized index"
        )
        state.reset()
        state.reconcile(with: [ids[0], ids[1]], fallbackIndex: -4)
        try require(
            state.activeID == ids[0] && state.selectedIDs == [ids[0]],
            "selection fallback did not clamp a negative index"
        )

        state.replaceSelection(
            [ids[0]],
            activeID: ids[1],
            anchorID: ids[0],
            in: ids
        )
        try require(
            state.activeID == ids[1]
                && state.selectedIDs == Set([ids[0], ids[1]])
                && state.anchorID == ids[0],
            "replacement selection allowed the active item to fall outside the selection"
        )
    }

    private static func testDisplayGeometry() throws {
        let frames = [
            NSRect(x: 0, y: 0, width: 1512, height: 982),
            NSRect(x: -196, y: 982, width: 1920, height: 1080)
        ]
        try require(
            DisplayGeometry.screenIndex(
                containing: NSPoint(x: 756, y: 491),
                frames: frames
            ) == 0,
            "mouse location did not resolve to the main display"
        )
        try require(
            DisplayGeometry.screenIndex(
                containing: NSPoint(x: 764, y: 1522),
                frames: frames
            ) == 1,
            "mouse location did not resolve to the negative-origin secondary display"
        )
        let secondaryVisible = NSRect(x: -196, y: 982, width: 1920, height: 1055)
        try require(
            DisplayGeometry.historyFrame(visibleFrame: secondaryVisible, height: 248)
                == NSRect(x: -196, y: 982, width: 1920, height: 248),
            "history frame did not remain inside the secondary display visible frame"
        )
    }

    private static func testAdaptivePreviewSizing() throws {
        // 负坐标副屏不应改变尺寸计算；算法只能依赖相对边界。
        let primaryVisible = NSRect(x: 0, y: 0, width: 1440, height: 860)
        let secondaryVisible = NSRect(x: -1440, y: 120, width: 1440, height: 860)
        let primarySource = NSRect(x: 120, y: 130, width: 204, height: 150)
        let secondarySource = NSRect(x: -1320, y: 250, width: 204, height: 150)
        let primaryLimits = AdaptivePreviewSizing.limits(
            visibleFrame: primaryVisible,
            sourceFrame: primarySource
        )
        let secondaryLimits = AdaptivePreviewSizing.limits(
            visibleFrame: secondaryVisible,
            sourceFrame: secondarySource
        )
        try require(
            primaryLimits.maximumWidth == secondaryLimits.maximumWidth
                && primaryLimits.maximumHeight == secondaryLimits.maximumHeight,
            "adaptive preview sizing depended on the screen origin"
        )

        let font = NSFont.systemFont(ofSize: 13.5)
        let shortText = AdaptivePreviewSizing.textSize(
            for: "一小段文本",
            font: font,
            visibleFrame: primaryVisible,
            sourceFrame: primarySource
        )
        let longText = AdaptivePreviewSizing.textSize(
            for: Array(repeating: "这是一段需要滚动显示的长文本。", count: 180).joined(separator: "\n"),
            font: font,
            visibleFrame: primaryVisible,
            sourceFrame: primarySource
        )
        try require(
            shortText.width < longText.width && shortText.height < longText.height,
            "long text did not receive a larger preview than short text"
        )
        try require(
            longText.width <= primaryLimits.maximumWidth
                && longText.height <= primaryLimits.maximumHeight,
            "long text preview exceeded the screen-derived limits"
        )

        let naturalImage = AdaptivePreviewSizing.imageSize(
            pixelSize: NSSize(width: 490, height: 159),
            visibleFrame: primaryVisible,
            sourceFrame: primarySource
        )
        try require(
            naturalImage.width == 514 && naturalImage.height == 231,
            "small image was unexpectedly enlarged or distorted"
        )

        let largeImage = AdaptivePreviewSizing.imageSize(
            pixelSize: NSSize(width: 6000, height: 4000),
            visibleFrame: primaryVisible,
            sourceFrame: primarySource
        )
        try require(
            largeImage.width <= primaryLimits.maximumWidth
                && largeImage.height <= primaryLimits.maximumHeight,
            "large image preview exceeded the screen-derived limits"
        )

        let smallScreen = NSRect(x: 0, y: 0, width: 360, height: 420)
        let smallScreenSource = NSRect(x: 20, y: 40, width: 200, height: 120)
        let constrained = AdaptivePreviewSizing.textSize(
            for: String(repeating: "内容 ", count: 1_000),
            font: font,
            visibleFrame: smallScreen,
            sourceFrame: smallScreenSource
        )
        try require(
            constrained.width <= smallScreen.width - 48
                && constrained.height <= smallScreen.height - 48,
            "adaptive preview did not respect a small screen's safe bounds"
        )

        let secondaryQuickLookFrame = AdaptivePreviewSizing.centeredQuickLookFrame(
            panelSize: NSSize(width: 816, height: 816),
            visibleFrame: secondaryVisible
        )
        try require(
            secondaryVisible.insetBy(dx: 24, dy: 24).contains(secondaryQuickLookFrame),
            "Quick Look frame escaped the negative-origin secondary display"
        )
        try require(
            secondaryQuickLookFrame.midX == secondaryVisible.midX
                && secondaryQuickLookFrame.midY == secondaryVisible.midY,
            "Quick Look frame was not centered on the selected display"
        )
    }

    private static func testPreviewSessionAndQuickLookStore(in directory: URL) throws {
        var state = HistoryPreviewSessionState()
        try require(
            !state.isActive && state.presentation == .none,
            "preview session did not start inactive"
        )
        try require(state.start() && !state.start(), "preview session started more than once")
        state.recordAdaptiveShown()
        try require(
            state.isActive && state.presentation == .adaptive,
            "adaptive preview was not recorded"
        )
        state.recordPresentationClosed()
        try require(
            state.isActive && state.presentation == .none,
            "closing a presentation incorrectly ended its session"
        )
        state.recordQuickLookShown()
        try require(state.presentation == .quickLook, "Quick Look presentation was not recorded")
        state.recordUnavailable()
        try require(
            state.isActive && state.presentation == .unavailable,
            "unsupported content incorrectly ended its preview session"
        )
        state.end()
        state.recordAdaptiveShown()
        try require(
            !state.isActive && state.presentation == .none,
            "ended preview session accepted a new presentation"
        )

        let previewDirectory = directory.appendingPathComponent("quick-look", isDirectory: true)
        let store = QuickLookPreviewStore(directory: previewDirectory)
        let textEntry = ClipboardEntry(payload: .text("preview text"))
        let textURL = try requireValue(store.prepare(for: textEntry), "text preview was not written")
        let textData = try Data(contentsOf: textURL)
        try require(
            textURL.pathExtension == "txt" && textData == Data("preview text".utf8),
            "text Quick Look payload did not preserve its contents"
        )

        let imageEntry = ClipboardEntry(
            payload: .image(data: Data([0, 1, 2]), pasteboardType: "public.tiff")
        )
        let imageURL = try requireValue(store.prepare(for: imageEntry), "image preview was not written")
        let imageData = try Data(contentsOf: imageURL)
        try require(
            imageURL.pathExtension == "tiff" && imageData == Data([0, 1, 2]),
            "image Quick Look payload used the wrong extension or contents"
        )

        try require(
            store.prepare(for: ClipboardEntry(payload: .files(["/tmp/file"]))) == nil
                && store.previewURL == nil
                && !FileManager.default.fileExists(atPath: previewDirectory.path),
            "unsupported file preview left temporary resources behind"
        )
    }

    private static func testUpdateSupport() throws {
        let current = try requireValue(AppVersion("1.9.0"), "current version was not parsed")
        let newer = try requireValue(AppVersion("v1.10.0"), "release tag was not parsed")
        let equivalent = try requireValue(AppVersion("1.9"), "short version was not parsed")
        try require(current < newer, "semantic version comparison used string ordering")
        try require(current == equivalent, "equivalent versions compared as different")
        try require(AppVersion("1.8-beta") == nil, "prerelease version was accepted")

        let openedInstructions = UpdateSupport.installationInstructions(installerOpened: true)
        let savedInstructions = UpdateSupport.installationInstructions(installerOpened: false)
        try require(
            openedInstructions.contains(L10n.tr("安装镜像已经打开。"))
                && openedInstructions.contains("1.")
                && openedInstructions.contains("/Applications/cpsmart.app"),
            "downloaded update instructions did not explain installation and optional permission repair"
        )
        try require(
            savedInstructions.contains(L10n.tr("安装包已保存到“下载”文件夹，请先打开它。")),
            "saved installer instructions did not explain how to open the DMG"
        )
        try require(
            AccessibilityPermissionSupport.resetArguments(
                bundleIdentifier: "com.cpsmart.app"
            ) == ["reset", "Accessibility", "com.cpsmart.app"],
            "Accessibility repair could reset more than the current cpsmart bundle"
        )

        let officialAsset = GitHubReleaseAsset(
            name: "cpsmart-1.10.0-universal.dmg",
            browserDownloadURL: URL(
                string: "https://github.com/dongdaoguang/cpsmart/releases/download/v1.10.0/cpsmart-1.10.0-universal.dmg"
            )!
        )
        let release = try requireValue(
            GitHubRelease(
                latestReleaseURL: URL(
                    string: "https://github.com/dongdaoguang/cpsmart/releases/tag/v1.10.0"
                )!
            ),
            "official latest-release redirect was not parsed"
        )
        try require(
            release.installerAsset == officialAsset,
            "universal installer URL was not derived from the release tag"
        )
        try require(
            UpdateSupport.isTrustedReleaseDownloadURL(officialAsset.browserDownloadURL),
            "official GitHub Release URL was rejected"
        )
        try require(
            !UpdateSupport.isTrustedReleaseDownloadURL(URL(string: "https://example.com/source.dmg")!),
            "untrusted update host was accepted"
        )
        try require(
            GitHubRelease(latestReleaseURL: URL(string: "https://example.com/releases/tag/v9.0.0")!) == nil,
            "untrusted latest-release redirect was accepted"
        )
        try require(
            GitHubRelease(
                latestReleaseURL: URL(
                    string: "https://github.com/dongdaoguang/cpsmart/releases/tag/archive/v9.0.0"
                )!
            ) == nil,
            "nested release path was accepted as a version tag"
        )

        let negativeOriginVisibleFrame = NSRect(x: -1512, y: 80, width: 1512, height: 900)
        let alertFrame = UpdateSupport.centeredWindowFrame(
            windowSize: NSSize(width: 520, height: 260),
            visibleFrame: negativeOriginVisibleFrame
        )
        try require(
            negativeOriginVisibleFrame.contains(alertFrame),
            "update alert escaped a negative-origin secondary display"
        )
        try require(
            alertFrame.midX == negativeOriginVisibleFrame.midX
                && alertFrame.midY == negativeOriginVisibleFrame.midY,
            "update alert was not centered on the selected display"
        )
    }

    private static func testLocalization() throws {
        try require(L10n.tr("全部", language: "en") == "All", "English resource was not loaded")
        try require(L10n.tr("全部", language: "zh-Hans") == "全部", "Chinese resource was not loaded")
        try require(
            L10n.format("在“{0}”中搜索", ["Notes {0}"], language: "en") == "Search in “Notes {0}”",
            "format argument was altered or not translated"
        )
        try require(
            L10n.tr("accessibility.repairInstructions", language: "en").contains("/Applications/cpsmart.app"),
            "English permission repair instructions are missing"
        )
    }

    private static func testDeduplication(in directory: URL) throws {
        let URL = directory.appendingPathComponent("deduplication.json")
        let store = HistoryStore(fileURL: URL, userDefaults: testDefaults)
        store.add(.text("first"), at: Date(timeIntervalSince1970: 1))
        store.add(.text("second"), at: Date(timeIntervalSince1970: 2))
        store.add(.text("first"), at: Date(timeIntervalSince1970: 3))

        try require(store.entries.count == 2, "duplicate entry was not removed")
        try require(
            store.entries.map(\.payload) == [.text("first"), .text("second")],
            "duplicate entry was not promoted"
        )
        try require(
            store.entries.first?.createdAt == Date(timeIntervalSince1970: 3),
            "promoted entry timestamp was not refreshed"
        )
    }

    private static func testUsagePromotion(in directory: URL) throws {
        let URL = directory.appendingPathComponent("usage-promotion.json")
        var currentDate = Date(timeIntervalSince1970: 4)
        let store = HistoryStore(
            fileURL: URL,
            maximumEntryCount: 20,
            maximumStorageBytes: 10_000,
            userDefaults: testDefaults,
            now: { currentDate }
        )
        let oldest = store.add(
            .text("oldest"),
            sourceAppName: "Terminal",
            sourceAppBundleID: "com.apple.Terminal",
            at: Date(timeIntervalSince1970: 1)
        )
        let middle = store.add(.text("middle"), at: Date(timeIntervalSince1970: 2))
        store.add(.text("newest"), at: Date(timeIntervalSince1970: 3))

        try require(store.promote(id: oldest.id), "existing history entry was not promoted")
        try require(
            store.entries.map(\.payload) == [
                .text("oldest"),
                .text("newest"),
                .text("middle")
            ],
            "used history entry did not become the most recently used item"
        )
        try require(
            store.entries.first?.id == oldest.id
                && store.entries.first?.createdAt == Date(timeIntervalSince1970: 1)
                && store.entries.first?.lastUsedAt == currentDate
                && store.entries.first?.sourceAppName == "Terminal"
                && store.entries.first?.sourceAppBundleID == "com.apple.Terminal",
            "usage promotion did not preserve copy metadata or record the usage time"
        )

        currentDate = Date(timeIntervalSince1970: 5)
        try require(store.promote(id: middle.id), "second history entry was not promoted")
        try require(
            store.entries.map(\.payload) == [
                .text("middle"),
                .text("oldest"),
                .text("newest")
            ],
            "repeated usage did not maintain LRU ordering"
        )

        let beforeMissingPromotion = store.entries
        try require(
            !store.promote(id: UUID()) && store.entries == beforeMissingPromotion,
            "unknown entry was inserted into recent history during promotion"
        )

        let reloaded = HistoryStore(
            fileURL: URL,
            maximumEntryCount: 20,
            maximumStorageBytes: 10_000,
            userDefaults: testDefaults
        )
        try require(
            reloaded.entries.map(\.payload) == [
                .text("middle"),
                .text("oldest"),
                .text("newest")
            ] && reloaded.entries.first?.lastUsedAt == currentDate,
            "LRU ordering did not persist after reload"
        )

        var evictionDate = Date(timeIntervalSince1970: 4)
        let evictionStore = HistoryStore(
            fileURL: directory.appendingPathComponent("usage-promotion-eviction.json"),
            maximumEntryCount: 3,
            maximumStorageBytes: 10_000,
            userDefaults: testDefaults,
            now: { evictionDate }
        )
        let evictionOldest = evictionStore.add(
            .text("oldest"),
            at: Date(timeIntervalSince1970: 1)
        )
        evictionStore.add(.text("least recently used"), at: Date(timeIntervalSince1970: 2))
        evictionStore.add(.text("newest"), at: Date(timeIntervalSince1970: 3))
        try require(
            evictionStore.promote(id: evictionOldest.id),
            "entry could not be marked as recently used before eviction"
        )
        evictionDate = Date(timeIntervalSince1970: 5)
        evictionStore.add(.text("incoming"), at: evictionDate)
        try require(
            evictionStore.entries.map(\.payload) == [
                .text("incoming"),
                .text("oldest"),
                .text("newest")
            ],
            "entry limit did not evict the least recently used history item"
        )
    }

    private static func testPinboardLifecycle(in directory: URL) throws {
        let URL = directory.appendingPathComponent("pinboard-lifecycle.json")
        let store = PinboardStore(fileURL: URL)
        let board = try requireValue(
            store.create(name: " 常用命令 ", color: .red),
            "valid pinboard was not created"
        )
        try require(board.name == "常用命令", "pinboard name was not trimmed")

        try require(store.rename(id: board.id, to: "开发命令"), "pinboard was not renamed")
        store.setColor(id: board.id, color: .blue)

        let reloaded = PinboardStore(fileURL: URL)
        try require(
            reloaded.boards.first?.name == "开发命令"
                && reloaded.boards.first?.color == .blue,
            "pinboard metadata did not persist"
        )

        reloaded.removeBoard(id: board.id)
        try require(
            PinboardStore(fileURL: URL).boards.isEmpty,
            "deleted pinboard was restored after reload"
        )
    }

    private static func testPinboardEntryPersistence(in directory: URL) throws {
        let URL = directory.appendingPathComponent("pinboard-entries.json")
        let store = PinboardStore(fileURL: URL)
        let board = try requireValue(
            store.create(name: "回复", color: .green),
            "pinboard was not created"
        )
        let historyEntry = ClipboardEntry(
            payload: .text("常用回复"),
            createdAt: Date(timeIntervalSince1970: 1),
            sourceAppName: "备忘录",
            sourceAppBundleID: "com.apple.Notes",
            isPinned: true
        )
        let firstFavorite = try requireValue(
            store.add(historyEntry, to: board.id),
            "history entry was not added to pinboard"
        )
        try require(firstFavorite.id != historyEntry.id, "pinboard did not create an independent snapshot")
        try require(firstFavorite.isPinned != true, "history pin state leaked into pinboard")

        let duplicateFavorite = store.add(historyEntry, to: board.id)
        try require(
            store.boards.first?.entries.count == 1,
            "adding the same payload created duplicate favorites"
        )
        try require(
            duplicateFavorite?.id == firstFavorite.id,
            "adding an existing favorite replaced or reordered its snapshot"
        )

        let reloaded = PinboardStore(fileURL: URL)
        let reloadedEntry = try requireValue(
            reloaded.boards.first?.entries.first,
            "pinboard entry did not persist"
        )
        try require(
            reloadedEntry.payload == historyEntry.payload
                && reloadedEntry.sourceAppBundleID == historyEntry.sourceAppBundleID,
            "pinboard snapshot lost payload or source metadata"
        )

        reloaded.removeEntry(id: reloadedEntry.id, from: board.id)
        try require(
            PinboardStore(fileURL: URL).boards.first?.entries.isEmpty == true,
            "removed favorite was restored after reload"
        )
    }

    private static func testPinboardBatchOperations(in directory: URL) throws {
        let URL = directory.appendingPathComponent("pinboard-batch.json")
        let store = PinboardStore(fileURL: URL)
        let board = try requireValue(
            store.create(name: "批量收藏", color: .blue),
            "batch pinboard was not created"
        )
        let one = ClipboardEntry(payload: .text("one"))
        let two = ClipboardEntry(payload: .text("two"))
        let duplicateOne = ClipboardEntry(payload: .text("one"))
        try require(
            store.add([one, two, duplicateOne], to: board.id) == 2,
            "batch add did not report the number of unique favorites"
        )
        try require(
            store.boards.first?.entries.map(\.payload) == [.text("one"), .text("two")],
            "batch add did not preserve the visible selection order"
        )

        let storedEntries = try requireValue(
            store.boards.first?.entries,
            "batch favorites disappeared before removal"
        )
        let removed = store.removeEntries(ids: Set(storedEntries.map(\.id)), from: board.id)
        try require(
            PinboardStore(fileURL: URL).boards.first?.entries.isEmpty == true,
            "batch favorite removal did not persist"
        )
        try require(removed.map(\.index) == [0, 1], "removed favorite indexes were not captured")
        try require(
            store.restoreEntries(removed, to: board.id) == 2,
            "batch favorite undo did not restore every entry"
        )
        let restored = try requireValue(
            PinboardStore(fileURL: URL).boards.first?.entries,
            "restored batch favorites did not persist"
        )
        try require(
            restored.map(\.id) == storedEntries.map(\.id)
                && restored.map(\.payload) == [.text("one"), .text("two")],
            "favorite undo did not preserve identity and order"
        )
    }

    private static func testPinboardNameValidation(in directory: URL) throws {
        let URL = directory.appendingPathComponent("pinboard-name-validation.json")
        let store = PinboardStore(fileURL: URL)
        try require(
            store.create(name: " \n ", color: .gray) == nil,
            "blank pinboard name was accepted"
        )
        let longName = String(repeating: "名", count: 40)
        let board = try requireValue(
            store.create(name: longName, color: .purple),
            "long pinboard name was rejected instead of normalized"
        )
        try require(board.name.count == 30, "long pinboard name was not capped at 30 characters")
        try require(
            !store.rename(id: board.id, to: "   "),
            "blank pinboard rename was accepted"
        )
    }

    private static func testPinboardInteractionSupport() throws {
        let firstEntry = ClipboardEntry(payload: .text("first"))
        let duplicateEntry = ClipboardEntry(payload: .text("first"))
        let secondEntry = ClipboardEntry(payload: .text("second"))
        let board = Pinboard(name: "Board", color: .blue, entries: [firstEntry])
        let anotherBoard = Pinboard(name: "Another", color: .green)

        var source = PinboardSourceState()
        try require(source.isHistory, "pinboard source did not start at recent history")
        try require(
            source.selectPinboard(board.id, from: [board, anotherBoard]) == board
                && source.selectedPinboardID == board.id,
            "valid pinboard source was not selected"
        )
        try require(
            source.reconcile(with: [board]) == board,
            "selected pinboard did not survive a metadata refresh"
        )
        try require(
            source.reconcile(with: [anotherBoard]) == nil && source.isHistory,
            "deleted pinboard source did not fall back to recent history"
        )

        try require(
            PinboardInteractionSupport.normalizedName("  常用命令  ") == "常用命令"
                && PinboardInteractionSupport.normalizedName("  \n ") == nil
                && PinboardInteractionSupport.normalizedName(String(repeating: "名", count: 40))?.count == 30,
            "pinboard name normalization did not trim, reject blank, or cap length"
        )
        try require(
            PinboardInteractionSupport.addedCount(
                entries: [duplicateEntry, secondEntry],
                to: board
            ) == 1,
            "pinboard addition count did not ignore an existing payload"
        )
        let directSourceKeys = [
            UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3),
            UInt16(kVK_ANSI_4), UInt16(kVK_ANSI_5), UInt16(kVK_ANSI_6),
            UInt16(kVK_ANSI_7), UInt16(kVK_ANSI_8), UInt16(kVK_ANSI_9)
        ]
        try require(
            directSourceKeys.enumerated().allSatisfy { index, keyCode in
                PinboardShortcutRouting.command(
                    keyCode: keyCode,
                    modifiers: [.command, .option]
                ) == .selectSource(index: index)
            },
            "direct pinboard shortcuts did not map 1...9 to recent and the first eight boards"
        )
        try require(
            PinboardShortcutRouting.command(
                keyCode: UInt16(kVK_Tab),
                modifiers: [.control]
            ) == .cycle(offset: 1)
                && PinboardShortcutRouting.command(
                    keyCode: UInt16(kVK_Tab),
                    modifiers: [.control, .shift]
                ) == .cycle(offset: -1),
            "pinboard cycle shortcuts did not distinguish forward and backward navigation"
        )
        try require(
            PinboardShortcutRouting.command(
                keyCode: UInt16(kVK_ANSI_2),
                modifiers: [.command]
            ) == nil
                && PinboardShortcutRouting.command(
                    keyCode: UInt16(kVK_ANSI_2),
                    modifiers: [.command, .option, .shift]
                ) == nil
                && PinboardShortcutRouting.command(
                    keyCode: UInt16(kVK_Tab),
                    modifiers: []
                ) == nil,
            "pinboard shortcut routing captured unrelated or extra-modifier key presses"
        )
        try require(
            PinboardShortcutRouting.cycledSourceIndex(
                currentIndex: 0,
                sourceCount: 3,
                offset: -1
            ) == 2
                && PinboardShortcutRouting.cycledSourceIndex(
                    currentIndex: 2,
                    sourceCount: 3,
                    offset: 1
                ) == 0
                && PinboardShortcutRouting.cycledSourceIndex(
                    currentIndex: 0,
                    sourceCount: 0,
                    offset: 1
                ) == nil,
            "pinboard cycling did not wrap or reject an empty source list"
        )
        try require(
            PinboardInteractionSupport.boardID(from: board.id.uuidString) == board.id
                && PinboardInteractionSupport.boardID(from: "invalid") == nil,
            "pinboard menu ID parsing accepted an invalid value"
        )
        let colorValue = "\(board.id.uuidString)|\(PinboardColor.purple.rawValue)"
        let parsedColor = PinboardInteractionSupport.boardColor(from: colorValue)
        try require(
            parsedColor?.0 == board.id && parsedColor?.1 == .purple,
            "pinboard menu color value was not parsed"
        )

        let descriptor = PinboardDragDescriptor(
            entryID: secondEntry.id,
            sourcePinboardID: board.id
        )
        let pasteboard = NSPasteboard(name: .init("cpsmart-tests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects([descriptor.pasteboardItem()])
        try require(
            PinboardDragDescriptor.read(from: pasteboard) == descriptor,
            "pinboard drag descriptor did not survive pasteboard serialization"
        )
        try require(
            PinboardDragRules.sourceOperation(sourcePinboardID: nil) == .copy
                && PinboardDragRules.sourceOperation(sourcePinboardID: board.id) == .move,
            "pinboard drag source operation did not distinguish copy and move"
        )
        try require(
            PinboardDragRules.canBeginDrag(
                selectedItemCount: 1,
                itemIsVisible: true,
                sourcePinboardID: nil,
                allowsPinboardReordering: false
            ),
            "history drag was incorrectly disabled by a filter"
        )
        try require(
            !PinboardDragRules.canBeginDrag(
                selectedItemCount: 1,
                itemIsVisible: true,
                sourcePinboardID: board.id,
                allowsPinboardReordering: false
            ),
            "filtered pinboard drag incorrectly allowed reordering"
        )
        try require(
            PinboardDragRules.reorderDescriptor(
                from: pasteboard,
                targetPinboardID: board.id,
                allowsPinboardReordering: true
            ) == descriptor
                && PinboardDragRules.reorderDescriptor(
                    from: pasteboard,
                    targetPinboardID: anotherBoard.id,
                    allowsPinboardReordering: true
                ) == nil,
            "pinboard reorder rules accepted a cross-board drag"
        )
    }

    private static func testPinboardReordering(in directory: URL) throws {
        let URL = directory.appendingPathComponent("pinboard-reordering.json")
        let store = PinboardStore(fileURL: URL)
        let board = try requireValue(
            store.create(name: "有序命令", color: .orange),
            "pinboard was not created"
        )
        store.add(ClipboardEntry(payload: .text("one")), to: board.id)
        store.add(ClipboardEntry(payload: .text("two")), to: board.id)
        let three = try requireValue(
            store.add(ClipboardEntry(payload: .text("three")), to: board.id),
            "third pinboard entry was not added"
        )
        try require(
            store.boards.first?.entries.map(\.payload) == [
                .text("three"), .text("two"), .text("one")
            ],
            "pinboard seed order was unexpected"
        )

        store.moveEntry(id: three.id, toInsertionIndex: 3, in: board.id)
        try require(
            store.boards.first?.entries.map(\.payload) == [
                .text("two"), .text("one"), .text("three")
            ],
            "moving a favorite to the end used the wrong insertion index"
        )
        try require(
            PinboardStore(fileURL: URL).boards.first?.entries.map(\.payload) == [
                .text("two"), .text("one"), .text("three")
            ],
            "reordered favorites did not persist"
        )

        store.moveEntry(id: three.id, toInsertionIndex: 0, in: board.id)
        try require(
            store.boards.first?.entries.map(\.payload) == [
                .text("three"), .text("two"), .text("one")
            ],
            "moving a favorite to the beginning failed"
        )
    }

    private static func testPersistence(in directory: URL) throws {
        let URL = directory.appendingPathComponent("persistence.json")
        let store = HistoryStore(fileURL: URL, userDefaults: testDefaults)
        store.add(.text("hello"))
        store.add(.image(data: Data([1, 2, 3]), pasteboardType: "public.png"))
        store.add(.files(["/tmp/a.txt", "/tmp/b.txt"]))

        let reloaded = HistoryStore(fileURL: URL, userDefaults: testDefaults)
        try require(
            reloaded.entries.map(\.payload) == store.entries.map(\.payload),
            "supported payloads did not round-trip"
        )
    }

    private static func testLimits(in directory: URL) throws {
        let countURL = directory.appendingPathComponent("count-limit.json")
        let countLimited = HistoryStore(
            fileURL: countURL,
            maximumEntryCount: 2,
            maximumStorageBytes: 100,
            userDefaults: testDefaults
        )
        countLimited.add(.text("one"))
        countLimited.add(.text("two"))
        countLimited.add(.text("three"))
        try require(
            countLimited.entries.map(\.payload) == [.text("three"), .text("two")],
            "entry count limit did not discard the oldest entry"
        )

        let sizeURL = directory.appendingPathComponent("size-limit.json")
        let sizeLimited = HistoryStore(
            fileURL: sizeURL,
            maximumEntryCount: 10,
            maximumStorageBytes: 5,
            userDefaults: testDefaults
        )
        sizeLimited.add(.text("1234"))
        sizeLimited.add(.text("abc"))
        try require(
            sizeLimited.entries.map(\.payload) == [.text("abc")],
            "storage limit did not discard the oldest entry"
        )
    }

    private static func testRemoveAndClear(in directory: URL) throws {
        let URL = directory.appendingPathComponent("remove-clear.json")
        let store = HistoryStore(fileURL: URL, userDefaults: testDefaults)
        let removable = store.add(.text("remove"))
        store.add(.text("keep"))
        store.remove(id: removable.id)
        try require(
            HistoryStore(fileURL: URL, userDefaults: testDefaults).entries.map(\.payload)
                == [.text("keep")],
            "removed entry was restored after reload"
        )

        let firstBatchEntry = store.add(.text("batch-one"))
        let secondBatchEntry = store.add(.text("batch-two"))
        let removed = store.remove(ids: [firstBatchEntry.id, secondBatchEntry.id])
        try require(
            HistoryStore(fileURL: URL, userDefaults: testDefaults).entries.map(\.payload)
                == [.text("keep")],
            "batch history removal did not persist"
        )
        store.restore(removed)
        let restoredIDs = HistoryStore(fileURL: URL, userDefaults: testDefaults).entries.map(\.id)
        try require(
            restoredIDs.contains(firstBatchEntry.id) && restoredIDs.contains(secondBatchEntry.id),
            "history undo did not restore the original entry identities"
        )

        store.clear()
        try require(
            HistoryStore(fileURL: URL, userDefaults: testDefaults).entries.isEmpty,
            "cleared history was restored after reload"
        )
    }

    private static func testSearchFiltering() throws {
        let quickFox = ClipboardEntry(payload: .text("The Quick Brown Fox"))
        let quickDog = ClipboardEntry(payload: .text("The quick brown dog"))
        let accented = ClipboardEntry(payload: .text("Résumé ABC"))
        let chinese = ClipboardEntry(payload: .text("你好，剪贴板"))
        let image = ClipboardEntry(
            payload: .image(data: Data([1]), pasteboardType: "public.png")
        )
        let file = ClipboardEntry(payload: .files(["/tmp/reports/年度总结.pdf"]))
        let entries = [quickFox, quickDog, accented, chinese, image, file]

        try require(
            SearchFilter.filter(entries, query: " \n\t ") == entries,
            "blank search query did not return the original entries"
        )
        try require(
            SearchFilter.filter(entries, query: "quick fox") == [quickFox],
            "multiple search terms were not combined with AND"
        )
        try require(
            SearchFilter.filter(entries, query: "résumé abc") == [accented],
            "case-insensitive search did not match"
        )
        try require(
            SearchFilter.filter(entries, query: "resume ＡＢＣ") == [accented],
            "diacritic- or width-insensitive search did not match"
        )
        try require(
            SearchFilter.filter(entries, query: "剪贴板") == [chinese],
            "Chinese search text did not match"
        )
        try require(
            SearchFilter.filter(entries, query: "图片") == [image]
                && SearchFilter.filter(entries, query: "IMAGE") == [image],
            "image entries were not searchable by their Chinese and English labels"
        )
        try require(
            SearchFilter.filter(entries, query: "年度总结.pdf") == [file],
            "file name search did not match its path"
        )

        var state = HistoryFilterState()
        try require(
            !state.isFiltering
                && state.allowsPinboardReordering
                && state.apply(to: entries) == entries,
            "default filter state unexpectedly filtered or disabled reordering"
        )
        state.updateQuery("quick")
        state.updateType(rawValue: HistoryContentTypeFilter.text.rawValue)
        try require(
            state.isFiltering
                && !state.allowsPinboardReordering
                && state.apply(to: entries) == [quickFox, quickDog],
            "query and type filters were not composed"
        )
        state.updateType(rawValue: HistoryContentTypeFilter.image.rawValue)
        try require(
            state.apply(to: entries).isEmpty,
            "type filter ignored the active query"
        )
        state.updateType(rawValue: 999)
        try require(
            state.type == .all && state.apply(to: entries) == [quickFox, quickDog],
            "invalid filter segment did not fall back to all types"
        )
        state.reset()
        try require(
            state == HistoryFilterState(),
            "reset did not restore the default query and type filter"
        )
    }

    private static func testThumbnailProvider() throws {
        let provider = ThumbnailProvider()
        let imageEntry = ClipboardEntry(
            payload: .image(data: try makePNGData(), pasteboardType: "public.png")
        )

        let first = try waitForThumbnail(from: provider, entry: imageEntry)
        try require(first != nil, "generated PNG did not produce a thumbnail")
        if let first {
            try require(
                max(first.size.width, first.size.height) <= 480,
                "thumbnail exceeded the configured maximum pixel size"
            )
        }

        let second = try waitForThumbnail(from: provider, entry: imageEntry)
        try require(first === second, "second thumbnail request did not return the cached image")

        let textResult = try waitForThumbnail(
            from: provider,
            entry: ClipboardEntry(payload: .text("not an image"))
        )
        try require(textResult == nil, "non-image entry unexpectedly produced a thumbnail")
    }

    private static func testLegacyHistoryCompatibility(in directory: URL) throws {
        let URL = directory.appendingPathComponent("legacy-history.json")
        let legacyEntry = LegacyClipboardEntry(
            id: UUID(),
            payload: .text("legacy"),
            createdAt: Date(timeIntervalSince1970: 123)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([legacyEntry]).write(to: URL)

        let reloaded = HistoryStore(fileURL: URL, userDefaults: testDefaults)
        try require(reloaded.entries.count == 1, "old history JSON could not be decoded")
        try require(
            reloaded.entries.first?.sourceAppName == nil
                && reloaded.entries.first?.sourceAppBundleID == nil
                && reloaded.entries.first?.lastUsedAt == nil,
            "missing optional history fields did not decode as nil"
        )
    }

    private static func testDeduplicationUsesLatestSourceApplication(in directory: URL) throws {
        let URL = directory.appendingPathComponent("source-application-deduplication.json")
        let store = HistoryStore(fileURL: URL, userDefaults: testDefaults)
        store.add(
            .text("same payload"),
            sourceAppName: "Old App",
            sourceAppBundleID: "com.example.old",
            at: Date(timeIntervalSince1970: 1)
        )
        store.add(
            .text("same payload"),
            sourceAppName: "New App",
            sourceAppBundleID: "com.example.new",
            at: Date(timeIntervalSince1970: 2)
        )

        try require(store.entries.count == 1, "source application changed payload deduplication")
        try require(
            store.entries.first?.sourceAppName == "New App"
                && store.entries.first?.sourceAppBundleID == "com.example.new",
            "deduplicated entry did not keep the latest source application"
        )

        let reloaded = HistoryStore(fileURL: URL, userDefaults: testDefaults)
        try require(
            reloaded.entries.first?.sourceAppName == "New App"
                && reloaded.entries.first?.sourceAppBundleID == "com.example.new",
            "source application fields did not persist"
        )
    }

    private static func testPinBehavior(in directory: URL) throws {
        let URL = directory.appendingPathComponent("pin-behavior.json")
        let store = HistoryStore(
            fileURL: URL,
            maximumEntryCount: 20,
            maximumStorageBytes: 10_000,
            userDefaults: testDefaults
        )
        let oldest = store.add(.text("oldest"), at: Date(timeIntervalSince1970: 1))
        let middle = store.add(.text("middle"), at: Date(timeIntervalSince1970: 2))
        store.add(.text("newest"), at: Date(timeIntervalSince1970: 3))

        store.togglePin(id: oldest.id)
        store.togglePin(id: middle.id)
        try require(
            store.entries.map(\.payload) == [
                .text("middle"),
                .text("oldest"),
                .text("newest")
            ],
            "pinned and unpinned groups were not sorted newest-first"
        )

        store.add(
            .text("oldest"),
            sourceAppName: "Latest Source",
            sourceAppBundleID: "com.example.latest",
            at: Date(timeIntervalSince1970: 4)
        )
        try require(store.entries.count == 3, "pin state changed payload deduplication")
        try require(
            store.entries.first?.payload == .text("oldest")
                && store.entries.first?.isPinned == true,
            "deduplicated entry did not inherit pin state"
        )
        try require(
            store.entries.first?.sourceAppBundleID == "com.example.latest",
            "deduplicated pinned entry did not keep the latest source application"
        )

        let unpinnedNewest = store.entries.first(where: { $0.payload == .text("newest") })!
        store.promote(id: unpinnedNewest.id)
        try require(
            store.entries.first?.isPinned == true
                && store.entries.first(where: { $0.isPinned != true })?.payload == .text("newest"),
            "LRU promotion moved an unpinned entry ahead of the pinned group"
        )
    }

    private static func testPinnedEntriesSurviveLimitsAndClear(in directory: URL) throws {
        let countURL = directory.appendingPathComponent("pinned-count-limit.json")
        let countLimited = HistoryStore(
            fileURL: countURL,
            maximumEntryCount: 2,
            maximumStorageBytes: 10_000,
            userDefaults: testDefaults
        )
        let pinned = countLimited.add(.text("pinned"), at: Date(timeIntervalSince1970: 1))
        countLimited.togglePin(id: pinned.id)
        countLimited.add(.text("discarded"), at: Date(timeIntervalSince1970: 2))
        countLimited.add(.text("retained"), at: Date(timeIntervalSince1970: 3))
        try require(
            countLimited.entries.map(\.payload) == [.text("pinned"), .text("retained")],
            "entry count limit evicted a pinned entry"
        )

        let sizeURL = directory.appendingPathComponent("pinned-size-limit.json")
        let sizeLimited = HistoryStore(
            fileURL: sizeURL,
            maximumEntryCount: 10,
            maximumStorageBytes: 5,
            userDefaults: testDefaults
        )
        let sizePinned = sizeLimited.add(.text("1234"))
        sizeLimited.togglePin(id: sizePinned.id)
        sizeLimited.add(.text("abcd"))
        try require(
            sizeLimited.entries.map(\.payload) == [.text("1234")],
            "storage limit evicted a pinned entry"
        )

        countLimited.clear()
        try require(
            countLimited.entries.map(\.payload) == [.text("pinned")],
            "clear removed a pinned entry"
        )
        countLimited.clearAll()
        try require(countLimited.entries.isEmpty, "clearAll did not remove pinned entries")
    }

    private static func testPinnedFieldLegacyCompatibility(in directory: URL) throws {
        let URL = directory.appendingPathComponent("legacy-without-pin.json")
        let legacyEntry = LegacyClipboardEntryWithSource(
            id: UUID(),
            payload: .text("legacy pin"),
            createdAt: Date(timeIntervalSince1970: 456),
            sourceAppName: "Legacy App",
            sourceAppBundleID: "com.example.legacy"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([legacyEntry]).write(to: URL)

        let reloaded = HistoryStore(
            fileURL: URL,
            maximumEntryCount: 20,
            maximumStorageBytes: 10_000,
            userDefaults: testDefaults
        )
        try require(reloaded.entries.count == 1, "history JSON without isPinned did not decode")
        try require(
            reloaded.entries.first?.isPinned == nil
                && reloaded.entries.first?.lastUsedAt == nil,
            "missing pin and usage fields did not decode as nil"
        )
    }

    private static func testRetentionPreferences(in directory: URL) throws {
        let defaultSuiteName = "cpsmartTests-retentionDefaults-\(UUID().uuidString)"
        let defaultSettings = UserDefaults(suiteName: defaultSuiteName)!
        defer { defaultSettings.removePersistentDomain(forName: defaultSuiteName) }

        let defaultStore = HistoryStore(
            fileURL: directory.appendingPathComponent("retention-defaults.json"),
            userDefaults: defaultSettings
        )
        try require(
            defaultStore.maximumEntryCount == 200
                && defaultStore.maximumStorageBytes == 25 * 1_024 * 1_024
                && defaultStore.keepDays == 0,
            "retention defaults no longer match the previous behavior"
        )
        defaultStore.add(.text("old but unlimited"), at: Date(timeIntervalSince1970: 1))
        try require(
            defaultStore.entries.count == 1,
            "default unlimited retention removed an old entry"
        )

        let customSuiteName = "cpsmartTests-retentionCustom-\(UUID().uuidString)"
        let customSettings = UserDefaults(suiteName: customSuiteName)!
        defer { customSettings.removePersistentDomain(forName: customSuiteName) }
        customSettings.set(2, forKey: "maximumEntryCount")
        customSettings.set(1, forKey: "maximumStorageMB")
        customSettings.set(0, forKey: "keepDays")

        let countLimited = HistoryStore(
            fileURL: directory.appendingPathComponent("retention-custom-count.json"),
            userDefaults: customSettings
        )
        countLimited.add(.text("one"))
        countLimited.add(.text("two"))
        countLimited.add(.text("three"))
        try require(
            countLimited.entries.map(\.payload) == [.text("three"), .text("two")],
            "UserDefaults maximumEntryCount was not applied"
        )
        try require(
            countLimited.maximumStorageBytes == 1 * 1_024 * 1_024,
            "UserDefaults maximumStorageMB was not converted to bytes"
        )

        customSettings.set(10, forKey: "maximumEntryCount")
        let sizeLimited = HistoryStore(
            fileURL: directory.appendingPathComponent("retention-custom-size.json"),
            userDefaults: customSettings
        )
        sizeLimited.add(.image(
            data: Data(repeating: 1, count: 700_000),
            pasteboardType: "public.png"
        ))
        sizeLimited.add(.image(
            data: Data(repeating: 2, count: 700_000),
            pasteboardType: "public.png"
        ))
        try require(sizeLimited.entries.count == 1, "UserDefaults storage limit was not applied")
    }

    private static func testExpiredEntries(in directory: URL) throws {
        let referenceDate = Date(timeIntervalSince1970: 100 * 24 * 60 * 60)
        let suiteName = "cpsmartTests-expiration-\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        defer { settings.removePersistentDomain(forName: suiteName) }
        settings.set(7, forKey: "keepDays")

        let store = HistoryStore(
            fileURL: directory.appendingPathComponent("expiration.json"),
            maximumEntryCount: 20,
            maximumStorageBytes: 10_000,
            userDefaults: settings,
            now: { referenceDate }
        )
        store.add(
            .text("recent"),
            at: referenceDate.addingTimeInterval(-6 * 24 * 60 * 60)
        )
        store.add(
            .text("expired"),
            at: referenceDate.addingTimeInterval(-8 * 24 * 60 * 60)
        )
        try require(
            store.entries.map(\.payload) == [.text("recent")],
            "entry older than keepDays was not removed"
        )

        let pinnedURL = directory.appendingPathComponent("pinned-expiration.json")
        let seedStore = HistoryStore(
            fileURL: pinnedURL,
            maximumEntryCount: 20,
            maximumStorageBytes: 10_000,
            keepDays: 0,
            userDefaults: testDefaults
        )
        let oldPinned = seedStore.add(
            .text("permanent"),
            at: referenceDate.addingTimeInterval(-30 * 24 * 60 * 60)
        )
        seedStore.togglePin(id: oldPinned.id)

        let reloaded = HistoryStore(
            fileURL: pinnedURL,
            maximumEntryCount: 20,
            maximumStorageBytes: 10_000,
            userDefaults: settings,
            now: { referenceDate }
        )
        try require(
            reloaded.entries.first?.payload == .text("permanent")
                && reloaded.entries.first?.isPinned == true,
            "keepDays removed a pinned entry"
        )

        let recentlyUsedURL = directory.appendingPathComponent("recently-used-expiration.json")
        let recentlyUsedSeed = HistoryStore(
            fileURL: recentlyUsedURL,
            maximumEntryCount: 20,
            maximumStorageBytes: 10_000,
            keepDays: 0,
            userDefaults: testDefaults,
            now: { referenceDate }
        )
        let oldButUsed = recentlyUsedSeed.add(
            .text("old copy, recent use"),
            at: referenceDate.addingTimeInterval(-30 * 24 * 60 * 60)
        )
        recentlyUsedSeed.promote(id: oldButUsed.id)

        let recentlyUsedReloaded = HistoryStore(
            fileURL: recentlyUsedURL,
            maximumEntryCount: 20,
            maximumStorageBytes: 10_000,
            userDefaults: settings,
            now: { referenceDate }
        )
        try require(
            recentlyUsedReloaded.entries.first?.id == oldButUsed.id
                && recentlyUsedReloaded.entries.first?.createdAt
                    == referenceDate.addingTimeInterval(-30 * 24 * 60 * 60)
                && recentlyUsedReloaded.entries.first?.lastUsedAt == referenceDate,
            "keepDays removed an old copy that was used recently"
        )
    }

    private static func testShortcutDefaultsAndValidation() throws {
        let suiteName = "cpsmartTests-shortcutDefaults-\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        defer { settings.removePersistentDomain(forName: suiteName) }
        let shortcuts = ShortcutStore(userDefaults: settings)

        try require(
            shortcuts.displayString(for: .toggleHistory) == "⇧⌘V",
            "default global shortcut display changed"
        )
        try require(
            shortcuts.bindings(for: .pasteSelection).count == 2,
            "Return and keypad Enter defaults were not both preserved"
        )
        try require(
            shortcuts.displayString(for: .addToPinboard) == "⌘D",
            "default pinboard shortcut display changed"
        )
        try require(
            shortcuts.validate(
                ShortcutGesture(keyCode: UInt16(kVK_UpArrow)),
                for: .selectPrevious
            ) == nil,
            "an unmodified arrow key was rejected"
        )
        try require(
            shortcuts.validate(
                ShortcutGesture(keyCode: UInt16(kVK_ANSI_A)),
                for: .selectPrevious
            ) == .requiresModifier,
            "an unmodified text key was accepted"
        )
        try require(
            shortcuts.validate(
                ShortcutGesture(keyCode: UInt16(kVK_ANSI_A), modifiers: [.shift]),
                for: .toggleHistory
            ) == .globalRequiresModifier,
            "a shift-only global shortcut was accepted"
        )
        try require(
            shortcuts.validate(
                ShortcutGesture(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command]),
                for: .toggleQuickLook
            ) == .reservedByApplication,
            "Command-Q was accepted as a configurable shortcut"
        )
        try require(
            shortcuts.validate(
                ShortcutGesture(keyCode: UInt16(kVK_ANSI_C), modifiers: [.command]),
                for: .toggleQuickLook
            ) == .reservedByApplication,
            "standard Command-C editing shortcut was accepted"
        )
        let directPinboardGesture = ShortcutGesture(
            keyCode: UInt16(kVK_ANSI_1),
            modifiers: [.command, .option]
        )
        let cyclePinboardGesture = ShortcutGesture(
            keyCode: UInt16(kVK_Tab),
            modifiers: [.control]
        )
        try require(
            shortcuts.validate(directPinboardGesture, for: .selectNext)
                == .reservedByApplication
                && shortcuts.validate(cyclePinboardGesture, for: .toggleHistory)
                    == .reservedByApplication,
            "fixed pinboard shortcuts were accepted by configurable shortcut validation"
        )
        try require(
            shortcuts.set(cyclePinboardGesture, for: .selectNext)
                == .reservedByApplication
                && !shortcuts.isCustomized(.selectNext),
            "a reserved pinboard shortcut was persisted as a configurable binding"
        )
        try require(
            shortcuts.validate(
                ShortcutGesture(keyCode: UInt16(kVK_RightArrow)),
                for: .selectPrevious
            ) == .conflictsWith(.selectNext),
            "duplicate shortcut conflict was not detected"
        )
    }

    private static func testShortcutPersistenceAndReset() throws {
        let suiteName = "cpsmartTests-shortcutPersistence-\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        defer { settings.removePersistentDomain(forName: suiteName) }

        let up = ShortcutGesture(keyCode: UInt16(kVK_UpArrow))
        let shortcuts = ShortcutStore(userDefaults: settings)
        try require(
            shortcuts.set(up, for: .selectPrevious) == nil,
            "valid shortcut override was rejected"
        )
        try require(shortcuts.hasCustomizations, "customization state was not recorded")

        let reloaded = ShortcutStore(userDefaults: settings)
        try require(
            reloaded.bindings(for: .selectPrevious) == [up],
            "shortcut override did not persist"
        )
        let left = ShortcutGesture(keyCode: UInt16(kVK_LeftArrow))
        try require(
            reloaded.set(left, for: .selectPrevious) == nil
                && !reloaded.hasCustomizations
                && settings.data(forKey: ShortcutStore.defaultsKey) == nil,
            "recording the single default binding did not clear its override"
        )
        try require(
            reloaded.set(up, for: .selectPrevious) == nil,
            "shortcut could not be customized again after returning to default"
        )
        reloaded.resetToDefaults()
        try require(
            !reloaded.hasCustomizations
                && reloaded.primaryBinding(for: .selectPrevious).keyCode == UInt16(kVK_LeftArrow)
                && settings.data(forKey: ShortcutStore.defaultsKey) == nil,
            "reset did not remove persisted overrides and restore defaults"
        )
    }

    private static func testShortcutResetAndSwap() throws {
        let suiteName = "cpsmartTests-shortcutEditing-\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        defer { settings.removePersistentDomain(forName: suiteName) }
        let shortcuts = ShortcutStore(userDefaults: settings)

        let left = ShortcutGesture(keyCode: UInt16(kVK_LeftArrow))
        let right = ShortcutGesture(keyCode: UInt16(kVK_RightArrow))

        try require(
            shortcuts.swap(
                .selectPrevious,
                with: .selectNext,
                requestedGesture: right
            ) == nil
                && shortcuts.primaryBinding(for: .selectPrevious) == right
                && shortcuts.primaryBinding(for: .selectNext) == left
                && shortcuts.customizationCount == 2,
            "conflicting navigation shortcuts were not swapped atomically"
        )
        try require(
            shortcuts.validateReset(for: .selectPrevious) == .conflictsWith(.selectNext),
            "single-action reset did not detect a conflict with the current bindings"
        )
        // 交换状态下两项互为对方默认值，任何单项恢复都会冲突；
        // 先把其中一项改到空闲按键，才能单项恢复另一项。
        try require(
            shortcuts.set(ShortcutGesture(keyCode: UInt16(kVK_UpArrow)), for: .selectNext) == nil,
            "moving selectNext to a free key was rejected"
        )
        try require(
            shortcuts.resetToDefault(.selectPrevious) == nil
                && shortcuts.primaryBinding(for: .selectPrevious) == left
                && !shortcuts.isCustomized(.selectPrevious)
                && shortcuts.isCustomized(.selectNext),
            "single-action reset did not restore only the requested shortcut"
        )

        let globalGesture = shortcuts.primaryBinding(for: .toggleHistory)
        try require(
            shortcuts.validateSwap(
                .selectPrevious,
                with: .toggleHistory,
                requestedGesture: globalGesture
            ) == .globalRequiresModifier,
            "swap allowed an unmodified key to become the global shortcut"
        )
        try require(
            shortcuts.validateSwap(
                .selectPrevious,
                with: .selectNext,
                requestedGesture: ShortcutGesture(
                    keyCode: UInt16(kVK_Tab),
                    modifiers: [.control]
                )
            ) == .reservedByApplication,
            "swap accepted a fixed pinboard shortcut"
        )
    }

    private static func testShortcutMatcherContexts() throws {
        let suiteName = "cpsmartTests-shortcutMatcher-\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        defer { settings.removePersistentDomain(forName: suiteName) }
        let shortcuts = ShortcutStore(userDefaults: settings)
        let matcher = ShortcutMatcher(store: shortcuts)

        let left = makeKeyEvent(keyCode: UInt16(kVK_LeftArrow), characters: "")
        try require(
            matcher.action(for: left, context: .browsing) == .selectPrevious,
            "left arrow did not resolve in browsing context"
        )
        try require(
            matcher.action(for: left, context: .searching) == nil,
            "left arrow intercepted search field navigation"
        )

        let tab = makeKeyEvent(keyCode: UInt16(kVK_Tab), characters: "\t")
        try require(
            matcher.action(for: tab, context: .searching) == .toggleSearchFocus,
            "Tab did not resolve in search context"
        )
        try require(
            matcher.action(for: tab, context: .composingSearchText) == nil,
            "Tab intercepted input method composition"
        )

        let commandOne = makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_1),
            modifiers: [.command],
            characters: "1"
        )
        try require(
            matcher.action(for: commandOne, context: .composingSearchText) == .filterAll,
            "explicit Command shortcut stopped working during input method composition"
        )

        let commandD = makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_D),
            modifiers: [.command],
            characters: "d"
        )
        try require(
            matcher.action(for: commandD, context: .browsing) == .addToPinboard
                && matcher.action(for: commandD, context: .composingSearchText) == .addToPinboard,
            "pinboard shortcut did not resolve in supported contexts"
        )

        let space = makeKeyEvent(keyCode: UInt16(kVK_Space), characters: " ")
        try require(
            matcher.action(for: space, context: .browsing) == .toggleQuickLook,
            "Space did not resolve in browsing context"
        )
        try require(
            matcher.action(for: space, context: .searching) == nil,
            "Space was intercepted while typing in the search field"
        )
        // 即使用户把 Space 重绑定给粘贴，搜索框里的空格仍然必须是输入字符。
        try require(
            shortcuts.swap(
                .pasteSelection,
                with: .toggleQuickLook,
                requestedGesture: ShortcutGesture(keyCode: UInt16(kVK_Space))
            ) == nil,
            "Space could not be swapped onto paste"
        )
        try require(
            matcher.action(for: space, context: .browsing) == .pasteSelection
                && matcher.action(for: space, context: .searching) == nil,
            "rebound Space was intercepted while typing in the search field"
        )

        let optionCommandP = makeKeyEvent(
            keyCode: UInt16(kVK_ANSI_P),
            modifiers: [.option, .command],
            characters: "p"
        )
        try require(
            matcher.action(for: optionCommandP, context: .browsing) == nil,
            "shortcut matching ignored extra modifiers"
        )

        let optionUp = ShortcutGesture(keyCode: UInt16(kVK_UpArrow), modifiers: [.option])
        try require(
            shortcuts.set(optionUp, for: .togglePin) == nil,
            "Option-arrow custom shortcut was rejected"
        )
        let optionUpEvent = makeKeyEvent(
            keyCode: UInt16(kVK_UpArrow),
            modifiers: [.option],
            characters: ""
        )
        try require(
            matcher.action(for: optionUpEvent, context: .browsing) == .togglePin
                && matcher.action(for: optionUpEvent, context: .searching) == nil,
            "custom management shortcut intercepted search field word navigation"
        )
    }

    private static func testInvalidShortcutPersistenceFallsBackToDefaults() throws {
        let suiteName = "cpsmartTests-invalidShortcuts-\(UUID().uuidString)"
        let settings = UserDefaults(suiteName: suiteName)!
        defer { settings.removePersistentDomain(forName: suiteName) }
        let invalidJSON = """
        {"version":1,"bindings":{"selectPrevious":[{"keyCode":0,"modifiersRawValue":0}]}}
        """
        settings.set(Data(invalidJSON.utf8), forKey: ShortcutStore.defaultsKey)

        let shortcuts = ShortcutStore(userDefaults: settings)
        try require(
            shortcuts.primaryBinding(for: .selectPrevious).keyCode == UInt16(kVK_LeftArrow),
            "invalid persisted shortcut did not fall back to the default"
        )

        struct PersistedShortcuts: Encodable {
            let version: Int
            let bindings: [String: [ShortcutGesture]]
        }
        let reservedData = try JSONEncoder().encode(PersistedShortcuts(
            version: 1,
            bindings: [
                ShortcutActionID.selectPrevious.rawValue: [ShortcutGesture(
                    keyCode: UInt16(kVK_ANSI_2),
                    modifiers: [.command, .option]
                )]
            ]
        ))
        settings.set(reservedData, forKey: ShortcutStore.defaultsKey)
        let reservedReloaded = ShortcutStore(userDefaults: settings)
        try require(
            reservedReloaded.primaryBinding(for: .selectPrevious).keyCode
                == UInt16(kVK_LeftArrow),
            "persisted shortcut conflicting with pinboard navigation did not fall back to default"
        )
    }

    private static func makeKeyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private static func makePNGData() throws -> Data {
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let data = representation.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "cpsmartCoreTests",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "could not generate test PNG"]
            )
        }
        return data
    }

    private static func waitForThumbnail(
        from provider: ThumbnailProvider,
        entry: ClipboardEntry
    ) throws -> NSImage? {
        var result: NSImage?
        var didComplete = false
        provider.thumbnail(for: entry) { image in
            result = image
            didComplete = true
        }

        let deadline = Date().addingTimeInterval(3)
        while !didComplete && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        try require(didComplete, "thumbnail callback did not arrive on the main run loop")
        return result
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw NSError(
                domain: "cpsmartCoreTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    private static func requireValue<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else {
            throw NSError(
                domain: "cpsmartCoreTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
        return value
    }

    private struct LegacyClipboardEntry: Codable {
        let id: UUID
        let payload: ClipboardPayload
        let createdAt: Date
    }

    private struct LegacyClipboardEntryWithSource: Codable {
        let id: UUID
        let payload: ClipboardPayload
        let createdAt: Date
        let sourceAppName: String?
        let sourceAppBundleID: String?
    }
}
