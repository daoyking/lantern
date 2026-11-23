import AppKit

// MARK: - Gemini Live function calling (M3)

/// Tool registry exposed to Gemini via the Live API `tools` declaration.
/// This is the capability Sapphire left unimplemented ("Not yet implemented
/// on Sapphire Live") — Lantern wires the calls into its real services:
/// quick timers, quick launch, music keys, system metrics, clipboard.
enum GeminiToolRegistry {

    struct Call {
        let id: String
        let name: String
        let args: [String: Any]
    }

    // MARK: Declarations (sent inside the setup frame)

    private static func declaration(_ name: String, _ description: String,
                                    _ parameters: [String: Any]) -> [String: Any] {
        ["name": name, "description": description, "parameters": parameters]
    }

    static let declarations: [[String: Any]] = [
        declaration(
            "start_timer",
            "Start a quick countdown timer in minutes. Confirms with a sound and a corner card.",
            ["type": "object",
             "properties": ["minutes": ["type": "integer", "description": "Duration in minutes (1-120)"]],
             "required": ["minutes"]]
        ),
        declaration(
            "cancel_timer", "Cancel the running quick timer, if any.",
            ["type": "object", "properties": [:]]
        ),
        declaration(
            "open_app",
            "Launch a macOS app by name. Known: Safari, Terminal, Notes, Calculator, Calendar, Mail.",
            ["type": "object",
             "properties": ["name": ["type": "string", "description": "App name, e.g. 'Safari'"]],
             "required": ["name"]]
        ),
        declaration(
            "music_play_pause", "Toggle play/pause on the current media player.",
            ["type": "object", "properties": [:]]
        ),
        declaration(
            "music_next_track", "Skip to the next track.",
            ["type": "object", "properties": [:]]
        ),
        declaration(
            "music_previous_track", "Go back to the previous track.",
            ["type": "object", "properties": [:]]
        ),
        declaration(
            "battery_level", "Report the current battery percentage and charging state.",
            ["type": "object", "properties": [:]]
        ),
        declaration(
            "clipboard_recent", "Return the most recent clipboard history entries.",
            ["type": "object",
             "properties": ["limit": ["type": "integer", "description": "How many entries (default 3)"]]]
        ),
    ]

    // MARK: Execution

    /// Runs a tool call against Lantern services and returns a JSON-ish
    /// result string for the toolResponse frame. Never throws.
    static func execute(name: String, args: [String: Any]) -> String {
        switch name {
        case "start_timer":
            let minutes = (args["minutes"] as? NSNumber)?.intValue ?? 5
            let clamped = min(max(minutes, 1), 120)
            QuickTimerService.shared.start(minutes: clamped)
            return "{\"result\": \"timer started for \(clamped) minutes\"}"

        case "cancel_timer":
            QuickTimerService.shared.cancel()
            return "{\"result\": \"timer cancelled\"}"

        case "open_app":
            let requested = (args["name"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            guard let url = appURL(forName: requested) else {
                return "{\"error\": \"unknown app: \(requested)\"}"
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            return "{\"result\": \"launched \(requested)\"}"

        case "music_play_pause":
            MusicControllerService.shared?.playPause()
            return "{\"result\": \"ok\"}"
        case "music_next_track":
            MusicControllerService.shared?.nextTrack()
            return "{\"result\": \"ok\"}"
        case "music_previous_track":
            MusicControllerService.shared?.previousTrack()
            return "{\"result\": \"ok\"}"

        case "battery_level":
            let metrics = SystemMetrics().snapshot()
            if metrics.batteryPercent >= 0 {
                let charging = metrics.batteryCharging ? " (charging)" : ""
                return "{\"result\": \"battery \(Int(metrics.batteryPercent))%\(charging)\"}"
            }
            return "{\"result\": \"no battery detected\"}"

        case "clipboard_recent":
            let limit = max(1, min((args["limit"] as? NSNumber)?.intValue ?? 3, 10))
            let entries = ClipboardService.shared?.getHistory().prefix(limit)
                .compactMap { $0.content.isEmpty ? nil : $0.content } ?? []
            let escaped = entries.map { entry in
                "\"" + entry.replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n") + "\""
            }
            return "{\"result\": [\(escaped.joined(separator: ","))]}"

        default:
            return "{\"error\": \"unknown tool: \(name)\"}"
        }
    }

    /// LaunchServices lookup by friendly name (Safari/Terminal/...).
    static func appURL(forName raw: String) -> URL? {
        let normalized = raw.lowercased().trimmingCharacters(in: .whitespaces)
        let bundles: [String: String] = [
            "safari": "com.apple.Safari",
            "terminal": "com.apple.Terminal",
            "notes": "com.apple.Notes",
            "calculator": "com.apple.calculator",
            "calendar": "com.apple.iCal",
            "mail": "com.apple.mail",
        ]
        guard let bundleID = bundles[normalized] else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}
