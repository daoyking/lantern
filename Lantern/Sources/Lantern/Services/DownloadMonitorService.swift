import Foundation
import AppKit

/// Download monitor (common checklist #7): watches ~/Downloads for recent
/// files and in-progress browser downloads (.download/.crdownload/.part),
/// listing the newest entries with size. Clicking a row reveals it in
/// Finder. Reading ~/Downloads triggers the system Downloads-folder prompt
/// once; a denial hides the section silently (weather/calendar pattern).
struct DownloadItem: Identifiable, Equatable {
    let id: String            // stable = path
    let name: String
    let path: String
    let sizeBytes: Int64
    let isPartial: Bool       // .download / .crdownload / .part in progress
    let modifiedAt: Date
}

final class DownloadMonitorService: BaseFeatureService {

    static let shared = DownloadMonitorService(feature: .downloadMonitor)

    /// Browser partial-download extensions, checked case-insensitively.
    static let partialExtensions: Set<String> = ["download", "crdownload", "part"]

    @Published public private(set) var items: [DownloadItem] = []
    @Published public private(set) var accessDenied = false

    private var pollTimer: Timer?

    private override init(feature: AppFeature) { super.init(feature: feature) }

    override public func start() throws {
        refresh()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    override public func stop() throws {
        pollTimer?.invalidate()
        pollTimer = nil
        items = []
    }

    deinit { pollTimer?.invalidate() }

    /// Snapshot of ~/Downloads, newest first, capped at 10 entries.
    public func refresh() {
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let downloads = url else { accessDenied = true; return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: downloads,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: []) else {
            // First touch may prompt; if the user denied, this throws.
            accessDenied = true
            return
        }
        accessDenied = false
        var found: [DownloadItem] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            guard values?.isDirectory != true, let modified = values?.contentModificationDate else { continue }
            // Recent window: last 24 hours keeps the list meaningful.
            guard modified.timeIntervalSinceNow > -86_400 else { continue }
            let ext = entry.pathExtension.lowercased()
            let isPartial = Self.partialExtensions.contains(ext)
            found.append(DownloadItem(
                id: entry.path,
                name: entry.lastPathComponent,
                path: entry.path,
                sizeBytes: Int64(values?.fileSize ?? 0),
                isPartial: isPartial,
                modifiedAt: modified
            ))
        }
        found.sort { $0.modifiedAt > $1.modifiedAt }
        items = Array(found.prefix(10))
    }

    public func reveal(_ item: DownloadItem) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }

    /// Double-click: open the finished file; partial downloads only reveal.
    public func open(_ item: DownloadItem) {
        guard !item.isPartial else { reveal(item); return }
        NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
    }

    /// Human-readable size, e.g. "1.2 MB".
    public static func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
