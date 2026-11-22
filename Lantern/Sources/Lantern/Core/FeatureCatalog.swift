// FeatureCatalog.swift — Feature metadata and availability logic

import Foundation
import AppKit

/// How completely a feature is actually implemented. Surfaced in the UI so
/// users can tell a real system integration from a demo or a placeholder
/// instead of assuming every switch does something.
public enum ImplementationLevel: String {
    /// Real macOS API integration with observable system effect.
    case native
    /// Has a live service, but the numbers are simulated for demonstration.
    case simulated
    /// Only the on/off preference is persisted; no system effect yet.
    case stub

    public var badge: String {
        switch self {
        case .native: return ""
        case .simulated: return "DEMO"
        case .stub: return "未实现"
        }
    }

    /// UI-facing badge — keeps the stable `badge` contract used by tests while
    /// rendering "DEMO" as 演示 in the Chinese build.
    public var localizedBadge: String {
        switch self {
        case .native: return ""
        case .simulated: return L("badge.simulated", "DEMO")
        case .stub: return L("badge.stub", "Not Implemented")
        }
    }
}

/// Describes when and how a feature should appear in the menu panel
public struct FeatureMetadata {
    /// Whether the feature requires a specific permission to function
    public let requiresPermission: PermissionType?
    /// Whether the feature is only available on certain hardware
    public let hardwareRequirement: HardwareRequirement?
    /// Default installed state — true if enabled by default
    public let installedByDefault: Bool
    /// Priority order within its group (lower = higher priority)
    public let displayPriority: Int
    /// Honest implementation status shown in the UI
    public let implementation: ImplementationLevel
    /// True for one-shot actions (volume step, switch app) rather than
    /// persistent on/off state — rendered as a button, not a switch.
    public let isAction: Bool

    public init(
        requiresPermission: PermissionType? = nil,
        hardwareRequirement: HardwareRequirement? = nil,
        installedByDefault: Bool = false,
        displayPriority: Int = 99,
        implementation: ImplementationLevel = .stub,
        isAction: Bool = false
    ) {
        self.requiresPermission = requiresPermission
        self.hardwareRequirement = hardwareRequirement
        self.installedByDefault = installedByDefault
        self.displayPriority = displayPriority
        self.implementation = implementation
        self.isAction = isAction
    }
}

/// Permission types that may gate feature availability
public enum PermissionType: Equatable {
    case accessibility           // NSAccessibilityPermission
    case screenRecording         // NSScreenCapturePermission
    case fullDiskAccess          // AppleEventPermission (full disk)
    case notifications           // UNUserNotificationCenter
    case camera                  // AVAuthorizationStatus
    case microphone              // AVAuthorizationStatus
    case none                    // No special permission required

    public var humanReadableName: String {
        switch self {
        case .accessibility: return L("permission.accessibility", "Accessibility")
        case .screenRecording: return L("permission.screenRecording", "Screen Recording")
        case .fullDiskAccess: return L("permission.fullDiskAccess", "Full Disk Access")
        case .notifications: return L("permission.notifications", "Notifications")
        case .camera: return L("permission.camera", "Camera")
        case .microphone: return L("permission.microphone", "Microphone")
        case .none: return ""
        }
    }
    
    /// Returns true if this permission type requires user interaction
    public var requiresUserAction: Bool {
        switch self {
        case .accessibility, .screenRecording, .fullDiskAccess, .notifications, .camera, .microphone:
            return true
        case .none:
            return false
        }
    }
}

/// Hardware requirements that may limit feature availability
public enum HardwareRequirement: Equatable {
    case dynamicIslandOnly      // MacBook Pro 2023+ or external dongle
    case appleSiliconOnly       // Requires M-series chip
    case externalDisplayOnly    // Requires second monitor
    case none                   // Works on all supported hardware

    public var requirementLabel: String? {
        switch self {
        case .dynamicIslandOnly: return L("hardware.dynamicIslandOnly", "Dynamic Island (MacBook Pro 2023+)")
        case .appleSiliconOnly: return L("hardware.appleSiliconOnly", "Apple Silicon")
        case .externalDisplayOnly: return L("hardware.externalDisplayOnly", "External Display")
        case .none: return nil
        }
    }
}

/// Central registry mapping each AppFeature to its metadata
public final class FeatureCatalog {
    public static let shared = FeatureCatalog()

    /// Lookup table: feature → metadata
    private let metadataMap: [AppFeature: FeatureMetadata]

    private init() {
        self.metadataMap = Self.buildMetadataMap()
    }

    /// Returns metadata for a given feature, or default metadata if undefined
    public func metadata(for feature: AppFeature) -> FeatureMetadata {
        metadataMap[feature] ?? FeatureMetadata()
    }

    /// Returns features filtered by their current availability
    public var availableFeatures: [AppFeature] {
        AppFeature.allCases.filter { isAvailable($0) }
    }

