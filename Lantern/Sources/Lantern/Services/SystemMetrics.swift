// SystemMetrics.swift — Real system telemetry via Mach / IOKit / BSD APIs.
//
// Every value here is read from the operating system; no fabricated numbers.
// The math helpers are pure functions so they can be unit-tested without
// touching real hardware state.

import Foundation
import Darwin
import IOKit
import IOKit.ps

// MARK: - Snapshot

/// One sample of live system telemetry.
public struct MetricSnapshot {
    public let cpuUsage: Double          // 0–100 %
    public let memoryPressure: Double    // 0–100 % (used / total)
    public let memoryUsedGB: Double
    public let memoryTotalGB: Double
    public let networkDownKBps: Double   // KB/s since previous sample
    public let networkUpKBps: Double     // KB/s since previous sample
    public let batteryPercent: Double    // 0–100, or -1 on desktops / no battery
    public let batteryCharging: Bool

    public init(
        cpuUsage: Double,
        memoryPressure: Double,
        memoryUsedGB: Double,
        memoryTotalGB: Double,
        networkDownKBps: Double,
        networkUpKBps: Double,
        batteryPercent: Double,
        batteryCharging: Bool
    ) {
        self.cpuUsage = cpuUsage
        self.memoryPressure = memoryPressure
        self.memoryUsedGB = memoryUsedGB
        self.memoryTotalGB = memoryTotalGB
        self.networkDownKBps = networkDownKBps
        self.networkUpKBps = networkUpKBps
        self.batteryPercent = batteryPercent
        self.batteryCharging = batteryCharging
    }
}

// MARK: - Pure math helpers (unit-testable, no I/O)

public enum MetricMath {
    /// Convert two host_cpu_load_info tick samples into a 0–100 utilisation.
    /// `ticks` order is (user, system, idle, nice).
    public static func cpuPercent(
        current: (UInt32, UInt32, UInt32, UInt32),
        previous: (UInt32, UInt32, UInt32, UInt32)
    ) -> Double {
        let user = Int64(current.0) - Int64(previous.0)
        let system = Int64(current.1) - Int64(previous.1)
        let idle = Int64(current.2) - Int64(previous.2)
        let nice = Int64(current.3) - Int64(previous.3)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        let active = user + system + nice
        return min(100, max(0, Double(active) / Double(total) * 100.0))
    }

    /// Byte counter delta over an interval → KB/s. Guards counter wrap / reset.
    public static func rateKBps(current: UInt64, previous: UInt64, interval: Double) -> Double {
        guard interval > 0 else { return 0 }
        guard current >= previous else { return 0 } // interface reset or wrap
        let delta = Double(current - previous)
        return max(0, delta / interval / 1024.0)
    }

    /// Used vs total bytes → percentage 0–100.
    public static func percent(used: UInt64, total: UInt64) -> Double {
        guard total > 0 else { return 0 }
        return min(100, max(0, Double(used) / Double(total) * 100.0))
    }

    public static func gigabytes(_ bytes: UInt64) -> Double {
        Double(bytes) / 1_073_741_824.0
    }
}

// MARK: - Live collector

/// Collects real telemetry. Not thread-safe by itself; callers should sample
/// from a single serial queue (EnergyMonitorService does).
public final class SystemMetrics {

    private var lastCPUTicks: (UInt32, UInt32, UInt32, UInt32)?
    private var lastNetIn: UInt64 = 0
    private var lastNetOut: UInt64 = 0
    private var lastSampleTime: Date?

    public init() {}

    /// Sample every metric. First call establishes baselines (network/cpu deltas read 0).
    public func snapshot() -> MetricSnapshot {
        let now = Date()
        let interval = lastSampleTime.map { now.timeIntervalSince($0) } ?? 1.0
        lastSampleTime = now

        let cpu = readCPUUsage()
        let mem = readMemory()
        let net = readNetwork(interval: interval)
        let bat = readBattery()

        return MetricSnapshot(
            cpuUsage: cpu,
            memoryPressure: MetricMath.percent(used: mem.used, total: mem.total),
            memoryUsedGB: MetricMath.gigabytes(mem.used),
            memoryTotalGB: MetricMath.gigabytes(mem.total),
            networkDownKBps: net.down,
            networkUpKBps: net.up,
            batteryPercent: bat.percent,
            batteryCharging: bat.charging
        )
    }

