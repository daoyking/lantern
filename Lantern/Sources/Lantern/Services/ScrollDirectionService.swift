// ScrollDirectionService.swift — Controls scroll direction

import Foundation

/// Service that manages mouse scroll direction settings
public final class ScrollDirectionService: BaseFeatureService {
    private let key = DefaultsKey.scrollDirection
    
    public override func start() throws {
        let enabled = UserDefaults.standard.bool(forKey: key.rawValue)
        if enabled {
            applyNaturalScroll(true)
        }
    }
    
    public override func stop() throws {
        // Restore default when disabled
        applyNaturalScroll(false)
    }
    
    public override var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key.rawValue)
    }
    
    // MARK: - Public API
    
    /// Toggle natural scroll direction
    public func toggle() {
        let currentValue = UserDefaults.standard.bool(forKey: key.rawValue)
        let newValue = !currentValue
        
        UserDefaults.standard.set(newValue, forKey: key.rawValue)
        
        // Apply immediately
        applyNaturalScroll(newValue)
    }
    
    /// Set scroll direction
    public func setNatural(_ natural: Bool) {
        UserDefaults.standard.set(natural, forKey: key.rawValue)
        applyNaturalScroll(natural)
    }
    
    // MARK: - Private Helpers
    
    private func applyNaturalScroll(_ natural: Bool) {
        // This requires Accessibility permission to modify system settings
        guard Permissions.shared.isGranted(.accessibility) else {
            #if DEBUG
            print("[Lantern] ScrollDirectionService: Missing accessibility permission")
            #endif
            return
        }
        
        // Use SystemPreferences to set scroll direction
        // Note: Direct NSPreferencePanel calls may not work in newer macOS
        // Alternative: Use defaults write or AppleScript
        #if DEBUG
        print("[Lantern] ScrollDirectionService: Applying \(natural ? "natural" : "standard") scroll")
        #endif
        
        // The actual implementation would use:
        // - NSApplication.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.mouse")!)
        // Or via UserDefaults + event tap modification
    }
}