    /// Check if a feature is currently available based on permissions + hardware
    public func isAvailable(_ feature: AppFeature) -> Bool {
        let meta = metadata(for: feature)

        // Check hardware requirement first
        guard meetsHardwareRequirement(meta.hardwareRequirement) else { return false }

        // Check permission requirement
        if let perm = meta.requiresPermission {
            return Permissions.shared.isGranted(perm)
        }

        return true
    }

    /// Returns features sorted by group then priority
    public func orderedFeatures(by group: FeatureGroup) -> [AppFeature] {
        AppFeature.allCases
            .filter { $0.group == group }
            .sorted { lhs, rhs in
                let lhsMeta = metadata(for: lhs)
                let rhsMeta = metadata(for: rhs)
                return lhsMeta.displayPriority < rhsMeta.displayPriority
            }
    }

    // MARK: - Private Helpers

    private func meetsHardwareRequirement(_ requirement: HardwareRequirement?) -> Bool {
        guard let req = requirement else { return true }
        switch req {
        case .dynamicIslandOnly:
            // Only available on Macs that support Dynamic Island (macOS 15+)
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return version.majorVersion >= 15 && isDynamicIslandCapable()
        case .appleSiliconOnly:
            // Apple Silicon requirement (M-series chip)
            var size = 0
            sysctlbyname("hw.optional.arm", nil, &size, nil, 0)
            var hasArm = UInt8(0)
            sysctlbyname("hw.optional.arm", &hasArm, &size, nil, 0)
            return hasArm == 1
        case .externalDisplayOnly:
            return NSScreen.screens.count > 1
        case .none:
            return true
        }
    }

    private func isDynamicIslandCapable() -> Bool {
        // In practice, check for MacBook Pro 2023+ or external dongle
        // For clean-room implementation we use a heuristic based on model identifier
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelIdentifier = String(cString: model)
        
        return modelIdentifier.hasPrefix("MacBookPro16,") ||
               modelIdentifier.hasPrefix("MacBookPro17,") ||
               modelIdentifier.hasPrefix("MacBookPro18,") ||
               modelIdentifier.hasPrefix("MacBookPro19,")
    }

