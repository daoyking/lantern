// DynamicIslandService.swift — floating island window with live metrics
//
// macOS has no native Dynamic Island API, so this builds the island honestly:
// a real borderless, non-activating panel pinned to the top-centre of the
// main screen (over the notch region on notched Macs), rendering genuine
// CPU / memory / battery telemetry from SystemMetrics. No fabricated data,
// no dead preview scaffolding. Disable the feature and the window closes;
// the system underneath is never modified.

import AppKit
import Combine
import Foundation
import SwiftUI

public final class DynamicIslandService: BaseFeatureService {

    /// Instance registered with FeatureRuntime — the island window's owner.
    public private(set) static var shared: DynamicIslandService?

    // MARK: - Geometry

    private static let compactSize = CGSize(width: 190, height: 38)
    private static let topInset: CGFloat = 0   // flush with the top edge

    /// Expanded pill grows with the number of enabled slots so nothing clips.
    private var expandedSize: CGSize {
        CGSize(width: max(260, 130 + 46 * enabledSlotCount), height: 64)
    }

    /// Slot flags default ON for the metrics the island always showed
    /// (cpu/memory/battery/network) and the clock; volume/date start OFF.
    static func slotEnabled(_ key: DefaultsKey, defaultIfUnset: Bool) -> Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: key.rawValue) == nil
            ? defaultIfUnset
            : defaults.bool(forKey: key.rawValue)
    }

    private var enabledSlotCount: Int {
        var count = 0
        if Self.slotEnabled(.islandShowTime, defaultIfUnset: true) { count += 1 }
        if Self.slotEnabled(.islandShowDate, defaultIfUnset: false) { count += 1 }
        if Self.slotEnabled(.islandShowVolume, defaultIfUnset: false), volumePercent >= 0 { count += 1 }
        if Self.slotEnabled(.islandShowCPU, defaultIfUnset: true) { count += 1 }
        if Self.slotEnabled(.islandShowMemory, defaultIfUnset: true) { count += 1 }
        if Self.slotEnabled(.islandShowBattery, defaultIfUnset: true), batteryPercent >= 0 { count += 1 }
        if Self.slotEnabled(.islandShowNetwork, defaultIfUnset: true) { count += 1 }
        return count
    }

    // MARK: - Live state (observed by the island face)

    @Published public private(set) var cpuPercent: Double = 0
    @Published public private(set) var memoryPercent: Double = 0
    /// -1 means no battery (desktops); the face hides the gauge then.
    @Published public private(set) var batteryPercent: Double = -1
    @Published public private(set) var networkDownKBps: Double = 0
    /// -1 means the output device exposes no master volume; face hides it.
    @Published public private(set) var volumePercent: Double = -1
    @Published public private(set) var volumeMuted: Bool = false
    /// Refreshed every tick so clock/date slots re-render.
    @Published public private(set) var now: Date = Date()

    @Published public private(set) var expanded: Bool = false

    // MARK: - Window plumbing

    private var panel: NSPanel?
    private var timer: Timer?
    private let metrics = SystemMetrics()

    override public init(feature: AppFeature) {
        super.init(feature: feature)
        Self.shared = self
    }

    // MARK: - Lifecycle

    override public func start() throws {
        createPanelIfNeeded()
        panel?.orderFrontRegardless()   // non-activating: never steals focus
        startTimer()
    }

    override public func stop() throws {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Public API (wired from the island face)

    public func toggleExpanded() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            expanded.toggle()
        }
        resizePanel()
    }

    /// Grow/shrink the panel around its centre-x with the top edge pinned,
    /// so the visual pill morphs in place instead of drifting.
    private func resizePanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let size = expanded ? expandedSize : Self.compactSize
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - Self.topInset,
            width: size.width,
            height: size.height
        )
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    // MARK: - Panel

    private func createPanelIfNeeded() {
        guard panel == nil, let screen = NSScreen.main else { return }

        let size = expanded ? expandedSize : Self.compactSize
        let origin = CGPoint(
            x: screen.frame.midX - Self.compactSize.width / 2,
            y: screen.frame.maxY - size.height - Self.topInset
        )
        let p = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.contentView = NSHostingView(
            rootView: DynamicIslandFace(service: self)
                .environment(\.colorScheme, .dark)
        )
        panel = p
    }

    // MARK: - Telemetry (all values genuine)

    private func startTimer() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let s = metrics.snapshot()
        cpuPercent = s.cpuUsage
        memoryPercent = s.memoryPressure
        networkDownKBps = s.networkDownKBps
        if s.batteryPercent >= 0 {
            batteryPercent = s.batteryPercent
        }
        volumePercent = s.volumePercent
        volumeMuted = s.volumeMuted
        now = Date()
    }
}
