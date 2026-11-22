import Foundation
import AppKit
import SwiftUI

/// Quick timer (common checklist #6): start a 5/10/25-minute countdown
/// from the panel; while it runs, the island shows the remaining time,
/// and expiry pops a small corner card with a sound. Zero TCC.
///
/// Button semantics: tapping the same duration again cancels; tapping a
/// different duration restarts with the new one. The `quickTimer`
/// state feature gates the whole thing (island slot + availability).
final class QuickTimerService: BaseFeatureService {

    static let shared = QuickTimerService(feature: .quickTimer)

    /// Offered durations, minutes → feature pairing handled by the catalog.
    static let durations: [Int] = [5, 10, 25]

    @Published public private(set) var endAt: Date?
    @Published public private(set) var durationMinutes: Int?

    private var tickTimer: Timer?
    private var doneWindow: NSWindow?
    private var running = false

    override init(feature: AppFeature) { super.init(feature: feature) }

    deinit { tickTimer?.invalidate() }

    // MARK: - Lifecycle (gated by the quickTimer toggle)

    override public func start() throws { setRunning(true) }
    override public func stop() throws { setRunning(false) }

    public func setRunning(_ active: Bool) {
        guard active != running else { return }
        running = active
        if active {
            tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick()
            }
        } else {
            tickTimer?.invalidate()
            tickTimer = nil
            cancel()
            dismissDoneWindow()
        }
    }

    // MARK: - Countdown control

    /// Start (or restart) a countdown; tapping the same duration while
    /// running cancels instead — one button, no extra cancel key.
    public func start(minutes: Int) {
        if let current = durationMinutes, endAt != nil, current == minutes {
            cancel()
            return
        }
        durationMinutes = minutes
        endAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    public func cancel() {
        endAt = nil
        durationMinutes = nil
    }

    /// Seconds left; negative never escapes (expiry handled by tick).
    public var remainingSeconds: Int {
        guard let endAt else { return 0 }
        return max(0, Int(endAt.timeIntervalSinceNow.rounded(.up)))
    }

    /// mm:ss caption for the island slot.
    public var caption: String {
        let s = remainingSeconds
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func tick() {
        guard let endAt, Date() >= endAt else { return }
        let minutes = durationMinutes ?? 0
        cancel()
        notifyDone(minutes: minutes)
    }

    // MARK: - Expiry card

    private func notifyDone(minutes: Int) {
        NSSound(named: "Glass")?.play()
        dismissDoneWindow()

        let width: CGFloat = 264, height: CGFloat = 108
        guard let screen = NSScreen.main else { return }
        let frame = NSRect(
            x: screen.frame.maxX - width - 16,
            y: screen.frame.maxY - height - 16,
            width: width,
            height: height
        )
        let panel = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: TimerDoneCard(minutes: minutes) {
            [weak self] in self?.dismissDoneWindow()
        })
        panel.orderFrontRegardless()
        doneWindow = panel

        // Auto-dismiss after 8 seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.dismissDoneWindow()
        }
    }

    private func dismissDoneWindow() {
        doneWindow?.orderOut(nil)
        doneWindow = nil
    }
}
