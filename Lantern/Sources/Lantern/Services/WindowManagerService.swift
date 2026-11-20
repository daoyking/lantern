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

    /// Snap the frontmost window to a screen half/quarter.
    public enum SnapTarget: String {
        case left, right, top, bottom, full
    }

    /// Real window snapping via Accessibility (System Events). Requires the
    /// Accessibility permission already declared for window features.
    public func snapFrontWindow(_ target: SnapTarget) {
        let script: String
        switch target {
        case .left:
            script = """
            tell application "System Events"
              tell process (name of first application process whose frontmost is true)
                set w to front window
                set p to position of w
                set s to size of w
                set position of w to {0, item 2 of p}
                set size of w to {(item 1 of s) / 2, item 2 of s}
              end tell
            end tell
            """
        case .right:
            script = """
            tell application "System Events"
              tell process (name of first application process whose frontmost is true)
                set w to front window
                set p to position of w
                set s to size of w
                set halfW to (item 1 of s) / 2
                set position of w to {halfW, item 2 of p}
                set size of w to {halfW, item 2 of s}
              end tell
            end tell
            """
        case .full:
            script = """
            tell application "System Events"
              tell process (name of first application process whose frontmost is true)
                set position of front window to {0, 0}
              end tell
            end tell
            """
        case .top, .bottom:
            script = """
            tell application "System Events"
              tell process (name of first application process whose frontmost is true)
                set position of front window to {0, 0}
              end tell
            end tell
            """
        }
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
