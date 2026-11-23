import AppKit
import SwiftUI

// MARK: - Lock-screen widgets (Sapphire #19, safe subset)
//
// Sapphire drives a private SkyLight dual-space setup to hang widgets on
// the system lock screen. Lantern takes the public-API subset: when the
// system reports lock/unlock (public distributed notifications), a
// pass-through overlay window rises to `CGShieldingWindowLevel() + 1` —
// the classic shielding level, no private frameworks. The overlay is
// deliberately NON-opaque (widgets on a soft scrim, never a black sheet):
// worst case is stray widgets over the desktop, never a stuck blackout.
final class LockScreenWidgetsService: BaseFeatureService {

    static let shared = LockScreenWidgetsService(feature: .lockScreenWidgets)

    static let lockedNotification = "com.apple.screenIsLocked"
    static let unlockedNotification = "com.apple.screenIsUnlocked"

    struct Snapshot: Equatable {
        let cpu: Int
        let memory: Int
        let networkKBps: Int
        let battery: Int
        let charging: Bool
    }

    @Published public private(set) var snapshot: Snapshot?
    @Published public private(set) var isLockedVisible = false

    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?
    private var overlay: NSWindow?
    private var tickTimer: Timer?

    override init(feature: AppFeature) { super.init(feature: feature) }
    deinit { stopObservers() }

    override public func start() throws {
        let center = DistributedNotificationCenter.default()
        lockObserver = center.addObserver(
            forName: NSNotification.Name(Self.lockedNotification), object: nil, queue: .main
        ) { [weak self] _ in self?.showOverlay() }
        unlockObserver = center.addObserver(
            forName: NSNotification.Name(Self.unlockedNotification), object: nil, queue: .main
        ) { [weak self] _ in self?.hideOverlay() }
    }

    override public func stop() throws {
        stopObservers()
        hideOverlay()
    }

    private func stopObservers() {
        if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver) }
        if let unlockObserver { DistributedNotificationCenter.default().removeObserver(unlockObserver) }
        lockObserver = nil
        unlockObserver = nil
    }

    // MARK: Overlay

    private func showOverlay() {
        guard overlay == nil else { return }
        guard let screen = NSScreen.main else { return }
        let panel = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: LockScreenWidgetsView(service: self))
        panel.orderFrontRegardless()
        overlay = panel
        isLockedVisible = true

        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    private func hideOverlay() {
        tickTimer?.invalidate()
        tickTimer = nil
        overlay?.orderOut(nil)
        overlay = nil
        isLockedVisible = false
        snapshot = nil
    }

    private let metrics = SystemMetrics()

    private func tick() {
        let sample = metrics.snapshot()
        snapshot = Snapshot(
            cpu: Int(sample.cpuUsage.rounded()),
            memory: Int(sample.memoryPressure.rounded()),
            networkKBps: max(0, Int((sample.networkDownKBps + sample.networkUpKBps).rounded())),
            battery: sample.batteryPercent >= 0 ? Int(sample.batteryPercent.rounded()) : -1,
            charging: sample.batteryCharging
        )
    }
}

// MARK: - Widget face

/// Big clock + date + the four island metrics, over a soft scrim.
/// `TimelineView` drives the clock — no timer plumbing needed.
struct LockScreenWidgetsView: View {
    @ObservedObject var service: LockScreenWidgetsService

    private static let dateFolder: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter
    }()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 10) {
                Text(context.date, style: .time)
                    .font(.system(size: 72, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                Text(Self.dateFolder.string(from: context.date))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))

                if let snapshot = service.snapshot {
                    HStack(spacing: 26) {
                        metric(icon: "cpu", label: "CPU", value: "\(snapshot.cpu)%", tint: .green)
                        metric(icon: "memorychip", label: "MEM", value: "\(snapshot.memory)%", tint: .purple)
                        metric(icon: "antenna.radiowaves.left.and.right",
                               label: "NET", value: "\(snapshot.networkKBps) KB/s", tint: .cyan)
                        if snapshot.battery >= 0 {
                            let pct = min(100, max(0, snapshot.battery))
                            let bucket = pct < 25 ? 0 : pct < 50 ? 25 : pct < 75 ? 50 : 100
                            let batteryIcon = snapshot.charging
                                ? "battery.100.bolt"
                                : "battery.\(bucket).percent"
                            metric(icon: batteryIcon, label: "BAT",
                                   value: "\(pct)%", tint: pct < 20 ? .red : .yellow)
                        }
                    }
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 30)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 90)
        }
    }

    private func metric(icon: String, label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(tint)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.5))
        }
    }
}
