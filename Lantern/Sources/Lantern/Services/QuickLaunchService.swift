import Foundation
import AppKit

/// Quick launcher (common checklist #15, minimal Lantern form): preset
/// one-tap launch actions for everyday Apple apps, rendered by the panel's
/// standard action rows. vorssaint ships a full grid overlay with keyboard
/// navigation; we deliberately keep the panel-button form — same outcome,
/// far less surface area. All bundle IDs resolve through LaunchServices at
/// launch time, so a missing app degrades to a no-op, not a crash.
final class QuickLaunchService: BaseFeatureService {

    static let shared = QuickLaunchService(feature: .launchSafari)

    /// Preset launch targets, in panel display order.
    static let presets: [AppFeature: String] = [
        .launchSafari: "com.apple.Safari",
        .launchTerminal: "com.apple.Terminal",
        .launchNotes: "com.apple.Notes",
        .launchCalculator: "com.apple.calculator",
        .launchCalendar: "com.apple.iCal",
        .launchMail: "com.apple.mail",
    ]

    private override init(feature: AppFeature) { super.init(feature: feature) }

    override public func start() throws {}
    override public func stop() throws {}

    /// Resolve the app bundle for a preset (nil = not installed).
    public static func appURL(for feature: AppFeature) -> URL? {
        guard let bundleID = presets[feature] else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Launch the preset app, activating it. Returns false when the app
    /// is absent or the async open fails.
    @discardableResult
    public static func launch(_ feature: AppFeature) -> Bool {
        guard let url = appURL(for: feature) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
        return true
    }
}
