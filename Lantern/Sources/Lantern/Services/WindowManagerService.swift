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
        let script = "tell application \"System Events\" to key tab using command down"
        if let appleScript = NSAppleScript(source: script) {
            var errorDict: NSDictionary?
            appleScript.executeAndReturnError(&errorDict)
        }
    }
    
    override public func start() throws {}
    override public func stop() throws {}
}
