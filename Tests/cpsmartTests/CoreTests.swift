import Foundation
import XCTest
@testable import cpsmart

final class CoreTests: XCTestCase {
    override func setUpWithError() throws {
        CoreTestSupport.resetDefaults()
    }

    override func tearDownWithError() throws {
        CoreTestSupport.resetDefaults()
    }

    private func withTemporaryDirectory(
        _ body: (URL) throws -> Void
    ) throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cpsmartTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try body(temporaryDirectory)
    }

    func testRangeSelection() throws { try CoreTestSupport.runRangeSelection() }
    func testDisplayGeometry() throws { try CoreTestSupport.runDisplayGeometry() }
    func testAdaptivePreviewSizing() throws { try CoreTestSupport.runAdaptivePreviewSizing() }
    func testPreviewSessionAndQuickLookStore() throws {
        try withTemporaryDirectory {
            try CoreTestSupport.runPreviewSessionAndQuickLookStore(in: $0)
        }
    }
    func testUpdateSupport() throws { try CoreTestSupport.runUpdateSupport() }
    func testLocalization() throws { try CoreTestSupport.runLocalization() }
    func testSearchFiltering() throws { try CoreTestSupport.runSearchFiltering() }
    func testThumbnailProvider() throws { try CoreTestSupport.runThumbnailProvider() }
    func testShortcutDefaultsAndValidation() throws {
        try CoreTestSupport.runShortcutDefaultsAndValidation()
    }
    func testShortcutPersistenceAndReset() throws {
        try CoreTestSupport.runShortcutPersistenceAndReset()
    }
    func testShortcutResetAndSwap() throws {
        try CoreTestSupport.runShortcutResetAndSwap()
    }
    func testShortcutMatcherContexts() throws {
        try CoreTestSupport.runShortcutMatcherContexts()
    }
    func testInvalidShortcutPersistenceFallsBackToDefaults() throws {
        try CoreTestSupport.runInvalidShortcutPersistenceFallsBackToDefaults()
    }

    func testDeduplication() throws {
        try withTemporaryDirectory { try CoreTestSupport.runDeduplication(in: $0) }
    }

    func testUsagePromotion() throws {
        try withTemporaryDirectory { try CoreTestSupport.runUsagePromotion(in: $0) }
    }

    func testPinboardLifecycle() throws {
        try withTemporaryDirectory { try CoreTestSupport.runPinboardLifecycle(in: $0) }
    }

    func testPinboardInteractionSupport() throws {
        try CoreTestSupport.runPinboardInteractionSupport()
    }

    func testPinboardEntryPersistence() throws {
        try withTemporaryDirectory { try CoreTestSupport.runPinboardEntryPersistence(in: $0) }
    }

    func testPinboardBatchOperations() throws {
        try withTemporaryDirectory { try CoreTestSupport.runPinboardBatchOperations(in: $0) }
    }

    func testPinboardNameValidation() throws {
        try withTemporaryDirectory { try CoreTestSupport.runPinboardNameValidation(in: $0) }
    }

    func testPinboardReordering() throws {
        try withTemporaryDirectory { try CoreTestSupport.runPinboardReordering(in: $0) }
    }

    func testPersistence() throws {
        try withTemporaryDirectory { try CoreTestSupport.runPersistence(in: $0) }
    }

    func testLimits() throws {
        try withTemporaryDirectory { try CoreTestSupport.runLimits(in: $0) }
    }

    func testRemoveAndClear() throws {
        try withTemporaryDirectory { try CoreTestSupport.runRemoveAndClear(in: $0) }
    }

    func testLegacyHistoryCompatibility() throws {
        try withTemporaryDirectory { try CoreTestSupport.runLegacyHistoryCompatibility(in: $0) }
    }

    func testDeduplicationUsesLatestSourceApplication() throws {
        try withTemporaryDirectory {
            try CoreTestSupport.runDeduplicationUsesLatestSourceApplication(in: $0)
        }
    }

    func testPinBehavior() throws {
        try withTemporaryDirectory { try CoreTestSupport.runPinBehavior(in: $0) }
    }

    func testPinnedEntriesSurviveLimitsAndClear() throws {
        try withTemporaryDirectory {
            try CoreTestSupport.runPinnedEntriesSurviveLimitsAndClear(in: $0)
        }
    }

    func testPinnedFieldLegacyCompatibility() throws {
        try withTemporaryDirectory {
            try CoreTestSupport.runPinnedFieldLegacyCompatibility(in: $0)
        }
    }

    func testRetentionPreferences() throws {
        try withTemporaryDirectory { try CoreTestSupport.runRetentionPreferences(in: $0) }
    }

    func testExpiredEntries() throws {
        try withTemporaryDirectory { try CoreTestSupport.runExpiredEntries(in: $0) }
    }
}
