// UpdateChecker.swift — in-app update check against GitHub Releases

import AppKit
import Foundation

/// Zero-dependency update checker. Reads the latest GitHub Release for the
/// published repository and compares its tag against the running bundle
/// version. Finding an update shows a pill in the panel footer that opens
/// the release page — it deliberately does NOT self-replace: the app is
/// ad-hoc signed, so a swap-on-the-fly risks Gatekeeper prompts and a TCC
/// identity reset (permissions would be re-asked). Notify + open is the
/// honest scope until real Developer ID signing exists.
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    /// Published repo — the same one build.sh artifacts are attached to.
    static let releasesAPI = "https://api.github.com/repos/daoyking/lantern/releases/latest"
    static let releasesPage = "https://github.com/daoyking/lantern/releases/latest"

    @Published private(set) var latestVersion: String?
    /// True when latestVersion parses strictly newer than the bundle.
    @Published private(set) var hasUpdate = false
    @Published private(set) var isChecking = false
    @Published private(set) var lastError: String?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Version comparison (pure, tested)

    /// Parse "v0.2.0", "0.2.0", "v0.2.0-1" into numeric components.
    /// Non-numeric junk yields nil — a malformed tag never looks "newer".
    static func parseVersion(_ tag: String) -> [Int]? {
        let trimmed = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let core = trimmed.split(separator: "-").first.map(String.init) ?? trimmed
        let parts = core.split(separator: ".")
        guard !parts.isEmpty, parts.count <= 4 else { return nil }
        var comps: [Int] = []
        for part in parts {
            guard let n = Int(part), n >= 0 else { return nil }
            comps.append(n)
        }
        return comps
    }

    /// Lexicographic comparison over numeric components; missing positions
    /// count as zero (0.2 > 0.1.9). Returns true only for strictly newer.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let c = parseVersion(candidate), let cur = parseVersion(current) else {
            return false
        }
        let width = max(c.count, cur.count)
        let padded = { (v: [Int]) in (0..<width).map { $0 < v.count ? v[$0] : 0 } }
        // Strictly newer = current precedes candidate (equality excluded by
        // the strict comparison itself).
        return padded(cur).lexicographicallyPrecedes(padded(c))
    }

    /// The running app's version, e.g. "0.1.0" (short) with build fallback.
    static var bundleVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let short, !short.isEmpty { return short }
        if let build, !build.isEmpty { return build }
        return "0.0.0"
    }

    // MARK: - Network

    /// Query the latest release. Network failures are surfaced via
    /// lastError for the manual path and swallowed by the auto path.
    func checkForUpdate() {
        guard !isChecking else { return }
        isChecking = true
        lastError = nil
        var request = URLRequest(url: URL(string: Self.releasesAPI)!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        session.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isChecking = false
                if let error {
                    self.lastError = error.localizedDescription
                    return
                }
                guard let data,
                      let tag = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?
                      .flatMap({ $0["tag_name"] as? String }) else {
                    self.lastError = L("update.badPayload", "Could not read release info")
                    return
                }
                self.latestVersion = tag
                self.hasUpdate = Self.isNewer(tag, than: Self.bundleVersion)
            }
        }.resume()
    }

    func openReleasePage() {
        NSWorkspace.shared.open(URL(string: Self.releasesPage)!)
    }
}
