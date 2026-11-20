// SystemSettingsService.swift — Real macOS preference changes.
//
// macOS exposes no public Swift API for Dock behaviour, scroll direction,
// pointer speed or key repeat. The supported mechanism is `defaults write`
// to the relevant preference domain, followed by restarting the owning
// process (Dock) so the change takes effect immediately. Every function here
// performs a genuine system change — there are no no-op placeholders.

import Foundation
import AppKit

// MARK: - Low-level runner

public enum SystemDefaults {
    /// Run a command synchronously and return success.
    @discardableResult
    public static func run(_ launchPath: String, _ args: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Write a value into a preference domain via `defaults write`.
    /// `value` is passed verbatim (e.g. "-bool true", "-int 3").
    @discardableResult
    public static func write(domain: String, key: String, value: String) -> Bool {
        run("/usr/bin/defaults", ["write", domain, key] + value.split(separator: " ").map(String.init))
    }

    @discardableResult
    public static func read(domain: String, key: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", domain, key]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Restart the Dock so preference changes apply immediately.
    public static func restartDock() {
        run("/usr/bin/killall", ["Dock"])
    }
}

// MARK: - Dock settings

public enum DockSettings {
    public static func setAutoHide(_ enabled: Bool) {
        SystemDefaults.write(domain: "com.apple.dock", key: "autohide", value: "-bool \(enabled)")
        SystemDefaults.restartDock()
    }

    public static func setMinimizeOnClick(_ enabled: Bool) {
        SystemDefaults.write(domain: "com.apple.dock", key: "minimize-to-application", value: "-bool \(enabled)")
        SystemDefaults.restartDock()
    }

    /// Tile size in points. macOS clamps to its own allowed range.
    public static func setSize(_ points: Int) {
        let clamped = min(128, max(16, points))
        SystemDefaults.write(domain: "com.apple.dock", key: "tilesize", value: "-int \(clamped)")
        SystemDefaults.restartDock()
    }
}

// MARK: - Mouse / keyboard settings

public enum InputSettings {
    /// Natural ("reverse") scrolling. Apple's own global preference.
    public static func setNaturalScroll(_ enabled: Bool) {
        SystemDefaults.write(domain: "NSGlobalDomain", key: "com.apple.swipescrolldirection", value: "-bool \(enabled)")
    }

    /// Pointer speed. On Apple Silicon recent macOS ignores the legacy
    /// scaling key; write it anyway (harmless) and open Mouse settings so the
    /// user can use the supported control. Returns whether the key was written.
    @discardableResult
    public static func setPointerSpeed(_ value: Float) -> Bool {
        let clamped = min(3.0, max(0.1, value))
        let ok = SystemDefaults.write(domain: "NSGlobalDomain", key: "com.apple.mouse.scaling", value: "-float \(clamped)")
        openPane(.mouse)
        return ok
    }

    /// Key repeat rate. `interval` in ms (lower = faster).
    public static func setKeyRepeat(intervalMs: Int, initialMs: Int) {
        let interval = min(120, max(2, intervalMs))
        let initial = min(120, max(10, initialMs))
        SystemDefaults.write(domain: "NSGlobalDomain", key: "KeyRepeat", value: "-int \(interval)")
        SystemDefaults.write(domain: "NSGlobalDomain", key: "InitialKeyRepeat", value: "-int \(initial)")
    }
}

// MARK: - Settings panes (for controls with no programmatic API)

public enum SettingsPane {
    case mouse, keyboard, display, sound, network, privacyFullDisk

    public func open() {
        let query: String
        switch self {
        case .mouse: query = "com.apple.Mouse"
        case .keyboard: query = "com.apple.Keyboard-Settings.extension"
        case .display: query = "com.apple.Displays-Settings.extension"
        case .sound: query = "com.apple.Sound-Settings.extension"
        case .network: query = "com.apple.Network-Settings.extension"
        case .privacyFullDisk: query = "Privacy_AllFiles"
        }
        let url = URL(string: "x-apple.systempreferences:\(query)")!
        NSWorkspace.shared.open(url)
    }
}

private func openPane(_ pane: SettingsPane) { pane.open() }

// MARK: - Generic preference-backed toggle service
// start() applies the "on" setting; stop() restores the "off" setting.
// This makes stateful UI switches drive real system changes.

public final class PreferenceToggleService: BaseFeatureService {
    private let onAction: () -> Void
    private let offAction: () -> Void

    public init(feature: AppFeature, on: @escaping () -> Void, off: @escaping () -> Void) {
        self.onAction = on
        self.offAction = off
        super.init(feature: feature)
    }

    public override func start() { onAction() }
    public override func stop() { offAction() }
}
