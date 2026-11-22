// PerAppAudioService.swift — per-application audio control via process taps
//
// What ships here (honest scope):
//   1. Live list of every process currently emitting audio — public CoreAudio
//      properties (kAudioHardwarePropertyProcessObjectList + per-process
//      PID / BundleID / IsRunningOutput). No tap required, zero side effects.
//   2. Per-app MUTE through AudioHardwareCreateProcessTap: one private tap per
//      app with muteBehavior .muted. While the tap exists macOS itself holds
//      that process's audio from the hardware; destroying the tap restores
//      playback. No DSP, no rerouting, fully reversible.
//
// Deliberately NOT shipped: a continuous per-app volume slider. Real per-app
// gain needs muteBehavior .mutedWhenTapped + an aggregate device + an IOProc
// that rescales each tap's bus and injects the mix back — the multi-tap bus
// ordering is undocumented, and a wrong mixdown mutes or crackles the user's
// whole system. That pipeline is written up in the replica journal and stays
// deferred until it can be tested with ears in the loop.

import AppKit
import CoreAudio
import Foundation

/// One audio-emitting (or muted) application, as shown in the panel.
public struct AudioApp: Identifiable, Equatable {
    public let pid: pid_t
    public let processObjectID: AudioObjectID
    public let name: String
    public let bundleID: String?
    public let isRunningOutput: Bool
    public var id: pid_t { pid }
}

public final class PerAppAudioService: BaseFeatureService {

    /// Instance registered with FeatureRuntime — observed by the panel section.
    public private(set) static var shared: PerAppAudioService?

    // MARK: - State

    /// Apps emitting audio right now, plus muted apps pinned for unmuting.
    @Published public private(set) var apps: [AudioApp] = []

    /// pid → live tap object. Tap existence IS the mute state.
    private var muteTaps: [pid_t: AudioObjectID] = [:]

    private var timer: Timer?

    override public init(feature: AppFeature) {
        super.init(feature: feature)
        Self.shared = self
    }

    // MARK: - Lifecycle

    override public func start() throws {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    override public func stop() throws {
        timer?.invalidate()
        timer = nil
        removeAllMutes()   // fail-safe: never leave a mute tap behind
    }

    deinit {
        removeAllMutes()
    }

    // MARK: - Public API (panel)

    public func isMuted(_ pid: pid_t) -> Bool {
        muteTaps[pid] != nil
    }

    /// Tear down a mute tap (availability-checked; targets macOS 14.0).
    private func destroyTap(_ tap: AudioObjectID) {
        if #available(macOS 14.2, *) {
            AudioHardwareDestroyProcessTap(tap)
        }
    }

    /// Toggle one app's audio: tap created = macOS mutes that process;
    /// tap destroyed = playback resumes. Creating the tap can fail (noErr
    /// checked) — silence in the UI means failure was honest, not fake.
    public func toggleMute(_ app: AudioApp) {
        if let tap = muteTaps[app.pid] {
            destroyTap(tap)
            muteTaps[app.pid] = nil
        } else {
            guard #available(macOS 14.2, *) else { return }
            let desc = CATapDescription(
                __stereoMixdownOfProcesses: [NSNumber(value: app.processObjectID)]
            )
            desc.name = "Lantern mute \(app.pid)"
            desc.uuid = UUID()
            desc.isPrivate = true
            desc.muteBehavior = CATapMuteBehavior.muted
            var tapID = AudioObjectID(0)
            guard AudioHardwareCreateProcessTap(desc, &tapID) == noErr else { return }
            muteTaps[app.pid] = tapID
        }
        refresh()
    }

    // MARK: - Enumeration

    private func removeAllMutes() {
        for tap in muteTaps.values {
            destroyTap(tap)
        }
        muteTaps.removeAll()
    }

    private func refresh() {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        var list: [AudioApp] = []
        if AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
           size > 0 {
            let count = Int(size) / MemoryLayout<AudioObjectID>.stride
            var ids = [AudioObjectID](repeating: 0, count: count)
            if AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr {
                for procID in ids {
                    guard let pidValue = uint32Property(procID, kAudioProcessPropertyPID) else { continue }
                    let pid = pid_t(pidValue)
                    let runningOut = uint32Property(procID, kAudioProcessPropertyIsRunningOutput) == 1
                    let bundleID = stringProperty(procID, kAudioProcessPropertyBundleID)
                    // Emitting apps, plus muted apps pinned so they can be unmuted.
                    guard runningOut || muteTaps[pid] != nil else { continue }
                    list.append(AudioApp(
                        pid: pid,
                        processObjectID: procID,
                        name: appName(pid: pid, bundleID: bundleID),
                        bundleID: bundleID,
                        isRunningOutput: runningOut
                    ))
                }
            }
        }

        // Muted pids whose process object vanished: if the app quit, drop its
        // tap (dead taps are useless); if it merely went quiet, keep it pinned.
        let stalePids = muteTaps.keys.filter { pid in !list.contains(where: { $0.pid == pid }) }
        for pid in stalePids {
            if kill(pid, 0) != 0 {
                if let tap = muteTaps[pid] { destroyTap(tap) }
                muteTaps[pid] = nil
            } else {
                list.append(AudioApp(
                    pid: pid, processObjectID: 0,
                    name: appName(pid: pid, bundleID: nil),
                    bundleID: nil, isRunningOutput: false
                ))
            }
        }

        apps = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Helpers

    private func appName(pid: pid_t, bundleID: String?) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName {
            return name
        }
        return bundleID ?? "PID \(pid)"
    }

    private func uint32Property(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr,
              let cf = value else { return nil }
        return cf as String
    }
}
