// AppFeature.swift — Feature registry enum
// Maps each menu bar utility to a persistent identifier

import Foundation

/// Central feature catalog: all Lantern capabilities are listed here.
/// Each case's rawValue becomes the UserDefaults key prefix.
public enum AppFeature: String, CaseIterable, Identifiable {
    // ── Windows & Dock ───────────────────────────────────────────────
    case autoHideDock = "autoHideDock"
    case minimizeOnClickDock = "minimizeOnClickDock"
    case dockSize = "dockSize"
    case windowSnap = "windowSnap"
    case hideAllWindows = "hideAllWindows"
    case forceQuitDialog = "forceQuitDialog"

    // ── Mouse & Keyboard ─────────────────────────────────────────────
    case invertScroll = "invertScroll"
    case mouseSensitivity = "mouseSensitivity"
    case keyboardRepeatRate = "keyboardRepeatRate"
    case doubleClickSpeed = "doubleClickSpeed"
    case cursorSize = "cursorSize"

    // ── Clipboard ────────────────────────────────────────────────────
    case clipboardHistory = "clipboardHistory"
    case pasteAsPlainText = "pasteAsPlainText"
    case syncClipboardAcrossDevices = "syncClipboardAcrossDevices"

    // ── Sound ────────────────────────────────────────────────────────
    case volumeMixer = "volumeMixer"
    case inputDeviceSelect = "inputDeviceSelect"
    case audioToggle = "audioToggle"
    case notificationSound = "notificationSound"
    
    // ── Window Management (Phase 6) ──────────────────────────────────
    case windowMinimizeAll = "windowMinimizeAll"
    case windowSwitchApp = "windowSwitchApp"
    
    // ── Sound Controls (Phase 6) ─────────────────────────────────────
    case soundVolumeUp = "soundVolumeUp"
    case soundVolumeDown = "soundVolumeDown"
    case soundMuteToggle = "soundMuteToggle"

    // ── Energy Display ───────────────────────────────────────────────
    case cpuMonitor = "cpuMonitor"
    case gpuMonitor = "gpuMonitor"
    case memoryMonitor = "memoryMonitor"
    case networkMonitor = "networkMonitor"
    case batteryDisplay = "batteryDisplay"

    // ── Tools ────────────────────────────────────────────────────────
    case keepAwake = "keepAwake"
    case portControl = "portControl"
    case processKiller = "processKiller"
    case fileShredder = "fileShredder"
    case colorPicker = "colorPicker"

    // ── Dynamic Island ───────────────────────────────────────────────
    case dynamicIslandEnabled = "dynamicIslandEnabled"
    case dynamicIslandShowCPU = "dynamicIslandShowCPU"
    case dynamicIslandShowBattery = "dynamicIslandShowBattery"

    /// Unique ID for SwiftUI list identification
    public var id: String { rawValue }

    // ── Group classification ─────────────────────────────────────────
    public var group: FeatureGroup {
        switch self {
        case .autoHideDock, .minimizeOnClickDock, .dockSize,
             .windowSnap, .hideAllWindows, .forceQuitDialog:
            return .windowsDock
        case .invertScroll, .mouseSensitivity, .keyboardRepeatRate,
             .doubleClickSpeed, .cursorSize:
            return .mouseKeyboard
        case .clipboardHistory, .pasteAsPlainText, .syncClipboardAcrossDevices:
            return .clipboard
        case .volumeMixer, .inputDeviceSelect, .audioToggle, .notificationSound,
             .windowMinimizeAll, .windowSwitchApp,
             .soundVolumeUp, .soundVolumeDown, .soundMuteToggle:
            return .sound
        case .cpuMonitor, .gpuMonitor, .memoryMonitor,
             .networkMonitor, .batteryDisplay:
            return .energyDisplay
        case .keepAwake, .portControl, .processKiller,
             .fileShredder, .colorPicker:
            return .tools
        case .dynamicIslandEnabled, .dynamicIslandShowCPU, .dynamicIslandShowBattery:
            return .dynamicIsland
        }
    }

