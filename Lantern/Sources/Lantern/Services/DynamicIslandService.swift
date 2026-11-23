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

    /// Height of the hardware-notch zone (safeAreaInsets.top on notched
    /// Macs). The physical notch hides anything drawn in this band at the
    /// screen's horizontal centre, so expanded content must stay below it.
    static var notchHeight: CGFloat {
        let h = NSScreen.main?.safeAreaInsets.top ?? 0
        return h >= 24 ? h : 32
    }

    /// Idle state carries the clock wing: time / date / weather live on the
    /// idle slab (user request: they leave the expanded hub entirely). The
    /// slab is wide enough for the hardware notch (184pt) plus a right wing
    /// (~150pt) that hosts the row, centred like the notch itself. Constant
    /// width keeps the idle look stable whether or not weather is available.
    private static var compactSize: CGSize {
        CGSize(width: 460, height: notchHeight)
    }
    private static let topInset: CGFloat = 0   // flush with the top edge

    /// Expanded hub: one fixed-width glass card in the Sapphire notch-hub
    /// style — hero zone (music or clock) over a scrolling chip row, so no
    /// slot combination can ever clip or squeeze the layout.
    private var expandedSize: CGSize {
        CGSize(width: 340, height: Self.notchHeight + 88)
    }

    /// Slot flags default ON for the metrics the island always showed
    /// (cpu/memory/battery/network) and the clock; volume/date start OFF.
    static func slotEnabled(_ key: DefaultsKey, defaultIfUnset: Bool) -> Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: key.rawValue) == nil
            ? defaultIfUnset
            : defaults.bool(forKey: key.rawValue)
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
    /// Nil means no weather reading yet (slot off, or location denied) —
    /// the face hides the slot then.
    @Published public private(set) var weatherTempC: Double?
    @Published public private(set) var weatherCode: Int?

    /// Next-event slot presence — mirrors CalendarService so the expanded
    /// panel reserves width for the cell only when a reading actually exists.
    @Published public private(set) var calendarHasEvent: Bool = false
    /// Refreshed every tick so clock/date slots re-render.
    @Published public private(set) var now: Date = Date()

    @Published public private(set) var expanded: Bool = false

    // MARK: - Window plumbing

    private var panel: NSPanel?
    private var timer: Timer?
    private let metrics = SystemMetrics()
    /// Weather polling runs only while the island does, and only when the
    /// slot is on (lazy: no CLLocationManager touch until the island starts).
    private lazy var weather = IslandWeatherService()

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
        weather.setRunning(false)
        CalendarService.shared.setRunning(false)
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
        // Weather slot: start/stop the poller to match the toggle, then
        // mirror its readings into published state for the face.
        let wantWeather = Self.slotEnabled(.islandShowWeather, defaultIfUnset: false)
        weather.setRunning(wantWeather)
        weatherTempC = wantWeather ? weather.temperatureC : nil
        weatherCode = wantWeather ? weather.weatherCode : nil
        // Music slot: same slot-driven pattern — poll AppleScript only
        // while the slot is on; the controller lives in FeatureRuntime
        // (created by AppDelegate) so panel actions share one instance.
        let wantMusic = Self.slotEnabled(.islandShowMusic, defaultIfUnset: false)
        if wantMusic {
            MusicControllerService.shared?.setRunning(true)
        } else {
            MusicControllerService.shared?.setRunning(false)
        }
        // Next-event slot: run the calendar poller while the slot is on;
        // mirror whether a reading exists so the panel width matches.
        let wantCalendar = Self.slotEnabled(.islandShowNextEvent, defaultIfUnset: false)
        if wantCalendar {
            CalendarService.shared.setRunning(true)
            CalendarService.shared.refresh()
        } else {
            CalendarService.shared.setRunning(false)
        }
        calendarHasEvent = wantCalendar && CalendarService.shared.nextEvent != nil
        now = Date()
    }
}
