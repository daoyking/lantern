// DynamicIslandView.swift — the island's face: notch-shaped, live slots
//
// Rendered inside the service's floating panel. Idle state is a plain
// black slab matching the hardware notch — no content, no shadow, so it
// blends in as "the original notch". Tapping expands the slab to show
// every enabled slot (time, date, weather, volume, cpu, memory, battery,
// network) with values; each slot is individually toggleable from the
// island tab via plain UserDefaults keys, and the service widens the
// panel to match, so nothing clips.

import SwiftUI

struct DynamicIslandFace: View {
    @ObservedObject var service: DynamicIslandService
    @AppStorage(DefaultsKey.islandShowTime.rawValue) private var showTime = true
    @AppStorage(DefaultsKey.islandShowDate.rawValue) private var showDate = false
    @AppStorage(DefaultsKey.islandShowWeather.rawValue) private var showWeather = false
    @AppStorage(DefaultsKey.islandShowVolume.rawValue) private var showVolume = false
    @AppStorage(DefaultsKey.islandShowCPU.rawValue) private var showCPU = true
    @AppStorage(DefaultsKey.islandShowMemory.rawValue) private var showMemory = true
    @AppStorage(DefaultsKey.islandShowBattery.rawValue) private var showBattery = true
    @AppStorage(DefaultsKey.islandShowNetwork.rawValue) private var showNetwork = true

    private enum IslandSlot { case time, date, weather, volume, cpu, memory, battery, network }

    /// Fixed priority order — enabled slots surface left to right.
    private var enabledSlots: [IslandSlot] {
        var slots: [IslandSlot] = []
        if showTime { slots.append(.time) }
        if showDate { slots.append(.date) }
        if showWeather, service.weatherTempC != nil { slots.append(.weather) }
        if showVolume, service.volumePercent >= 0 { slots.append(.volume) }
        if showCPU { slots.append(.cpu) }
        if showMemory { slots.append(.memory) }
        if showBattery, service.batteryPercent >= 0 { slots.append(.battery) }
        if showNetwork { slots.append(.network) }
        return slots
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.92))
                // The real notch casts no shadow — only the expanded state
                // floats above the menu bar and gets one.
                .shadow(color: service.expanded ? .black.opacity(0.35) : .clear,
                        radius: 6, y: 2)

            if service.expanded {
                expandedContent
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { service.toggleExpanded() }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: service.expanded)
    }

    // MARK: - Expanded: every enabled slot with its value

    private var expandedContent: some View {
        HStack(spacing: 14) {
            ForEach(Array(enabledSlots.enumerated()), id: \.offset) { _, slot in
                expandedSlot(slot)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func expandedSlot(_ slot: IslandSlot) -> some View {
        switch slot {
        case .time:
            VStack(spacing: 2) {
                Text(Self.timeFormatter.string(from: service.now))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                Text(L("island.time", "Time"))
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.55))
            }
        case .date:
            VStack(spacing: 2) {
                Text(Self.dateFormatter.string(from: service.now))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                Text(L("island.date", "Date"))
                    .font(.system(size: 8))
                    .foregroundColor(.white.opacity(0.55))
            }
        case .weather:
            if let temp = service.weatherTempC {
                metric(icon: IslandWeatherService.symbol(for: service.weatherCode ?? 3),
                       color: .cyan,
                       label: L("island.weather", "Weather"),
                       value: String(format: "%.0f°", temp))
            }
        case .volume:
            metric(icon: service.volumeMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                   color: service.volumeMuted ? .orange : .white,
                   label: L("island.volume", "Volume"),
                   value: service.volumeMuted
                       ? L("island.muted", "Muted")
                       : "\(Int(service.volumePercent))%")
        case .cpu:
            metric(icon: "cpu.fill", color: cpuColor,
                   label: L("island.cpu", "CPU"),
                   value: "\(Int(service.cpuPercent))%")
        case .memory:
            metric(icon: "memorychip.fill", color: .purple,
                   label: L("island.memory", "Memory"),
                   value: "\(Int(service.memoryPercent))%")
        case .battery:
            metric(icon: "bolt.fill", color: .green,
                   label: L("island.battery", "Battery"),
                   value: "\(Int(service.batteryPercent))%")
        case .network:
            metric(icon: "arrow.down", color: .teal,
                   label: L("island.network", "Net"),
                   value: String(format: "%.0fKB/s", service.networkDownKBps))
        }
    }

    private func metric(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    // MARK: - Helpers

    private var cpuColor: Color {
        switch service.cpuPercent {
        case ..<50: return .green
        case ..<80: return .orange
        default: return .red
        }
    }

    // Cached formatters — the face re-renders every second via service.now.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MdEEE") // e.g. 12/22 周一
        return f
    }()
}
