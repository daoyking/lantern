// DynamicIslandView.swift — Dynamic Island preview component (macOS 15+)

import SwiftUI

/// Preview of the simulated Dynamic Island showing system metrics
struct DynamicIslandView: View {
    @StateObject private var service: DynamicIslandService
    init() {
        _service = StateObject(wrappedValue: DynamicIslandService(feature: .dynamicIslandEnabled))
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Text(L("island.preview", "Dynamic Island Preview"))
                .font(.headline)
            
            // Compact mode
            HStack {
                Text(L("island.compact", "Compact:"))
                    .frame(width: 60, alignment: .leading)
                DynamicIslandCompact(service: service)
            }
            
            // Expanded mode
            HStack {
                Text(L("island.expanded", "Expanded:"))
                    .frame(width: 60, alignment: .leading)
                DynamicIslandExpanded(service: service)
            }
            
            // Controls
            HStack(spacing: 12) {
                Button(L("island.toggleMode", "Toggle Mode")) {
                    service.toggleMode()
                }
                .buttonStyle(.bordered)
                
                Button(L("island.setCPU", "Set CPU")) {
                    service.setContent(.cpuUsage)
                }
                .buttonStyle(.bordered)
                
                Button(L("island.setMemory", "Set Memory")) {
                    service.setContent(.memoryUsage)
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            service.updateMetrics(cpu: 45, memory: 62, battery: 88, volume: 50)
        }
    }
}

// MARK: - Compact Island

struct DynamicIslandCompact: View {
    let service: DynamicIslandService
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black)
                .frame(width: 120, height: 38)
            
            if let content = service.activeContent {
                HStack {
                    Image(systemName: content.icon)
                        .font(.system(size: 12))
                        .foregroundColor(content.color)
                    Text(isMetricFor(content))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                }
            } else {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.green)
            }
        }
    }
    
    private func isMetricFor(_ content: DynamicIslandService.IslandContent) -> String {
        switch content {
        case .cpuUsage: return "\(Int(service.cpuPercent))%"
        case .memoryUsage: return "\(Int(service.memoryPercent))%"
        case .batteryLevel: return "\(Int(service.batteryPercent))%"
        case .volumeLevel: return "\(Int(service.volumePercent))%"
        case .networkSpeed: return "+\(Int(service.networkUploadKBps))/−\(Int(service.networkDownloadKBps))"
        }
    }
}

// MARK: - Expanded Island

struct DynamicIslandExpanded: View {
    let service: DynamicIslandService
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.black)
                .frame(width: 220, height: 50)
            
            if let content = service.activeContent {
                HStack(spacing: 12) {
                    Image(systemName: content.icon)
                        .font(.system(size: 14))
                        .foregroundColor(content.color)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("island.content.\(content.rawValue)", content.rawValue))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(metricValue(for: content))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 12)
            } else {
                HStack(spacing: 16) {
                    MetricTile(icon: "cpu.fill", value: "\(Int(service.cpuPercent))%", color: .orange)
                    Divider().frame(height: 20)
                    MetricTile(icon: "memorychip.fill", value: "\(Int(service.memoryPercent))%", color: .purple)
                }
                .padding(.horizontal, 12)
            }
        }
    }
    
    private func metricValue(for content: DynamicIslandService.IslandContent) -> String {
        switch content {
        case .cpuUsage: return "\(Int(service.cpuPercent))%"
        case .memoryUsage: return "\(Int(service.memoryPercent))%"
        case .batteryLevel: return "\(Int(service.batteryPercent))%"
        case .volumeLevel: return "\(Int(service.volumePercent))%"
        case .networkSpeed: return "+\(Int(service.networkUploadKBps))k/s"
        }
    }
}

// MARK: - Helper Views

private struct MetricTile: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    DynamicIslandView()
        .preferredColorScheme(.dark)
        .frame(width: 400, height: 300)
}
#endif