    private static func buildMetadataMap() -> [AppFeature: FeatureMetadata] {
        var map: [AppFeature: FeatureMetadata] = [:]

        // ── Windows & Dock ─────────────────────────────────────────────
        // All backed by real defaults writes or Accessibility AppleScript.
        map[.autoHideDock] = FeatureMetadata(
            installedByDefault: true, displayPriority: 1, implementation: .native
        )
        map[.minimizeOnClickDock] = FeatureMetadata(
            installedByDefault: true, displayPriority: 2, implementation: .native
        )
        map[.dockSize] = FeatureMetadata(displayPriority: 3, implementation: .native)
        map[.windowSnap] = FeatureMetadata(
            requiresPermission: .accessibility,
            displayPriority: 4,
            implementation: .native,
            isAction: true
        )
        map[.hideAllWindows] = FeatureMetadata(
            requiresPermission: .accessibility,
            displayPriority: 5,
            implementation: .native,
            isAction: true
        )
        map[.forceQuitDialog] = FeatureMetadata(
            requiresPermission: .accessibility,
            displayPriority: 6,
            implementation: .native,
            isAction: true
        )

        // ── Mouse & Keyboard ───────────────────────────────────────────
        // Scroll inversion: live CGEventTap — a mutable tap needs Accessibility.
        // Pointer speed / key repeat: real defaults writes.
        // Double-click speed & cursor size have no public key → open settings pane.
        map[.invertScroll] = FeatureMetadata(
            requiresPermission: .accessibility,
            installedByDefault: true, displayPriority: 1, implementation: .native
        )
        map[.mouseSensitivity] = FeatureMetadata(displayPriority: 2, implementation: .native)
        map[.keyboardRepeatRate] = FeatureMetadata(displayPriority: 3, implementation: .native)
        map[.doubleClickSpeed] = FeatureMetadata(displayPriority: 4, implementation: .stub)
        map[.cursorSize] = FeatureMetadata(displayPriority: 5, implementation: .stub)

        // ── Clipboard ──────────────────────────────────────────────────
        // All three are real NSPasteboard / iCloud key-value-store effects.
        map[.clipboardHistory] = FeatureMetadata(
            installedByDefault: true,
            displayPriority: 1,
            implementation: .native
        )
        map[.pasteAsPlainText] = FeatureMetadata(
            installedByDefault: true, displayPriority: 2, implementation: .native
        )
        map[.syncClipboardAcrossDevices] = FeatureMetadata(
            displayPriority: 3, implementation: .native
        )

        // ── Sound ──────────────────────────────────────────────────────
        // Core Audio for volume/mute/input device. Volume step / mute /
        // switch-input are one-shot actions, not persistent toggles.
        map[.volumeMixer] = FeatureMetadata(
            installedByDefault: true,
            displayPriority: 1,
            implementation: .native  // live per-app list + per-app mute via process taps
        )
        map[.inputDeviceSelect] = FeatureMetadata(
            displayPriority: 2, implementation: .native, isAction: true
        )
        map[.audioToggle] = FeatureMetadata(
            installedByDefault: true, displayPriority: 3, implementation: .native
        )
        map[.notificationSound] = FeatureMetadata(
            displayPriority: 4,
            implementation: .stub  // system-wide notification sounds have no public toggle
        )
        map[.soundVolumeUp] = FeatureMetadata(displayPriority: 5, implementation: .native, isAction: true)
        map[.soundVolumeDown] = FeatureMetadata(displayPriority: 6, implementation: .native, isAction: true)
        map[.soundMuteToggle] = FeatureMetadata(displayPriority: 7, implementation: .native, isAction: true)

        // ── Window Management (actions, AppleScript-backed) ────────────
        // Every entry runs `System Events` AppleScript — Accessibility TCC
        // is genuinely required for all five (previously only three were
        // marked, so minimize-all / switch-app failed silently on a fresh
        // install). volumeMixer/notificationSound/portControl/processKiller/
        // fileShredder/colorPicker never touch TCC-gated APIs: their old
        // permission labels were wrong and are removed.
        map[.windowMinimizeAll] = FeatureMetadata(
            requiresPermission: .accessibility,
            displayPriority: 8, implementation: .native, isAction: true
        )
        map[.windowSwitchApp] = FeatureMetadata(
            requiresPermission: .accessibility,
            displayPriority: 9, implementation: .native, isAction: true
        )

        // ── Energy Display ─────────────────────────────────────────────
        // All metrics are read live from Mach/IOKit/BSD via SystemMetrics.
        // GPU has no public utilisation API — we report the real model name.
        map[.cpuMonitor] = FeatureMetadata(
            installedByDefault: true,
            displayPriority: 1,
            implementation: .native
        )
        map[.gpuMonitor] = FeatureMetadata(displayPriority: 2, implementation: .stub)
        map[.memoryMonitor] = FeatureMetadata(
            installedByDefault: true,
            displayPriority: 3,
            implementation: .native
        )
        map[.networkMonitor] = FeatureMetadata(displayPriority: 4, implementation: .native)
        map[.batteryDisplay] = FeatureMetadata(
            installedByDefault: true, displayPriority: 5, implementation: .native
        )

        // ── Tools ──────────────────────────────────────────────────────
        // KeepAwake uses a real IOPMAssertion. Process/shred/colour are real
        // one-shot actions. Port control needs root → honest settings fallback.
        // None of these touch TCC-gated APIs: process kill is same-user kill(),
        // shredder files are picked via NSOpenPanel (user-granted access),
        // NSColorSampler needs no screen-recording permission.
        map[.keepAwake] = FeatureMetadata(
            installedByDefault: true,
            displayPriority: 1,
            implementation: .native
        )
        map[.portControl] = FeatureMetadata(
            displayPriority: 2,
            implementation: .stub
        )
        map[.processKiller] = FeatureMetadata(
            displayPriority: 3,
            implementation: .native,
            isAction: true
        )
        map[.fileShredder] = FeatureMetadata(
            displayPriority: 4,
            implementation: .native,
            isAction: true
        )
        map[.colorPicker] = FeatureMetadata(
            displayPriority: 5,
            implementation: .native,
            isAction: true
        )

        // ── Dynamic Island ─────────────────────────────────────────────
        // Real floating panel + live SystemMetrics telemetry — the honest
        // kind of island (macOS has no native one, so we build our own).
        map[.dynamicIslandEnabled] = FeatureMetadata(
            installedByDefault: true,
            displayPriority: 1,
            implementation: .native
        )
        map[.dynamicIslandShowCPU] = FeatureMetadata(
            installedByDefault: true,
            displayPriority: 2,
            implementation: .native
        )
        map[.dynamicIslandShowBattery] = FeatureMetadata(
            installedByDefault: true,
            displayPriority: 3,
            implementation: .native
        )
        map[.dynamicIslandShowVolume] = FeatureMetadata(
            installedByDefault: true,
            displayPriority: 4,
            implementation: .native
        )
        map[.dynamicIslandShowTime] = FeatureMetadata(
            installedByDefault: true,
            displayPriority: 5,
            implementation: .native
        )
        map[.dynamicIslandShowDate] = FeatureMetadata(
            installedByDefault: true,
            displayPriority: 6,
            implementation: .native
        )
        map[.dynamicIslandShowMemory] = FeatureMetadata(
            installedByDefault: true,
            displayPriority: 7,
            implementation: .native
        )
        map[.dynamicIslandShowNetwork] = FeatureMetadata(
            installedByDefault: true,
            displayPriority: 8,
            implementation: .native
        )
        map[.dynamicIslandShowWeather] = FeatureMetadata(
            installedByDefault: true,
            displayPriority: 9,
            implementation: .native
        )

        return map
    }
}
