import Foundation
import SQLite
import AppKit

extension Notification.Name {
    static let clipboardDatabaseDidChange = Notification.Name("ClipboardDatabaseDidChange")
}

enum ClipboardContentType: String, Codable {
    case text
    case image
}

struct ClipboardItem: Identifiable, Hashable, Codable {
    let id: Int64
    let contentType: ClipboardContentType
    let text: String?
    let imagePNG: Data?
    let createdAt: Date
}

final class ClipboardDatabase {
    private let db: Connection
    private let items = Table("items")
    private let id = Expression<Int64>("id")
    private let type = Expression<String>("type")
    private let text = Expression<String?>("text")
    private let image = Expression<Blob?>("image")
    private let createdAt = Expression<Date>("created_at")
    private let historyLimit = 100

    init() throws {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let appDir = dir.appendingPathComponent("ClipboardMate", conformingTo: .directory)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let dbURL = appDir.appendingPathComponent("clipboard.sqlite")
        db = try Connection(dbURL.path)
        try setup()
    }

    private func setup() throws {
        try db.run(items.create(ifNotExists: true) { t in
            t.column(id, primaryKey: .autoincrement)
            t.column(type)
            t.column(text)
            t.column(image)
            t.column(createdAt)
        })
        try db.run("CREATE INDEX IF NOT EXISTS idx_items_created_at ON items(created_at DESC)")
    }

    func addText(_ value: String) throws {
        let insert = items.insert(type <- ClipboardContentType.text.rawValue, text <- value, image <- nil, createdAt <- Date())
        try db.run(insert)
        try enforceLimit()
        notifyChange()
    }

    func addImage(_ data: Data) throws {
        let insert = items.insert(type <- ClipboardContentType.image.rawValue, text <- nil, image <- Blob(bytes: [UInt8](data)), createdAt <- Date())
        try db.run(insert)
        try enforceLimit()
        notifyChange()
    }

    func deleteItem(id itemId: Int64) throws {
        let row = items.filter(id == itemId)
        try db.run(row.delete())
        notifyChange()
    }

    func clearAll() throws {
        try db.run(items.delete())
        notifyChange()
    }

    func recentItems(matching query: String? = nil) throws -> [ClipboardItem] {
        var q = items.order(createdAt.desc).limit(historyLimit)
        if let query, !query.isEmpty {
            q = q.filter((text ?? "").like("%\(query)%"))
        }
        return try db.prepare(q).map { row in
            ClipboardItem(
                id: row[id],
                contentType: ClipboardContentType(rawValue: row[type]) ?? .text,
                text: row[text],
                imagePNG: row[image].map { Data($0.bytes) },
                createdAt: row[createdAt]
            )
        }
    }

    private func enforceLimit() throws {
        let count = try db.scalar(items.count)
        if count > historyLimit {
            let overflow = count - historyLimit
            let oldest = items.order(createdAt.asc).limit(overflow)
            try db.run(oldest.delete())
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .clipboardDatabaseDidChange, object: nil)
    }
}

