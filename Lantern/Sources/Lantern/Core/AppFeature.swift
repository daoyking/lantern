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
    case timerStart5 = "timerStart5"
    case timerStart10 = "timerStart10"
    case timerStart25 = "timerStart25"
    case musicPlayPause = "musicPlayPause"
    case musicNextTrack = "musicNextTrack"
    case musicPrevTrack = "musicPrevTrack"
    
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
    case eyeBreak = "eyeBreak"
    case quickTimer = "quickTimer"
    case focusMode = "focusMode"

    // ── Dynamic Island ───────────────────────────────────────────────
    case dynamicIslandEnabled = "dynamicIslandEnabled"
    case dynamicIslandShowCPU = "dynamicIslandShowCPU"
    case dynamicIslandShowBattery = "dynamicIslandShowBattery"
    case dynamicIslandShowVolume = "dynamicIslandShowVolume"
    case dynamicIslandShowTime = "dynamicIslandShowTime"
    case dynamicIslandShowDate = "dynamicIslandShowDate"
    case dynamicIslandShowMemory = "dynamicIslandShowMemory"
    case dynamicIslandShowNetwork = "dynamicIslandShowNetwork"
    case dynamicIslandShowWeather = "dynamicIslandShowWeather"
    case dynamicIslandShowMusic = "dynamicIslandShowMusic"
    case dynamicIslandShowNextEvent = "dynamicIslandShowNextEvent"

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
        case .timerStart5, .timerStart10, .timerStart25:
            return .tools
        case .volumeMixer, .inputDeviceSelect, .audioToggle, .notificationSound,
             .windowMinimizeAll, .windowSwitchApp,
             .soundVolumeUp, .soundVolumeDown, .soundMuteToggle,
             .musicPlayPause, .musicNextTrack, .musicPrevTrack:
            return .sound
        case .cpuMonitor, .gpuMonitor, .memoryMonitor,
             .networkMonitor, .batteryDisplay:
            return .energyDisplay
        case .keepAwake, .portControl, .processKiller,
             .fileShredder, .colorPicker, .eyeBreak, .quickTimer, .focusMode:
            return .tools
        case .dynamicIslandEnabled, .dynamicIslandShowCPU, .dynamicIslandShowBattery,
             .dynamicIslandShowVolume, .dynamicIslandShowTime, .dynamicIslandShowDate,
             .dynamicIslandShowMemory, .dynamicIslandShowNetwork, .dynamicIslandShowWeather,
             .dynamicIslandShowMusic, .dynamicIslandShowNextEvent:
            return .dynamicIsland
        }
    }

    private func localized(_ kind: String, _ englishFallback: String) -> String {
        L("feature.\(rawValue).\(kind)", englishFallback)
    }

    /// Human-readable label displayed in the menu panel
    public var displayName: String {
        switch self {
        case .autoHideDock: return localized("name", "Auto-Hide Dock")
        case .minimizeOnClickDock: return localized("name", "Minimize on Dock Click")
        case .dockSize: return localized("name", "Dock Size")
        case .windowSnap: return localized("name", "Window Snap")
        case .hideAllWindows: return localized("name", "Hide All Windows")
        case .forceQuitDialog: return localized("name", "Force Quit Dialog")
        case .invertScroll: return localized("name", "Invert Scroll Direction")
        case .mouseSensitivity: return localized("name", "Mouse Sensitivity")
        case .keyboardRepeatRate: return localized("name", "Key Repeat Rate")
        case .doubleClickSpeed: return localized("name", "Double-Click Speed")
        case .cursorSize: return localized("name", "Cursor Size")
        case .clipboardHistory: return localized("name", "Clipboard History")
        case .pasteAsPlainText: return localized("name", "Paste as Plain Text")
        case .syncClipboardAcrossDevices: return localized("name", "Sync Clipboard")
        case .volumeMixer: return localized("name", "Volume Mixer")
        case .inputDeviceSelect: return localized("name", "Input Device")
        case .audioToggle: return localized("name", "Audio Toggle")
        case .notificationSound: return localized("name", "Notification Sound")
        case .windowMinimizeAll: return localized("name", "Minimize All Windows")
        case .windowSwitchApp: return localized("name", "Switch App (Cmd+Tab)")
        case .soundVolumeUp: return localized("name", "Volume Up +5%")
        case .soundVolumeDown: return localized("name", "Volume Down -5%")
        case .soundMuteToggle: return localized("name", "Toggle Mute")
        case .musicPlayPause: return localized("name", "Play / Pause")
        case .musicNextTrack: return localized("name", "Next Track")
        case .musicPrevTrack: return localized("name", "Previous Track")
        case .dynamicIslandShowMusic: return localized("name", "Island: Music")
        case .dynamicIslandShowNextEvent: return localized("name", "Island: Next Event")
        case .cpuMonitor: return localized("name", "CPU Monitor")
        case .gpuMonitor: return localized("name", "GPU Monitor")
        case .memoryMonitor: return localized("name", "Memory Monitor")
        case .networkMonitor: return localized("name", "Network Monitor")
        case .batteryDisplay: return localized("name", "Battery Display")
        case .keepAwake: return localized("name", "Keep Awake")
        case .portControl: return localized("name", "Port Control")
        case .processKiller: return localized("name", "Process Killer")
        case .fileShredder: return localized("name", "File Shredder")
        case .colorPicker: return localized("name", "Color Picker")
        case .eyeBreak: return localized("name", "Eye Break (20-20-20)")
        case .quickTimer: return localized("name", "Quick Timer")
        case .focusMode: return localized("name", "Focus Session")
        case .timerStart5: return localized("name", "Timer 5 min")
        case .timerStart10: return localized("name", "Timer 10 min")
        case .timerStart25: return localized("name", "Timer 25 min")
        case .dynamicIslandEnabled: return localized("name", "Dynamic Island")
        case .dynamicIslandShowCPU: return localized("name", "Island: CPU")
        case .dynamicIslandShowBattery: return localized("name", "Island: Battery")
        case .dynamicIslandShowVolume: return localized("name", "Island: Volume")
        case .dynamicIslandShowTime: return localized("name", "Island: Time")
        case .dynamicIslandShowDate: return localized("name", "Island: Date")
        case .dynamicIslandShowMemory: return localized("name", "Island: Memory")
        case .dynamicIslandShowNetwork: return localized("name", "Island: Network")
        case .dynamicIslandShowWeather: return localized("name", "Island: Weather")
        }
    }

    /// Description shown in tooltip or settings panel
    public var descriptionText: String {
        switch self {
        case .autoHideDock: return localized("desc", "Automatically hide the Dock when space is needed")
        case .minimizeOnClickDock: return localized("desc", "Minimize windows when clicking their Dock icon")
        case .dockSize: return localized("desc", "Toggle between larger and default Dock icon size")
        case .windowSnap: return localized("desc", "Snap the frontmost window to the left half")
        case .hideAllWindows: return localized("desc", "Hide all app windows (Option+Command+H)")
        case .forceQuitDialog: return localized("desc", "Open the system Force Quit dialog")
        case .invertScroll: return localized("desc", "Reverse scroll direction instantly (event tap)")
        case .mouseSensitivity: return localized("desc", "Set pointer speed and open Mouse settings")
        case .keyboardRepeatRate: return localized("desc", "Set key repeat rate (faster / default)")
        case .doubleClickSpeed: return localized("desc", "Open Mouse settings to adjust double-click speed")
        case .cursorSize: return localized("desc", "Open Display settings to adjust cursor size")
        case .clipboardHistory: return localized("desc", "Maintain clipboard history across sessions")
        case .pasteAsPlainText: return localized("desc", "Always paste content as unformatted text")
        case .syncClipboardAcrossDevices: return localized("desc", "Sync clipboard text across devices via iCloud")
        case .volumeMixer: return localized("desc", "See which apps play sound and mute them individually")
        case .inputDeviceSelect: return localized("desc", "Switch to the next Core Audio input device")
        case .audioToggle: return localized("desc", "Mute/unmute system audio via Core Audio")
        case .notificationSound: return localized("desc", "Open Sound settings for notification sounds")
        case .windowMinimizeAll: return localized("desc", "Minimize all windows with one click")
        case .windowSwitchApp: return localized("desc", "Switch to next app (like Cmd+Tab)")
        case .soundVolumeUp: return localized("desc", "Increase system volume by 5%")
        case .soundVolumeDown: return localized("desc", "Decrease system volume by 5%")
        case .soundMuteToggle: return localized("desc", "Toggle system mute state")
        case .cpuMonitor: return localized("desc", "Live CPU usage from Mach host statistics")
        case .gpuMonitor: return localized("desc", "GPU model via system_profiler (no public utilization API)")
        case .memoryMonitor: return localized("desc", "Live memory usage from VM statistics")
        case .networkMonitor: return localized("desc", "Live upload/download rates from network interfaces")
        case .batteryDisplay: return localized("desc", "Battery percentage and charging state (IOKit)")
        case .keepAwake: return localized("desc", "Prevent Mac from sleeping automatically")
        case .portControl: return localized("desc", "Open Network settings (port control needs root)")
        case .processKiller: return localized("desc", "Choose a running app and terminate it")
        case .fileShredder: return localized("desc", "Overwrite and delete files you select")
        case .eyeBreak: return localized("desc", "Every 20 minutes, dim the screen for a 20-second eye break")
        case .quickTimer: return localized("desc", "Enable quick timers; the countdown shows on the island")
        case .focusMode: return localized("desc", "25-minute focus session on the island; tries to mute notifications (legacy hook)")
        case .timerStart5: return localized("desc", "Start a 5-minute timer (tap again to cancel)")
        case .timerStart10: return localized("desc", "Start a 10-minute timer (tap again to cancel)")
        case .timerStart25: return localized("desc", "Start a 25-minute timer (tap again to cancel)")
        case .colorPicker: return localized("desc", "Pick an on-screen color and copy its hex")
        case .dynamicIslandEnabled: return localized("desc", "Floating island at the top of the screen with live CPU / memory / battery")
        case .dynamicIslandShowCPU: return localized("desc", "Show CPU stats in the island")
        case .dynamicIslandShowBattery: return localized("desc", "Show battery status in the island")
        case .dynamicIslandShowVolume: return localized("desc", "Show output volume in the island")
        case .dynamicIslandShowTime: return localized("desc", "Show the clock in the island")
        case .dynamicIslandShowDate: return localized("desc", "Show the date in the island")
        case .dynamicIslandShowMemory: return localized("desc", "Show memory pressure in the island")
        case .dynamicIslandShowNetwork: return localized("desc", "Show network throughput in the island")
        case .dynamicIslandShowWeather: return localized("desc", "Show local weather in the island (auto location)")
        case .dynamicIslandShowMusic: return localized("desc", "Show the playing track in the island")
        case .dynamicIslandShowNextEvent: return localized("desc", "Show the next calendar event in the island")
        case .musicPlayPause: return localized("desc", "Send the system play/pause media key")
        case .musicNextTrack: return localized("desc", "Send the next-track media key")
        case .musicPrevTrack: return localized("desc", "Send the previous-track media key")
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

    /// Full localized group title
    public var localizedName: String {
        L("group.\(rawValue).name", rawValue)
    }

    /// Compact label for the narrow tab bar (full rawValue overflows at 320pt)
    public var shortLabel: String {
        L("group.\(rawValue).short", {
            switch self {
            case .windowsDock: return "Windows"
            case .mouseKeyboard: return "Mouse"
            case .clipboard: return "Clipboard"
            case .sound: return "Sound"
            case .energyDisplay: return "Energy"
            case .tools: return "Tools"
            case .dynamicIsland: return "Island"
            }
        }())
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
