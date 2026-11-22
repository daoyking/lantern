// DynamicIslandView.swift — the island's face: one pill, live metrics
//
// Rendered inside the service's floating panel. Compact shows CPU + battery;
// clicking morphs to expanded, adding memory and network. Content switches
// (island_show_cpu / island_show_battery) are plain UserDefaults so the
// panel tab can toggle them without touching window lifecycle.

import SwiftUI

struct DynamicIslandFace: View {
    @ObservedObject var service: DynamicIslandService
    @AppStorage(DefaultsKey.islandShowCPU.rawValue) private var showCPU = true
    @AppStorage(DefaultsKey.islandShowBattery.rawValue) private var showBattery = true

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

    // MARK: - Compact: icon + CPU, battery glyph on the right

    private var compactContent: some View {
        HStack(spacing: 10) {
            if showCPU {
                HStack(spacing: 4) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 11))
                        .foregroundColor(cpuColor)
                    Text("\(Int(service.cpuPercent))%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
            if showBattery, service.batteryPercent >= 0 {
                batteryGlyph
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Expanded: labelled rows for every live metric

    private var expandedContent: some View {
        HStack(spacing: 14) {
            if showCPU {
                metric(icon: "cpu.fill", color: cpuColor,
                       label: L("island.cpu", "CPU"),
                       value: "\(Int(service.cpuPercent))%")
            }
            metric(icon: "memorychip.fill", color: .purple,
                   label: L("island.memory", "Memory"),
                   value: "\(Int(service.memoryPercent))%")
            if showBattery, service.batteryPercent >= 0 {
                metric(icon: "bolt.fill", color: .green,
                       label: L("island.battery", "Battery"),
                       value: "\(Int(service.batteryPercent))%")
            }
            metric(icon: "arrow.down", color: .teal,
                   label: L("island.network", "Net"),
                   value: String(format: "%.0fKB/s", service.networkDownKBps))
        }
        .padding(.horizontal, 16)
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
}
