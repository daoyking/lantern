import Foundation
import AppKit
import SwiftUI

/// 20-20-20 eye-strain prevention (common checklist #11): every 20
/// minutes, overlay the screen for 20 seconds with a countdown asking
/// the user to look ~20 feet away. Zero TCC permissions — a plain
/// borderless window above everything, auto-dismissing.
///
/// Main display only (honest limitation, noted in the journal).
final class EyeBreakService: BaseFeatureService {

    static let shared = EyeBreakService(feature: .eyeBreak)

    /// Interval between breaks, and the overlay duration. Exposed for tests.
    static let breakInterval: TimeInterval = 20 * 60   // 20 minutes
    static let breakDuration: TimeInterval = 20        // 20 seconds

    private var scheduleTimer: Timer?
    private var breakTimer: Timer?
    private var breakWindow: NSWindow?
    private var breakEnd: Date?

    public private(set) var onBreak: Bool = false

    override init(feature: AppFeature) { super.init(feature: feature) }

    override public func start() throws {
        scheduleNextBreak(from: Date())
    }

    override public func stop() throws {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        endBreak(reschedule: false)
    }

    deinit {
        scheduleTimer?.invalidate()
        breakTimer?.invalidate()
    }

    private func scheduleNextBreak(from date: Date) {
        scheduleTimer?.invalidate()
        scheduleTimer = Timer.scheduledTimer(
            withTimeInterval: Self.breakInterval, repeats: false
        ) { [weak self] _ in
            self?.beginBreak()
        }
    }

    // MARK: - Break overlay

    private func beginBreak() {
        guard breakWindow == nil else { return }
        onBreak = true
        breakEnd = Date().addingTimeInterval(Self.breakDuration)

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let panel = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hosting = NSHostingView(rootView: EyeBreakOverlay(
            endDate: breakEnd!,
            onSkip: { [weak self] in self?.endBreak() }
        ))
        panel.contentView = hosting
        panel.makeKeyAndOrderFront(nil)
        breakWindow = panel

        // Tick for the countdown label; the overlay reads endDate itself,
        // so this timer only drives the auto-dismiss.
        breakTimer = Timer.scheduledTimer(
            withTimeInterval: 0.25, repeats: true
        ) { [weak self] _ in
            guard let self, let end = self.breakEnd, Date() >= end else { return }
            self.endBreak()
        }
    }

    private func endBreak(reschedule: Bool = true) {
        breakTimer?.invalidate()
        breakTimer = nil
        breakWindow?.orderOut(nil)
        breakWindow = nil
        breakEnd = nil
        onBreak = false
        if reschedule { scheduleNextBreak(from: Date()) }
    }
}
