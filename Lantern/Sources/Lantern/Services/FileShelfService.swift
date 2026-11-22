import Foundation
import AppKit

/// File shelf (common checklist #3): drag files onto the panel section and
/// they stick around for quick reveal/open. Persisted as security-scoped
/// bookmark data in defaults, restored across launches. No TCC: the user
/// dragged the files themselves, which is the consent.
struct ShelfItem: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let path: String
    let bookmark: Data
}

final class FileShelfService: BaseFeatureService {

    static let shared = FileShelfService(feature: .fileShelf)
    static let storageKey = "lantern_file_shelf_items"
    static let maxItems = 12

    @Published public private(set) var items: [ShelfItem] = []

    private override init(feature: AppFeature) {
        super.init(feature: feature)
        restore()
    }

    override public func start() throws {}
    override public func stop() throws { clear() }

    // MARK: - Shelf operations

    /// Add a dragged file (dedup by path, newest first, capped).
    public func add(url: URL) {
        guard let bookmark = try? url.bookmarkData() else { return }
        var item = ShelfItem(id: UUID(), name: url.lastPathComponent,
                             path: url.path, bookmark: bookmark)
        if let existing = items.first(where: { $0.path == item.path }) {
            item = ShelfItem(id: existing.id, name: item.name,
                             path: item.path, bookmark: item.bookmark)
            items.removeAll { $0.path == item.path }
        }
        items.insert(item, at: 0)
        if items.count > Self.maxItems { items.removeLast(items.count - Self.maxItems) }
        persist()
    }

    public func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    public func clear() {
        items.removeAll()
        persist()
    }

    /// Resolve the stored bookmark to a live URL (nil when moved/deleted).
    public static func resolve(_ item: ShelfItem) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: item.bookmark, options: [],
                        relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    public func reveal(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              let url = Self.resolve(item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func open(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              let url = Self.resolve(item) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Persistence (bookmark data survives moves across sessions)

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let stored = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        items = stored
    }
}
