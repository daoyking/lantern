// Permissions.swift — Reactive TCC permission monitoring

import Foundation
import AppKit
import Security
import AVFoundation
import UserNotifications

/// Monitors system permissions and publishes changes reactively
public final class Permissions: ObservableObject {
    public static let shared = Permissions()

    // MARK: - Published Permission States

    @Published public var accessibility: PermissionStatus = .checking
    @Published public var screenRecording: PermissionStatus = .checking
    @Published public var fullDiskAccess: PermissionStatus = .checking
    @Published public var notifications: PermissionStatus = .checking
    @Published public var camera: PermissionStatus = .notRequested
    @Published public var microphone: PermissionStatus = .notRequested

    // MARK: - Polling Timer

    private var pollingTimer: Timer?
    private let pollInterval: TimeInterval = 2.5 // Seconds between checks

    // MARK: - Initialization

    private init() {
        startPolling()
    }

    deinit {
        pollingTimer?.invalidate()
    }

    // MARK: - Public API

    /// Check if a permission type is currently granted
    public func isGranted(_ type: PermissionType) -> Bool {
        switch type {
        case .accessibility: return accessibility == .granted
        case .screenRecording: return screenRecording == .granted
        case .fullDiskAccess: return fullDiskAccess == .granted
        case .notifications: return notifications == .granted
        case .camera: return camera == .granted
        case .microphone: return microphone == .granted
        case .none: return true
        }
    }

    /// Request a specific permission (may trigger system dialog)
    public func request(_ type: PermissionType) {
        switch type {
        case .accessibility:
            requestAccessibility()
        case .screenRecording:
            requestScreenRecording()
        case .fullDiskAccess:
            openSystemPreferences()
        case .notifications:
            requestNotifications()
        case .camera, .microphone:
            requestAVPermission(type == .camera ? .video : .audio)
        case .none:
            break
        }
    }

    /// Open System Preferences for manual permission granting
    public func openSystemPreferences(for type: PermissionType? = nil) {
        let url: URL
        switch type {
        case .accessibility?:
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .screenRecording?:
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .fullDiskAccess?:
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        case .notifications?:
            url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        default:
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) {_ in
            self.checkPermissions()
        }
    }

    private func checkPermissions() {
        checkAccessibility()
        checkScreenRecording()
        checkFullDiskAccess()
        checkNotifications()
    }

    // MARK: - Permission Checks

    private func checkAccessibility() {
        let status = AXIsProcessTrusted()
        DispatchQueue.main.async { [weak self] in
            self?.accessibility = status ? .granted : .denied
        }
    }

    private func checkScreenRecording() {
        #if os(macOS)
        let status = CGPreflightScreenCaptureAccess()
        DispatchQueue.main.async { [weak self] in
            self?.screenRecording = status ? .granted : .denied
        }
        #else
        DispatchQueue.main.async { [weak self] in
            self?.screenRecording = .notAvailable
        }
        #endif
    }

    private func checkFullDiskAccess() {
        // Full Disk Access requires elevated privileges to check programmatically
        // Use heuristics based on process capabilities
        let canAccessProtectedPaths = checkProtectedPathAccess()
        DispatchQueue.main.async { [weak self] in
            self?.fullDiskAccess = canAccessProtectedPaths ? .granted : .denied
        }
    }

    private func checkNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings {settings in
            DispatchQueue.main.async {
                
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    self.notifications = .granted
                case .denied:
                    self.notifications = .denied
                case .notDetermined:
                    self.notifications = .notRequested
                @unknown default:
                    self.notifications = .notRequested
                }
            }
        }
    }

    private func checkProtectedPathAccess() -> Bool {
        // Try accessing a protected path as a heuristic
        let protectedPaths = [
            "/private/var/db/",
            "/Library/Application Support/",
            "~/Library/Application Support/"
        ]
        for path in protectedPaths {
            let expanded = URL(fileURLWithPath: path).standardized.path
            if FileManager.default.isReadableFile(atPath: expanded) {
                return true
            }
        }
        return false
    }

    // MARK: - Request Helpers

    private func requestAccessibility() {
        // Accessibility access must be granted in System Preferences
        // We cannot trigger this programmatically
        openSystemPreferences(for: .accessibility)
    }

    private func requestScreenRecording() {
        // Screen recording also requires manual approval
        openSystemPreferences(for: .screenRecording)
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {granted, error in
            DispatchQueue.main.async {
                self.notifications = granted ? .granted : .denied
            }
        }
    }

    private func requestAVPermission(_ type: AVMediaType) {
        let status = AVCaptureDevice.authorizationStatus(for: type)
        switch status {
        case .authorized:
            // Already granted
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: type) {granted in
                DispatchQueue.main.async {
                    if type == .video {
                        self.camera = granted ? .granted : .denied
                    } else {
                        self.microphone = granted ? .granted : .denied
                    }
                }
            }
        case .denied, .restricted:
            // Must be set in System Preferences
            openSystemPreferences()
        @unknown default:
            break
        }
    }
}

/// Current state of a permission
public enum PermissionStatus: Equatable {
    case notRequested
    case checking
    case granted
    case denied
    case unavailable

    /// Returns true if permission is fully granted
    public var isGranted: Bool {
        switch self {
        case .granted: return true
        default: return false
        }
    }

    /// Returns true if we need to guide user to grant permission
    public var needsPermission: Bool {
        switch self {
        case .denied, .notRequested: return true
        default: return false
        }
    }

}

// MARK: - Permissions Class Extension

public extension Permissions {
    /// Convenience accessor for denied permissions via shared singleton
    static var deniedPermission: PermissionType? {
        let permissions = Permissions.shared
        let types: [PermissionType] = [.accessibility, .screenRecording, .fullDiskAccess, .notifications, .camera, .microphone]
        return types.first { type in
            switch type {
            case .accessibility: return permissions.accessibility == .denied
            case .screenRecording: return permissions.screenRecording == .denied
            case .fullDiskAccess: return permissions.fullDiskAccess == .denied
            case .notifications: return permissions.notifications == .denied
            case .camera: return permissions.camera == .denied
            case .microphone: return permissions.microphone == .denied
            case .none: return false
            }
        }
    }
}

/// Extension for AVAssetExportSession media type compatibility
private extension AVMediaType {
    static var video: AVMediaType { .init(rawValue: "vide")! }
    static var audio: AVMediaType { .init(rawValue: "soun")! }
}
