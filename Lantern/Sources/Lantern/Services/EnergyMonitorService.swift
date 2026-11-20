// EnergyMonitorService.swift — Real CPU/memory/network/battery telemetry.
//
// All numbers come from SystemMetrics (Mach / IOKit / BSD). No fabricated
// or time-based "demo" values remain.

import Foundation
import AppKit
import Combine

/// Service providing real CPU/memory/network statistics display.
public final class EnergyMonitorService: BaseFeatureService {

    private var timer: Timer?
    private let updateInterval: TimeInterval = 1.0
    private let collector = SystemMetrics()

    @Published public var cpuUsage: Double = 0.0
    @Published public var memoryUsage: Double = 0.0
    @Published public var diskUsage: Double = 0.0
    @Published public var networkDown: Double = 0.0
    @Published public var networkUp: Double = 0.0
    @Published public var batteryPercent: Double = -1
    @Published public var batteryCharging: Bool = false

    override init(feature: AppFeature) {
        super.init(feature: feature)
    }

    deinit {
        stop()
    }

    // MARK: - Lifecycle

    public override func start() {
        guard timer == nil else { return }
        startMonitoring()
    }

    public override func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        // Establish a baseline on the main thread so the first delta is valid.
        _ = collector.snapshot()
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
        updateStats()
    }

    private func updateStats() {
        let snapshot = collector.snapshot()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.cpuUsage = snapshot.cpuUsage
            self.memoryUsage = snapshot.memoryPressure
            self.networkDown = snapshot.networkDownKBps
            self.networkUp = snapshot.networkUpKBps
            self.batteryPercent = snapshot.batteryPercent
            self.batteryCharging = snapshot.batteryCharging
        }
    }

    // MARK: - Formatted accessors for UI

    public var memoryUsedText: String {
        let s = collector.snapshot()
        return String(format: "%.1f / %.1f GB", s.memoryUsedGB, s.memoryTotalGB)
    }

    /// Human-readable network rate string.
    public var networkDownText: String { Self.formatRate(networkDown) }
    public var networkUpText: String { Self.formatRate(networkUp) }

    public static func formatRate(_ kbPerSec: Double) -> String {
        if kbPerSec >= 1024 {
            return String(format: "%.1f MB/s", kbPerSec / 1024.0)
        }
        return String(format: "%.0f KB/s", kbPerSec)
    }
}
