import Foundation

enum ClipboardPayload: Codable, Equatable {
    case text(String)
    case image(data: Data, pasteboardType: String)
    case files([String])

    var estimatedSize: Int {
        switch self {
        case .text(let text):
            return text.utf8.count
        case .image(let data, _):
            return data.count
        case .files(let paths):
            return paths.reduce(0) { $0 + $1.utf8.count }
        }
    }

    var searchableText: String {
        switch self {
        case .text(let text):
            return text
        case .image:
            return "图片 image"
        case .files(let paths):
            return paths.joined(separator: " ")
        }
    }
}

struct ClipboardEntry: Codable, Equatable, Identifiable {
    let id: UUID
    let payload: ClipboardPayload
    let createdAt: Date
    let lastUsedAt: Date?
    let sourceAppName: String?
    let sourceAppBundleID: String?
    let isPinned: Bool?

    init(
        id: UUID = UUID(),
        payload: ClipboardPayload,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        isPinned: Bool? = nil
    ) {
        self.id = id
        self.payload = payload
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.isPinned = isPinned
    }

    var recencyDate: Date {
        max(createdAt, lastUsedAt ?? createdAt)
    }
}

struct RemovedClipboardEntry: Equatable {
    let entry: ClipboardEntry
    let index: Int
}

enum PinboardColor: String, Codable, CaseIterable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink
    case gray

    var displayName: String {
        switch self {
        case .red: return L10n.tr("红色")
        case .orange: return L10n.tr("橙色")
        case .yellow: return L10n.tr("黄色")
        case .green: return L10n.tr("绿色")
        case .blue: return L10n.tr("蓝色")
        case .purple: return L10n.tr("紫色")
        case .pink: return L10n.tr("粉色")
        case .gray: return L10n.tr("灰色")
        }
    }
}

struct Pinboard: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var color: PinboardColor
    var entries: [ClipboardEntry]

    init(
        id: UUID = UUID(),
        name: String,
        color: PinboardColor,
        entries: [ClipboardEntry] = []
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.entries = entries
    }
}
