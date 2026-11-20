// ClipboardEnhancementService.swift — Real paste-as-plain-text and iCloud sync.
//
// pasteAsPlainText monitors the system pasteboard and, whenever rich text or
// HTML lands on it, rewrites the pasteboard to plain text. The change is a
// real NSPasteboard mutation observable by every app.
//
// syncClipboardAcrossDevices uses NSUbiquitousKeyValueStore (iCloud KVS) to
// mirror clipboard text across devices signed into the same iCloud account.

import Foundation
import AppKit

// MARK: - Paste as plain text

public final class PastePlainTextService: BaseFeatureService {
    private var timer: Timer?
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int = -1

    public override init(feature: AppFeature) {
        super.init(feature: feature)
    }

    public override func start() throws {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.scrubPasteboardIfNeeded()
        }
    }

    public override func stop() throws {
        timer?.invalidate()
        timer = nil
    }

    /// If the newest pasteboard item contains rich text / HTML, replace its
    /// contents with the plain-string representation. No-op for plain text,
    /// images and file URLs so those clipboard uses still work.
    private func scrubPasteboardIfNeeded() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let richTypes: [NSPasteboard.PasteboardType] = [.rtf, .rtfd, .html, .tabularText]
        let hasRich = richTypes.contains { pasteboard.types?.contains($0) ?? false }
        guard hasRich else { return }
        guard let plain = pasteboard.string(forType: .string), !plain.isEmpty else { return }

        pasteboard.clearContents()
        pasteboard.setString(plain, forType: .string)
        lastChangeCount = pasteboard.changeCount // avoid reprocessing our own write
    }

    /// Pure helper: decide whether a set of types should be scrubbed.
    public static func shouldScrub(types: [NSPasteboard.PasteboardType]?) -> Bool {
        guard let types else { return false }
        let rich: Set<NSPasteboard.PasteboardType> = [.rtf, .rtfd, .html, .tabularText]
        return types.contains { rich.contains($0) }
    }
}

// MARK: - iCloud clipboard sync

public final class ClipboardSyncService: BaseFeatureService {
    private let store = NSUbiquitousKeyValueStore.default
    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private let syncKey = "lantern.clipboard.latest"

    private enum SyncDirection {
        case none, upload, download
    }
    private var lastDirection: SyncDirection = .none

    public override init(feature: AppFeature) {
        super.init(feature: feature)
    }

    public override func start() throws {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        store.synchronize()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store
        )

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollLocalClipboard()
        }
    }

    public override func stop() throws {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self, name: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store)
    }

    private func pollLocalClipboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        // Don't echo back a value we just downloaded.
        if lastDirection == .download {
            lastDirection = .none
            return
        }
        lastDirection = .upload
        store.set(text, forKey: syncKey)
        store.synchronize()
    }

    @objc private func storeDidChange(_ notification: Notification) {
        guard let text = store.string(forKey: syncKey), !text.isEmpty else { return }
        guard text != pasteboard.string(forType: .string) else { return }
        lastDirection = .download
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    /// Whether iCloud key-value storage is available on this device/account.
    public static var isAvailable: Bool {
        NSUbiquitousKeyValueStore.default.synchronize()
        // A store that can round-trip a probe key is usable.
        let probe = "lantern.kvs.probe"
        NSUbiquitousKeyValueStore.default.set(true, forKey: probe)
        let ok = NSUbiquitousKeyValueStore.default.bool(forKey: probe)
        NSUbiquitousKeyValueStore.default.removeObject(forKey: probe)
        return ok
    }
}
