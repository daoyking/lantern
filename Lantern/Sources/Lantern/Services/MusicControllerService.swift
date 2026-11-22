// MusicControllerService.swift — now-playing info + media keys control
//
// Zero-dependency music control, honest about what each path can see:
//
//   Control — universal media-key events (NX system-defined, subtype 8).
//   These reach whichever app currently owns playback (Music, Spotify,
//   browsers, QuickTime) and need no TCC permission at all.
//
//   Info — AppleScript polling of Music / Spotify, but ONLY while the app
//   is already running (NSWorkspace check first: osascript would otherwise
//   launch the player, which is never our business). Anything else playing
//   still responds to the keys; its title just stays unknown.
//
// The island drives polling with setRunning(_:) exactly like
// IslandWeatherService — no timers, no Apple events while the slot is off.

import AppKit
import Combine
import Foundation

public final class MusicControllerService: BaseFeatureService {

    /// Created lazily by DynamicIslandService; panel actions use the same
    /// instance through this handle.
    public private(set) static var shared: MusicControllerService?

    // MARK: - Live state (observed by the island face)

    /// Nil = nothing known to be playing (slot hidden).
    @Published public private(set) var trackTitle: String?
    @Published public private(set) var trackArtist: String?
    @Published public private(set) var isPlaying: Bool = false

    // MARK: - Media-key encoding (pure, unit-tested)

    /// NX key codes for the system-defined media events.
    public static let keyPlay = 16
    public static let keyNext = 17
    public static let keyPrevious = 18

    /// data1 payload of an NX_SUBTYPE_AUX_CONTROL_BUTTONS event:
    /// high 16 bits carry the key code, low byte 0xA = key-down, 0xB = key-up.
    public static func mediaKeyEventData1(keyCode: Int, keyDown: Bool) -> Int {
        (keyCode << 16) | (keyDown ? 0x0A : 0x0B)
    }

    /// Posts one media-key press (down + up) as a system-defined event.
    /// Universal: works against any app that owns playback, no TCC needed.
    ///
    /// macOS 27 SDK dropped CGEvent(nsEvent:), so the classic NSEvent
    /// system-defined wrapper (subtype 8, data1 = (key<<16)|(0xA down /
    /// 0xB up)) can no longer be bridged into CoreGraphics. Virtual
    /// keycodes 16/17/18 ARE the media keys (NX_KEYTYPE_PLAY/NEXT/
    /// PREVIOUS) at the HID level, so a plain keyboard event pair does
    /// the same job and works for every active player. The encoding
    /// helpers stay public + tested so the data1 format is documented.
    public static func postMediaKey(_ keyCode: Int) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Public actions (island face + panel bindings)

    public func playPause() { Self.postMediaKey(Self.keyPlay) }
    public func nextTrack() { Self.postMediaKey(Self.keyNext) }
    public func previousTrack() { Self.postMediaKey(Self.keyPrevious) }

    // MARK: - Lifecycle

    private var timer: Timer?
    private let pollQueue = DispatchQueue(label: "lantern.music.poll", qos: .utility)

    override public init(feature: AppFeature) {
        super.init(feature: feature)
        Self.shared = self
    }

    /// Slot-driven start/stop, mirroring IslandWeatherService.setRunning.
    public func setRunning(_ running: Bool) {
        if running, timer == nil {
            pollNow()
            timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.pollNow()
            }
        } else if !running, let t = timer {
            t.invalidate()
            timer = nil
            trackTitle = nil
            trackArtist = nil
            isPlaying = false
        }
    }

    override public func start() throws {
        setRunning(true)
    }

    override public func stop() throws {
        setRunning(false)
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Now-playing poll

    private func pollNow() {
        pollQueue.async { [weak self] in
            let reading = Self.readNowPlaying()
            DispatchQueue.main.async {
                guard let self else { return }
                self.trackTitle = reading?.title
                self.trackArtist = reading?.artist
                self.isPlaying = reading?.playing ?? false
            }
        }
    }

    struct Reading { let title: String; let artist: String; let playing: Bool }

    /// Runs the AppleScript on the calling (utility) thread; returns nil when
    /// no supported player is running or the script fails.
    static func readNowPlaying() -> Reading? {
        let running = NSWorkspace.shared.runningApplications
        // Music first, then Spotify. Both scripts return
        // "title<US>artist<US>state" while playing, "<empty><empty>state" otherwise.
        if running.contains(where: { $0.bundleIdentifier == "com.apple.Music" }) {
            if let r = read(appleScript: musicScript(), stateKey: "playing") { return r }
        }
        if running.contains(where: { $0.bundleIdentifier == "com.spotify.client" }) {
            if let r = read(appleScript: spotifyScript(), stateKey: "playing") { return r }
        }
        return nil
    }

    /// Script template shared by Music and Spotify — identical vocabulary.
    static func musicScript() -> String {
        playerScript(app: "Music")
    }
    static func spotifyScript() -> String {
        playerScript(app: "Spotify")
    }
    static func playerScript(app: String) -> String {
        """
        tell application "\(app)"
            if (player state as text) is "playing" then
                return (name of current track) & (character id 31) & (artist of current track) & (character id 31) & "playing"
            else
                return "" & (character id 31) & "" & (character id 31) & (player state as text)
            end if
        end tell
        """
    }

    private static func read(appleScript: String, stateKey: String) -> Reading? {
        guard let out = runAppleScript(appleScript) else { return nil }
        return parseNowPlaying(out, stateKey: stateKey)
    }

    /// Pure parser, unit-tested. Format: "title<US>artist<US>state".
    static func parseNowPlaying(_ raw: String, stateKey: String) -> Reading? {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\u{001F}")
        guard parts.count >= 3 else { return nil }
        let playing = parts[2].contains(stateKey)
        guard playing, !parts[0].isEmpty else { return nil }
        return Reading(title: parts[0], artist: parts[1], playing: playing)
    }

    /// osascript with a hard 1.2s budget — a wedged Apple event must never
    /// stall the poll thread.
    private static func runAppleScript(_ source: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(1.2)
        while p.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if p.isRunning { p.terminate(); return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return text.isEmpty ? nil : text
    }
}
