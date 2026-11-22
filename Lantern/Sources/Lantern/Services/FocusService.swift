import Foundation
import AppKit
import SwiftUI

/// Focus session (common checklist #12, vorssaint parity): toggling starts
/// a fixed 25-minute session shown on the island; expiry pops the done card
/// and plays a sound. While a session runs we also post the legacy
/// `com.apple.notificationcenterui.setDNDStatus` distributed notification —
/// the only zero-dependency hook for Do Not Disturb. On recent macOS the
/// notification may be inert (Focus replaced DND); we post best-effort and
/// never claim state we cannot read back.
final class FocusService: BaseFeatureService {

    static let shared = FocusService(feature: .focusMode)

    /// Session length in seconds (vorssaint parity: one 25-minute block).
    static let sessionSeconds = 25 * 60

    @Published public private(set) var endAt: Date?
    @Published public private(set) var interrupted: Bool = false

    private var tickTimer: Timer?
    private var doneWindow: NSWindow?
    private var running = false

    private override init(feature: AppFeature) { super.init(feature: feature) }

    deinit { tickTimer?.invalidate() }

    // MARK: - Lifecycle (driven by the focusMode toggle)

    override public func start() throws { setRunning(true) }
    override public func stop() throws { setRunning(false) }

    public func setRunning(_ active: Bool) {
        guard active != running else { return }
        running = active
        if active {
            beginSession()
            tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick()
            }
        } else {
            tickTimer?.invalidate()
            tickTimer = nil
            if endAt != nil { restoreDND() }
            endAt = nil
            interrupted = false
            dismissDoneWindow()
        }
    }

    // MARK: - Session

    private func beginSession() {
        endAt = Date().addingTimeInterval(TimeInterval(Self.sessionSeconds))
        interrupted = false
Self.setDND(true)
    }

    public var remainingSeconds: Int {
        guard let endAt else { return 0 }
        return max(0, Int(endAt.timeIntervalSinceNow.rounded(.up)))
    }

    /// mm:ss caption for the island slot.
    public var caption: String {
        let s = remainingSeconds
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    /// Abort early from the done card — keeps DND restore honest.
    public func interrupt() {
        guard endAt != nil else { return }
        interrupted = true
        restoreDND()
        endAt = nil
        dismissDoneWindow()
    }

    private func tick() {
        guard let endAt, Date() >= endAt else { return }
        restoreDND()
        self.endAt = nil
        notifyDone()
    }

    // MARK: - Legacy DND hook (best-effort)

    /// Posted at session start/end. Legacy hook, may be inert on Focus-era
    /// macOS — no state readback exists for us, so we never expose status.
    public static func setDND(_ enabled: Bool) {
        let center = DistributedNotificationCenter.default()
        let name = Notification.Name("com.apple.notificationcenterui.setDNDStatus")
        center.post(Notification(name: name, object: nil, userInfo: ["status": enabled ? 1 : 0]))
    }

    private func restoreDND() { Self.setDND(false) }

    // MARK: - Done card (same pattern as QuickTimerService)

    private func notifyDone() {
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
        panel.contentView = NSHostingView(rootView: FocusDoneCard {
            [weak self] in self?.dismissDoneWindow()
        })
        panel.orderFrontRegardless()
        doneWindow = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.dismissDoneWindow()
        }
    }

    private func dismissDoneWindow() {
        doneWindow?.orderOut(nil)
        doneWindow = nil
    }
}
