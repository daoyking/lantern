import SwiftUI

@main
struct LanternApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // 不使用 WindowGroup，因为这是菜单栏 Agent
        // 面板由 AppDelegate.showPanel() 手动创建
        Settings {
            Text("Settings placeholder (Phase 4)")
        }
    }
}
