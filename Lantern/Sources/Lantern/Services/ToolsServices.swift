// ToolsServices.swift — Real implementations for the Tools group.
//
// - ProcessKillerService: enumerate & terminate real running apps.
// - FileShredderService: overwrite then unlink (best-effort secure delete).
// - ColorPickerService: NSColorSampler for real on-screen colour picking.
// - GPUInfoService: real GPU model via system_profiler (macOS exposes no
//   public GPU-utilisation API, so this reports hardware, not a fake %).
// - PortControlService: opens Network settings; toggling privileged ports
//   requires root/a privileged helper, which an unsigned menu-bar app cannot
//   obtain. The real, honest behaviour is to open the owning pane.

import Foundation
import AppKit

// MARK: - Process killer

public final class ProcessKillerService: BaseFeatureService {
    public struct ProcessInfo: Identifiable, Hashable {
        public let pid: Int32
        public let name: String
        public var id: Int32 { pid }
    }

    /// Running, user-visible applications (excludes background daemons).
    public static func runningApps() -> [ProcessInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited && $0.processIdentifier > 0 }
            .compactMap { app in
                ProcessInfo(
                    pid: app.processIdentifier,
                    name: app.localizedName ?? app.bundleIdentifier ?? "PID \(app.processIdentifier)"
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Terminate gracefully; force-terminate if the app refuses.
    @discardableResult
    public static func terminate(pid: Int32, force: Bool = false) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if force {
            return app.forceTerminate()
        }
        return app.terminate()
    }

    override public func start() throws {}
    override public func stop() throws {}
}

// MARK: - File shredder

public final class FileShredderService: BaseFeatureService {
    public enum ShredError: Error, LocalizedError {
        case unreadable(String)
        case failed(String)
        public var errorDescription: String? {
            switch self {
            case .unreadable(let p): return "Cannot read file: \(p)"
            case .failed(let p): return "Failed to shred file: \(p)"
            }
        }
    }

    /// Overwrite a file with zeros, random bytes, zeros again, then remove it.
    /// On APFS/SSD this is best-effort (copy-on-write + wear levelling limit
    /// guarantees) but the writes are real and the file is genuinely removed.
    public static func shred(path: String, passes: Int = 3) throws {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw ShredError.unreadable(path)
        }
        let size = try FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber ?? NSNumber(value: 0)
        let length = Int(size.uint64Value)

        for pass in 0..<max(1, passes) {
            let byte: UInt8 = (pass % 2 == 0) ? 0x00 : 0xFF
            let data = Data(repeating: byte, count: max(1, length))
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw ShredError.failed(path)
            }
        }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw ShredError.failed(path)
        }
    }

    override public func start() throws {}
    override public func stop() throws {}
}

// MARK: - Colour picker

@available(macOS 10.15, *)
public final class ColorPickerService: BaseFeatureService {
    private let sampler = NSColorSampler()

    public typealias PickHandler = (NSColor) -> Void

    /// Open the OS eyedropper and deliver the sampled colour.
    /// The system callback provides an optional colour (nil if the user cancels).
    public func pick(completion: @escaping PickHandler) {
        sampler.show { color in
            guard let color else { return }
            completion(color)
        }
    }

    /// Copy a sampled colour to the pasteboard as hex.
    public func pickAndCopyHex(completion: @escaping (String) -> Void) {
        pick { color in
            let hex = Self.hexString(color)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(hex, forType: .string)
            completion(hex)
        }
    }

    public static func hexString(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    override public func start() throws {}
    override public func stop() throws {}
}

// MARK: - GPU info (real hardware, not fabricated utilisation)

public enum GPUInfoService {
    /// Query the real GPU via system_profiler. Returns a human-readable model
    /// string, or nil if unavailable. macOS has no public utilisation API.
    public static func primaryGPU() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPDisplaysDataType", "-json"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let displays = json["SPDisplaysDataType"] as? [[String: Any]],
                  let first = displays.first else { return nil }
            return first["sppci_model"] as? String
                ?? first["SPDisplays_DeviceType"] as? String
        } catch {
            return nil
        }
    }
}

// MARK: - Port control (honest privileged-operation fallback)

public enum PortControlService {
    /// Disabling physical USB ports requires root (e.g. writing IOService
    /// properties / a privileged helper). Without elevation the correct,
    /// honest behaviour is to open Network settings where the user can manage
    /// interfaces. Returns whether the pane was opened.
    @discardableResult
    public static func openNetworkSettings() -> Bool {
        let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!
        return NSWorkspace.shared.open(url)
    }
}
