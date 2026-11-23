import AppKit

// MARK: - Send clipboard to Notes (Sapphire Notes subset)
//
// One-shot action: creates a new note in Notes.app holding the current
// clipboard text (or the selection fallback). Uses osascript like the
// music controller; the first run raises one TCC automation prompt for
// Notes, after which it is silent. Failures surface as a sound cue only —
// the panel never blocks on the scripting bridge.
final class NotesCaptureService: BaseFeatureService {

    static let shared = NotesCaptureService(feature: .notesCapture)

    @Published public private(set) var lastResult: String?

    override init(feature: AppFeature) { super.init(feature: feature) }

    override public func start() throws {}
    override public func stop() throws { lastResult = nil }

    // MARK: Script assembly (pure, tested)

    /// Builds the osascript payload. Body text is shell- and AppleScript-escaped
    /// through osascript's own `-e` argument passing (no shell involved).
    static func script(noteTitle: String, body: String) -> String {
        func esc(_ text: String) -> String {
            text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")
        }
        return """
        tell application "Notes"
            make new note with properties {name:"\(esc(noteTitle))", body:"\(esc(body))"}
        end tell
        """
    }

    static func fallbackTitle(for date: Date, formatter: DateFormatter) -> String {
        "Lantern · " + formatter.string(from: date)
    }

    // MARK: Capture

    public func capture() {
        let body = NSPasteboard.general.string(forType: .string) ?? ""
        let title = Self.fallbackTitle(for: Date(), formatter: Self.titleFormatter)
        let script = Self.script(noteTitle: title, body: body.isEmpty ? "(empty clipboard)" : body)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = Self.runOsaScript(script, timeout: 10)
            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
                    self.lastResult = title
                    NSSound(named: "Tink")?.play()
                } else {
                    self.lastResult = nil
                    NSSound(named: "Sosumi")?.play()
                }
            }
        }
    }

    static func runOsaScript(_ source: String, timeout: TimeInterval) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }

    static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
