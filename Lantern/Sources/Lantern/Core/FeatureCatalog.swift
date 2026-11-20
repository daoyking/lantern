// FeatureCatalog.swift — Feature metadata and availability logic

import Foundation
import AppKit

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

    public init(
        requiresPermission: PermissionType? = nil,
        hardwareRequirement: HardwareRequirement? = nil,
        installedByDefault: Bool = false,
        displayPriority: Int = 99
    ) {
        self.requiresPermission = requiresPermission
        self.hardwareRequirement = hardwareRequirement
        self.installedByDefault = installedByDefault
        self.displayPriority = displayPriority
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
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .fullDiskAccess: return "Full Disk Access"
        case .notifications: return "Notifications"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
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
        case .dynamicIslandOnly: return "Dynamic Island (MacBook Pro 2023+)"
        case .appleSiliconOnly: return "Apple Silicon"
        case .externalDisplayOnly: return "External Display"
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

        // Windows & Dock — no special permissions
        map[.autoHideDock] = FeatureMetadata(installedByDefault: true, displayPriority: 1)
        map[.minimizeOnClickDock] = FeatureMetadata(installedByDefault: true, displayPriority: 2)
        map[.dockSize] = FeatureMetadata(installedByDefault: false, displayPriority: 3)
        map[.windowSnap] = FeatureMetadata(
            requiresPermission: .accessibility,
            installedByDefault: true,
            displayPriority: 4
        )
        map[.hideAllWindows] = FeatureMetadata(installedByDefault: false, displayPriority: 5)
        map[.forceQuitDialog] = FeatureMetadata(installedByDefault: false, displayPriority: 6)

        // Mouse & Keyboard — minimal permissions
        map[.invertScroll] = FeatureMetadata(installedByDefault: true, displayPriority: 1)
        map[.mouseSensitivity] = FeatureMetadata(installedByDefault: false, displayPriority: 2)
        map[.keyboardRepeatRate] = FeatureMetadata(installedByDefault: false, displayPriority: 3)
        map[.doubleClickSpeed] = FeatureMetadata(installedByDefault: false, displayPriority: 4)
        map[.cursorSize] = FeatureMetadata(installedByDefault: false, displayPriority: 5)

        // Clipboard
        map[.clipboardHistory] = FeatureMetadata(
            requiresPermission: .accessibility,
            installedByDefault: true,
            displayPriority: 1
        )
        map[.pasteAsPlainText] = FeatureMetadata(installedByDefault: true, displayPriority: 2)
        map[.syncClipboardAcrossDevices] = FeatureMetadata(
            requiresPermission: PermissionType.none,
            installedByDefault: false,
            displayPriority: 3
        )

        // Sound
        map[.volumeMixer] = FeatureMetadata(
            requiresPermission: .accessibility,
            installedByDefault: true,
            displayPriority: 1
        )
        map[.inputDeviceSelect] = FeatureMetadata(installedByDefault: false, displayPriority: 2)
        map[.audioToggle] = FeatureMetadata(installedByDefault: true, displayPriority: 3)
        map[.notificationSound] = FeatureMetadata(
            requiresPermission: .notifications,
            installedByDefault: false,
            displayPriority: 4
        )

        // Energy Display — read-only, no permissions needed
        map[.cpuMonitor] = FeatureMetadata(installedByDefault: true, displayPriority: 1)
        map[.gpuMonitor] = FeatureMetadata(installedByDefault: false, displayPriority: 2)
        map[.memoryMonitor] = FeatureMetadata(installedByDefault: true, displayPriority: 3)
        map[.networkMonitor] = FeatureMetadata(installedByDefault: false, displayPriority: 4)
        map[.batteryDisplay] = FeatureMetadata(installedByDefault: true, displayPriority: 5)

        // Tools
        map[.keepAwake] = FeatureMetadata(installedByDefault: true, displayPriority: 1)
        map[.portControl] = FeatureMetadata(
            requiresPermission: .fullDiskAccess,
            installedByDefault: false,
            displayPriority: 2
        )
        map[.processKiller] = FeatureMetadata(
            requiresPermission: .accessibility,
            installedByDefault: true,
            displayPriority: 3
        )
        map[.fileShredder] = FeatureMetadata(
            requiresPermission: .fullDiskAccess,
            installedByDefault: false,
            displayPriority: 4
        )
        map[.colorPicker] = FeatureMetadata(
            requiresPermission: .screenRecording,
            installedByDefault: false,
            displayPriority: 5
        )

        // Dynamic Island
        map[.dynamicIslandEnabled] = FeatureMetadata(
            hardwareRequirement: .dynamicIslandOnly,
            installedByDefault: true,
            displayPriority: 1
        )
        map[.dynamicIslandShowCPU] = FeatureMetadata(
            hardwareRequirement: .dynamicIslandOnly,
            installedByDefault: true,
            displayPriority: 2
        )
        map[.dynamicIslandShowBattery] = FeatureMetadata(
            hardwareRequirement: .dynamicIslandOnly,
            installedByDefault: true,
            displayPriority: 3
        )

        return map
    }
}
