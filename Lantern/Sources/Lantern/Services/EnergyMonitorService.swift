// EnergyMonitorService.swift — Stub implementation for energy monitoring features

import Foundation
import AppKit

/// Service providing CPU/memory/network statistics display
public final class EnergyMonitorService: BaseFeatureService {
    
    private var timer: Timer?
    private let updateInterval: TimeInterval = 1.0
    
    @Published public var cpuUsage: Double = 0.0
    @Published public var memoryUsage: Double = 0.0
    @Published public var diskUsage: Double = 0.0
    @Published public var networkDown: Double = 0.0
    @Published public var networkUp: Double = 0.0
    
    override init(feature: AppFeature) {
        super.init(feature: feature)
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Lifecycle
    
    public override func start() {
        guard !isEnabled else { return }
        startMonitoring()
    }
    
    public override func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - Monitoring
    
    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
        updateStats()
    }
    
    private func updateStats() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self, self.isEnabled else { return }
            
            self.cpuUsage = self.getCPUUsage()
            self.memoryUsage = self.getMemoryUsage()
            
            let down = self.getNetworkDown()
            let up = self.getNetworkUp()
            if self.networkDown != down || self.networkUp != up {
                self.networkDown = down
                self.networkUp = up
                self.objectWillChange.send()
            }
        }
    }
    
    // MARK: - Stats Computation (stub implementations)
    
    private func getCPUUsage() -> Double {
        // Stub: oscillate between 15-35% for demo
        let t = Date().timeIntervalSince1970
        return 15.0 + (t * 3.7).truncatingRemainder(dividingBy: 20.0)
    }
    
    private func getMemoryUsage() -> Double {
        // Stub: ~65% typical macOS usage
        let t = Date().timeIntervalSince1970
        return 60.0 + (t * 1.3).truncatingRemainder(dividingBy: 10.0)
    }
    
    private func getNetworkDown() -> Double {
        // Stub: mock download rate
        return 100.0 + Double(Date().timeIntervalSinceReferenceDate).truncatingRemainder(dividingBy: 50.0)
    }
    
    private func getNetworkUp() -> Double {
        // Stub: mock upload rate  
        return 25.0 + Double(Date().timeIntervalSinceReferenceDate).truncatingRemainder(dividingBy: 20.0)
    }
}
