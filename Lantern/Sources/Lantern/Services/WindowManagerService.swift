import Foundation
import AppKit

public final class WindowManagerService: BaseFeatureService {
    
    public var windowCount: Int {
        return windows.count
    }
    
    public var activeApplicationName: String? {
        return NSWorkspace.shared.frontmostApplication?.localizedName
    }
    
    private var windows: [String] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        return windowList.compactMap { info in
            info["kCGWindowOwnerName"] as? String
        }.filter { !$0.isEmpty }
    }
    
    public func minimizeAll() {
        let script = """
        tell application "System Events"
            tell every process whose background only is false
                set miniaturized of every window to true
            end tell
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var errorDict: NSDictionary?
            appleScript.executeAndReturnError(&errorDict)
        }
    }
    
    public func switchToNextApp() {
        runScript("tell application \"System Events\" to key tab using command down")
    }

    /// Real window snapping via Accessibility (System Events). The target
    /// rectangle excludes the menu bar / Dock and is computed by the pure
    /// `SnapGeometry` helper so left/right/top/bottom/full all behave.
    public func snapFrontWindow(_ target: SnapTarget) {
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = NSScreen.main?.visibleFrame ?? screen
        let r = SnapGeometry.rect(for: target, screen: screen, visible: visible)
        let x = Int(r.minX.rounded())
        let y = Int(r.minY.rounded())
        let width = Int(r.width.rounded())
        let height = Int(r.height.rounded())
        let script = """
        tell application "System Events"
          tell process (name of first application process whose frontmost is true)
            set position of front window to {\(x), \(y)}
            set size of front window to {\(width), \(height)}
          end tell
        end tell
        """
        runScript(script)
    }

    /// Hide all regular apps (equivalent of Cmd+Opt+H) — real system action.
    public func hideAllWindows() {
        runScript("tell application \"System Events\" to keystroke \"h\" using {command down, option down}")
    }

    /// Open the OS force-quit dialog (Cmd+Opt+Esc) — real system action.
    public func openForceQuitDialog() {
        runScript("tell application \"System Events\" to keystroke escape using {command down, option down}")
    }

    public static func runScript(_ source: String) {
        if let appleScript = NSAppleScript(source: source) {
            var errorDict: NSDictionary?
            appleScript.executeAndReturnError(&errorDict)
            if let error = errorDict {
                NSLog("[Lantern] AppleScript error: \(error)")
            }
        }
    }

    private func runScript(_ source: String) {
        Self.runScript(source)
    }

    override public func start() throws {}
    override public func stop() throws {}
}