    // MARK: CPU — host_statistics(HOST_CPU_LOAD_INFO)

    private func readCPUUsage() -> Double {
        var load = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let status = withUnsafeMutablePointer(to: &load) { loadPtr in
            loadPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics(mach_host_self(), host_flavor_t(HOST_CPU_LOAD_INFO), intPtr, &count)
            }
        }
        guard status == KERN_SUCCESS else { return 0 }

        let current = (load.cpu_ticks.0, load.cpu_ticks.1, load.cpu_ticks.2, load.cpu_ticks.3)
        defer { lastCPUTicks = current }
        guard let previous = lastCPUTicks else { return 0 }
        return MetricMath.cpuPercent(current: current, previous: previous)
    }

    // MARK: Memory — host_statistics64(HOST_VM_INFO64)

    private func readMemory() -> (used: UInt64, total: UInt64) {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let status = withUnsafeMutablePointer(to: &stats) { statsPtr in
            statsPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), host_flavor_t(HOST_VM_INFO64), intPtr, &count)
            }
        }
        guard status == KERN_SUCCESS else { return (0, 0) }

        let pageSize = UInt64(vm_page_size)
        // Match Activity Monitor's "Memory Used" = app (active) + wired + compressed.
        // Inactive pages are recently-used but reclaimable, so they count as available.
        let usedPages = UInt64(stats.active_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        let total = ProcessInfo.processInfo.physicalMemory
        return (usedPages * pageSize, total)
    }

    // MARK: Network — getifaddrs (per-interface byte counters)

    private func readNetwork(interval: Double) -> (down: Double, up: Double) {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return (0, 0) }
        defer { freeifaddrs(addresses) }

        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let ifa = current.pointee
            // Skip loopback; it inflates counters with local traffic.
            let name = ifa.ifa_name != nil ? String(cString: ifa.ifa_name) : ""
            if name.hasPrefix("lo") {
                cursor = ifa.ifa_next
                continue
            }
            if let data = ifa.ifa_data {
                let ifData = data.assumingMemoryBound(to: if_data.self).pointee
                bytesIn += UInt64(ifData.ifi_ibytes)
                bytesOut += UInt64(ifData.ifi_obytes)
            }
            cursor = ifa.ifa_next
        }

        let down = MetricMath.rateKBps(current: bytesIn, previous: lastNetIn, interval: interval)
        let up = MetricMath.rateKBps(current: bytesOut, previous: lastNetOut, interval: interval)
        lastNetIn = bytesIn
        lastNetOut = bytesOut
        return (down, up)
    }

    // MARK: Battery — IOPMPowerSource

    private func readBattery() -> (percent: Double, charging: Bool) {
        // IOPSCopyPowerSourcesInfo returns a CFDictionary whose "Power Sources"
        // key holds an array of per-source dictionaries. Bridge through
        // Foundation to avoid fragile CF casts; IOPSGetPowerSourceArray is not
        // exported by this SDK's IOKit.ps module.
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() as? NSDictionary,
              let sources = blob["Power Sources"] as? NSArray else {
            return (-1, false) // desktop / no battery
        }
        for case let source as NSDictionary in sources {
            guard let current = source[kIOPSCurrentCapacityKey as String] as? Int,
                  let maximum = source[kIOPSMaxCapacityKey as String] as? Int,
                  maximum > 0 else { continue }
            let state = source[kIOPSPowerSourceStateKey as String] as? String ?? ""
            let charging = (state == (kIOPSACPowerValue as String))
            return (Double(current) / Double(maximum) * 100.0, charging)
        }
        return (-1, false)
    }
}