    /// Human-readable label displayed in the menu panel
    public var displayName: String {
        switch self {
        case .autoHideDock: return "Auto-Hide Dock"
        case .minimizeOnClickDock: return "Minimize on Dock Click"
        case .dockSize: return "Dock Size"
        case .windowSnap: return "Window Snap"
        case .hideAllWindows: return "Hide All Windows"
        case .forceQuitDialog: return "Force Quit Dialog"
        case .invertScroll: return "Invert Scroll Direction"
        case .mouseSensitivity: return "Mouse Sensitivity"
        case .keyboardRepeatRate: return "Key Repeat Rate"
        case .doubleClickSpeed: return "Double-Click Speed"
        case .cursorSize: return "Cursor Size"
        case .clipboardHistory: return "Clipboard History"
        case .pasteAsPlainText: return "Paste as Plain Text"
        case .syncClipboardAcrossDevices: return "Sync Clipboard"
        case .volumeMixer: return "Volume Mixer"
        case .inputDeviceSelect: return "Input Device"
        case .audioToggle: return "Audio Toggle"
        case .notificationSound: return "Notification Sound"
        case .windowMinimizeAll: return "Minimize All Windows"
        case .windowSwitchApp: return "Switch App (Cmd+Tab)"
        case .soundVolumeUp: return "Volume Up +5%"
        case .soundVolumeDown: return "Volume Down -5%"
        case .soundMuteToggle: return "Toggle Mute"
        case .cpuMonitor: return "CPU Monitor"
        case .gpuMonitor: return "GPU Monitor"
        case .memoryMonitor: return "Memory Monitor"
        case .networkMonitor: return "Network Monitor"
        case .batteryDisplay: return "Battery Display"
        case .keepAwake: return "Keep Awake"
        case .portControl: return "Port Control"
        case .processKiller: return "Process Killer"
        case .fileShredder: return "File Shredder"
        case .colorPicker: return "Color Picker"
        case .dynamicIslandEnabled: return "Dynamic Island"
        case .dynamicIslandShowCPU: return "Island: CPU"
        case .dynamicIslandShowBattery: return "Island: Battery"
        }
    }

    /// Description shown in tooltip or settings panel
    public var descriptionText: String {
        switch self {
        case .autoHideDock: return "Automatically hide the Dock when space is needed"
        case .minimizeOnClickDock: return "Minimize windows when clicking their Dock icon"
        case .dockSize: return "Adjust Dock icon size"
        case .windowSnap: return "Snap windows to screen edges for easier resizing"
        case .hideAllWindows: return "Minimize all windows with a single click"
        case .forceQuitDialog: return "Show enhanced force-quit dialog"
        case .invertScroll: return "Reverse scroll direction for mouse/trackpad"
        case .mouseSensitivity: return "Adjust pointer speed"
        case .keyboardRepeatRate: return "Change keyboard repeat delay and rate"
        case .doubleClickSpeed: return "Adjust double-click timing threshold"
        case .cursorSize: return "Increase or decrease cursor size"
        case .clipboardHistory: return "Maintain clipboard history across sessions"
        case .pasteAsPlainText: return "Always paste content as unformatted text"
        case .syncClipboardAcrossDevices: return "Sync clipboard via iCloud (experimental)"
        case .volumeMixer: return "Control per-app volume levels"
        case .inputDeviceSelect: return "Quickly switch between input devices"
        case .audioToggle: return "Mute/unmute system audio"
        case .notificationSound: return "Toggle notification sounds"
        case .windowMinimizeAll: return "Minimize all windows with one click"
        case .windowSwitchApp: return "Switch to next app (like Cmd+Tab)"
        case .soundVolumeUp: return "Increase system volume by 5%"
        case .soundVolumeDown: return "Decrease system volume by 5%"
        case .soundMuteToggle: return "Toggle system mute state"
        case .cpuMonitor: return "Display real-time CPU usage in status bar"
        case .gpuMonitor: return "Display GPU utilization"
        case .memoryMonitor: return "Show available memory"
        case .networkMonitor: return "Track upload/download speeds"
        case .batteryDisplay: return "Show battery percentage and charging state"
        case .keepAwake: return "Prevent Mac from sleeping automatically"
        case .portControl: return "Disable/enable USB ports (admin required)"
        case .processKiller: return "Kill misbehaving processes from menu bar"
        case .fileShredder: return "Securely delete files beyond recovery"
        case .colorPicker: return "Pick colors from anywhere on screen"
        case .dynamicIslandEnabled: return "Enable Dynamic Island integration"
        case .dynamicIslandShowCPU: return "Show CPU stats in Dynamic Island"
        case .dynamicIslandShowBattery: return "Show battery status in Dynamic Island"
        }
    }
}

/// Groups features into top-level tabs of the menu panel
public enum FeatureGroup: String, CaseIterable, Identifiable {
    case windowsDock = "Windows & Dock"
    case mouseKeyboard = "Mouse & Keyboard"
    case clipboard = "Clipboard"
    case sound = "Sound"
    case energyDisplay = "Energy Display"
    case tools = "Tools"
    case dynamicIsland = "Dynamic Island"

    public var id: String { rawValue }

    /// Compact label for the narrow tab bar (full rawValue overflows at 320pt)
    public var shortLabel: String {
        switch self {
        case .windowsDock: return "Windows"
        case .mouseKeyboard: return "Mouse"
        case .clipboard: return "Clipboard"
        case .sound: return "Sound"
        case .energyDisplay: return "Energy"
        case .tools: return "Tools"
        case .dynamicIsland: return "Island"
        }
    }

    public var icon: String {
        switch self {
        case .windowsDock: return "square.stack.3d.up.fill"
        case .mouseKeyboard: return "keyboard.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .sound: return "speaker.wave.3.fill"
        case .energyDisplay: return "bolt.fill"
        case .tools: return "wrench.adjustable.fill"
        case .dynamicIsland: return "iphone.gen3.radiowaves.left.and.right.fill"
        }
    }
}
