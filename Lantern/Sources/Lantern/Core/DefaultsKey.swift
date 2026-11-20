// DefaultsKey.swift — Type-safe UserDefaults keys

import Foundation

/// Centralized UserDefaults keys for Lantern preferences
public enum DefaultsKey: String {
    // MARK: - Onboarding
    case onboarded = "lantern_onboarded"
    case onboardedStep = "lantern_onboarded_step"
    
    // MARK: - Appearance
    case panelOpacity = "lantern_panel_opacity"
    case panelPosition = "lantern.panel.position"
    case showAnimations = "lantern_show_animations"
    
    // MARK: - Feature enable states (accessors)
    public static func featureEnabledKey(_ featureRawValue: String) -> String {
        "lantern_feature_\(featureRawValue)_enabled"
    }
    
    public static func featureSettingKey(_ featureRawValue: String, key: String) -> String {
        "lantern_feature_\(featureRawValue)_\(key)"
    }
    
    // MARK: - Clipboard
    case clipboardMaxItems = "lantern_clipboard_max_items"
    case clipboardSyncEnabled = "lantern_clipboard_sync_enabled"
    
    // MARK: - Monitor
    case monitorRefreshInterval = "lantern_monitor_refresh_ms"
    
    // MARK: - Mouse/Scroll
    case scrollDirection = "lantern_scroll_direction"
    
    // MARK: - Dynamic Island
    case islandAnimationEnabled = "lantern_island_animation_enabled"
    
    // MARK: - Panel State
    case panelVisible = "lantern_panel_visible"
}
