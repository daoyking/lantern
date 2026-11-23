import AppKit

// MARK: - System sound tester (Sapphire #15 subset)
//
// macOS ships a fixed set of named system sounds (no public enumeration
// API), so the list is curated. Enabling the feature reveals a play-grid
// in the tools tab; each button plays through NSSound.
final class SystemSoundsService: BaseFeatureService {

    static let shared = SystemSoundsService(feature: .systemSounds)

    /// The classic macOS alert set — every entry must resolve via NSSound(named:).
    static let soundNames = [
        "Basso", "Blow", "Bottle", "Frog",
        "Funk", "Glass", "Hero", "Morse",
        "Ping", "Pop", "Submarine", "Sosumi",
    ]

    @Published public private(set) var lastPlayed: String?

    override init(feature: AppFeature) { super.init(feature: feature) }

    override public func start() throws { /* visibility-only feature */ }
    override public func stop() throws { lastPlayed = nil }

    public func play(_ name: String) {
        guard Self.soundNames.contains(name), let sound = NSSound(named: name) else { return }
        sound.play()
        lastPlayed = name
    }
}
