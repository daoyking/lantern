import AppKit
import SwiftUI

/// AppDelegate 负责应用生命周期管理：
/// 1. 注册 UserDefaults defaults
/// 2. 创建 StatusItem（菜单栏图标）
/// 3. 监听权限变更并触发对应 feature sync
/// 4. 面板窗口生命周期管理
final class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Singleton
    
    static let shared = AppDelegate()
    
    // MARK: - Properties
    
    /// StatusItemController 单例，管理菜单栏图标和面板
    lazy var statusItemController: StatusItemController = {
        let controller = StatusItemController()
        controller.appDelegate = self
        return controller
    }()
    
    /// 应用面板窗口（懒加载）
    private var panelWindow: NSWindow?

    /// True only when the panel window actually exists and is on screen.
    /// Never derive this from persisted UserDefaults — a stale "true" from a
    /// previous launch made clicks call hidePanel() on a nil window, so the
    /// panel appeared impossible to open.
    var isPanelVisible: Bool {
        panelWindow?.isVisible ?? false
    }
    
    // MARK: - NSApplicationDelegate
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 注册默认值
        registerDefaults()
        
        // 创建菜单栏 StatusItem
        statusItemController.setup()
        
        // 设置菜单栏右键菜单（Quit 等）
        setupMainMenu()
        
        // 注册服务实例到 FeatureRuntime
        registerServices()
        
        // 同步 feature 状态到 UserDefaults
        FeatureRuntime.shared.syncFromDefaults()
        
        // 启动权限监控
        // PermissionMonitor.shared.startMonitoring()
        
        Logger.info("Lantern launched — Bundle: \(Bundle.main.bundleIdentifier ?? "unknown")")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 保持运行（作为菜单栏 Agent）
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 点击 Dock icon（如果用户手动拖出）时恢复面板
        if !flag {
            statusItemController.togglePanel()
        }
        return false
    }
    
    // MARK: - Private
    
    /// 注册所有 UserDefaults 默认值
    private func registerDefaults() {
        let defaults = UserDefaults.standard
        
        // Panel state
        defaults.register(defaults: [
            DefaultsKey.panelVisible.rawValue: false,
            DefaultsKey.panelPosition.rawValue: "center",
        ])
        
        // Feature flags (Phase 2 将扩展到这里)
        // 目前仅保留基础结构
    }
    
    /// 创建应用主菜单（含 Quit）
    private func setupMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: String(localized: "menu.about"), action: nil, keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: String(localized: "menu.quit"), action: #selector(NSApp.terminate), keyEquivalent: "q"))
        
        NSApp.mainMenu = NSMenu()
        let applicationsMenuItem = NSMenuItem(title: String(localized: "app.name"), action: nil, keyEquivalent: "")
        applicationsMenuItem.submenu = appMenu
        NSApp.mainMenu?.addItem(applicationsMenuItem)
    }
    
    /// 显示面板 —— 定位到菜单栏图标正下方，确保完整落在屏幕内
    func showPanel() {
        if let window = panelWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelSize = PanelLayout.fittedSize(in: visible)

        // Anchor below the status item when available; the pure helper
        // guarantees the result stays inside `visible` (off-screen regression).
        let buttonWindow = statusItemController.statusItemWindow
        let origin = PanelLayout.origin(
            in: visible,
            anchorMidX: buttonWindow?.frame.midX,
            anchorMinY: buttonWindow?.frame.minY
        )

        let contentRect = NSRect(origin: origin, size: panelSize)
        let hostingView = NSHostingView(rootView: MenuPanelView())

        let window = NSPanel(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        window.title = Strings.appName.value
        window.isReleasedWhenClosed = false
        window.level = .popUpMenu
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.contentView = hostingView

        window.makeKeyAndOrderFront(nil)
        panelWindow = window

        UserDefaults.standard.setValue(true, forKey: DefaultsKey.panelVisible.rawValue)
    }
    
    // MARK: - Service Registration
    
    private func registerServices() {
        let runtime = FeatureRuntime.shared
        
        // KeepAwake service (needs accessibility permission)
        runtime.register(.keepAwake, service: KeepAwakeService(feature: .keepAwake), binding: {})
        
        // Clipboard history service (needs screen recording for pasteboard access)
        runtime.register(.clipboardHistory, service: ClipboardService(feature: .clipboardHistory), binding: {})
        
        // Scroll direction service (needs accessibility)
        runtime.register(.invertScroll, service: ScrollDirectionService(feature: .invertScroll), binding: {})
        
        // Energy monitor stub (for demo purposes)
        runtime.register(.cpuMonitor, service: EnergyMonitorService(feature: .cpuMonitor), binding: {})
        runtime.register(.memoryMonitor, service: EnergyMonitorService(feature: .memoryMonitor), binding: {})
        
        // Phase 6: Window management service
        runtime.register(.windowMinimizeAll, service: WindowManagerService(feature: .windowMinimizeAll), binding: {})
        runtime.register(.windowSwitchApp, service: WindowManagerService(feature: .windowSwitchApp), binding: {})
        
        // Phase 6: Sound mixer service  
        runtime.register(.soundVolumeUp, service: SoundMixerService(feature: .soundVolumeUp), binding: {})
        runtime.register(.soundVolumeDown, service: SoundMixerService(feature: .soundVolumeDown), binding: {})
        runtime.register(.soundMuteToggle, service: SoundMixerService(feature: .soundMuteToggle), binding: {})
        
        // Phase 7: Dynamic Island service (macOS 15+ only)
        if #available(macOS 15.0, *) {
            runtime.register(.dynamicIslandEnabled, service: DynamicIslandService(feature: .dynamicIslandEnabled), binding: {})
            runtime.register(.dynamicIslandShowCPU, service: DynamicIslandService(feature: .dynamicIslandShowCPU), binding: {})
            runtime.register(.dynamicIslandShowBattery, service: DynamicIslandService(feature: .dynamicIslandShowBattery), binding: {})
        }
    }
    
    /// 隐藏面板
    func hidePanel() {
        panelWindow?.close()
        panelWindow = nil
        
        UserDefaults.standard.setValue(false, forKey: DefaultsKey.panelVisible.rawValue)
    }
}

// MARK: - Logger

private enum Logger {
    static func info(_ message: String) {
        #if DEBUG
        print("[Lantern] \(message)")
        #endif
    }
}
