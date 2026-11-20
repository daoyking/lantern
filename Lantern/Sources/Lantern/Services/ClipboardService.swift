// ClipboardService.swift — Clipboard history and management

import Foundation
import AppKit

/// Service managing clipboard operations and history
public final class ClipboardService: BaseFeatureService {
    
    private let pasteboard = NSPasteboard.general
    private var history: [ClipboardItem] = []
    private let maxHistorySize = 50
    
    // MARK: - Timer-based monitoring
    private var monitorTimer: Timer?
    private var lastContentHash: String?
    
    public override init(feature: AppFeature) {
        super.init(feature: feature)
    }
    
    public override func start() throws {
        // Poll clipboard contents periodically using a Timer
        // (NSPasteboard.changeNotification was removed in newer SDKs)
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            self.checkForChanges()
        }
        #if DEBUG
        print("[Lantern] ClipboardService: Started monitoring via timer")
        #endif
    }
    
    public override func stop() throws {
        monitorTimer?.invalidate()
        monitorTimer = nil
        #if DEBUG
        print("[Lantern] ClipboardService: Stopped")
        #endif
    }
    
    // MARK: - Private helpers
    
    private func checkForChanges() {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
        let hash = text.hashValue.description
        guard hash != lastContentHash else { return }
        lastContentHash = hash
        
        let item = ClipboardItem(
            type: .string,
            content: text,
            timestamp: Date()
        )
        history.insert(item, at: 0)
        if history.count > maxHistorySize {
            history.removeLast(history.count - maxHistorySize)
        }
        #if DEBUG
        print("[Lantern] ClipboardService: New content detected (\(min(text.count, 30)) chars)")
        #endif
    }
    
    private func hashString(_ s: String) -> String {
        return String(s.hashValue)
    }
    
    // MARK: - Public API
    
    /// Copy text to clipboard
    public func copy(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    /// Get current clipboard content
    public func getSelectedText() -> String? {
        pasteboard.string(forType: .string)
    }
    
    /// Get clipboard history (most recent first)
    public func getHistory() -> [ClipboardItem] {
        return history
    }
    
    /// Clear clipboard history
    public func clearHistory() {
        history.removeAll()
        lastContentHash = nil
    }
}

// MARK: - Data Types

public enum ClipboardItemType: String, CaseIterable, Identifiable {
    case string = "Text"
    case url = "URL"
    case image = "Image"
    case fileURL = "File Path"
    case rtfd = "Rich Text"
    
    public var id: String { rawValue }
    
    public var description: String {
        switch self {
        case .string: return "Plain Text"
        case .url: return "URL Link"
        case .image: return "Image"
        case .fileURL: return "File Path"
        case .rtfd: return "Rich Text"
        }
    }
}

public struct ClipboardItem: Identifiable, Equatable, Hashable {
    public let id: UUID = UUID()
    public let type: ClipboardItemType
    public let content: String
    public let timestamp: Date
    
    public static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
