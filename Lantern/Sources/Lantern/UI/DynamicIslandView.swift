// DynamicIslandView.swift — the island's face: one pill, live slots
//
// Rendered inside the service's floating panel. Every slot (time, date,
// volume, cpu, memory, battery, network) is individually toggleable from the
// island tab via plain UserDefaults keys; compact shows the first three
// enabled slots as glyphs, expanded shows all of them. The service widens
// the panel to match, so nothing clips.

import SwiftUI

struct DynamicIslandFace: View {
    @ObservedObject var service: DynamicIslandService
    @AppStorage(DefaultsKey.islandShowTime.rawValue) private var showTime = true
    @AppStorage(DefaultsKey.islandShowDate.rawValue) private var showDate = false
    @AppStorage(DefaultsKey.islandShowVolume.rawValue) private var showVolume = false
    @AppStorage(DefaultsKey.islandShowCPU.rawValue) private var showCPU = true
    @AppStorage(DefaultsKey.islandShowMemory.rawValue) private var showMemory = true
    @AppStorage(DefaultsKey.islandShowBattery.rawValue) private var showBattery = true
    @AppStorage(DefaultsKey.islandShowNetwork.rawValue) private var showNetwork = true

    private enum IslandSlot { case time, date, volume, cpu, memory, battery, network }

    /// Fixed priority order — enabled slots surface left to right.
    private var enabledSlots: [IslandSlot] {
        var slots: [IslandSlot] = []
        if showTime { slots.append(.time) }
        if showDate { slots.append(.date) }
        if showVolume, service.volumePercent >= 0 { slots.append(.volume) }
        if showCPU { slots.append(.cpu) }
        if showMemory { slots.append(.memory) }
        if showBattery, service.batteryPercent >= 0 { slots.append(.battery) }
        if showNetwork { slots.append(.network) }
        return slots
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.black.opacity(0.92))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)

            if service.expanded {
                expandedContent
            } else {
                compactContent
            }
        }
        .contentShape(Capsule())
        .onTapGesture { service.toggleExpanded() }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: service.expanded)
    }

    // MARK: - Compact: at most three glyphs (clock spelled out, rest icons)

    private var compactContent: some View {
        HStack(spacing: 10) {
            ForEach(Array(enabledSlots.prefix(3).enumerated()), id: \.offset) { _, slot in
                compactSlot(slot)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func compactSlot(_ slot: IslandSlot) -> some View {
        switch slot {
        case .time:
            Text(Self.timeFormatter.string(from: service.now))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)
        case .date:
            Image(systemName: "calendar")
                .font(.system(size: 11))
                .foregroundColor(.pink)
        case .volume:
            Image(systemName: service.volumeMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11))
                .foregroundColor(service.volumeMuted ? .orange : .white)
        case .cpu:
            Image(systemName: "cpu.fill")
                .font(.system(size: 11))
                .foregroundColor(cpuColor)
        case .memory:
            Image(systemName: "memorychip.fill")
                .font(.system(size: 11))
                .foregroundColor(.purple)
        case .battery:
            batteryGlyph
        case .network:
            Image(systemName: "arrow.down")
                .font(.system(size: 11))
                .foregroundColor(.teal)
        }
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

    private var batteryGlyph: some View {
        Image(systemName: batteryIcon)
            .font(.system(size: 12))
            .foregroundColor(service.batteryPercent < 20 ? .red : .green)
    }

    private var batteryIcon: String {
        switch service.batteryPercent {
        case ..<20: return "battery.0percent"
        case ..<50: return "battery.25percent"
        case ..<80: return "battery.50percent"
        default: return "battery.100percent"
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
