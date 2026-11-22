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

    /// Global click monitor: dismiss the panel when clicking outside it.
    private var outsideClickMonitor: Any?

    /// Notification observer token for the in-panel close button / Esc.
    private var closeObserver: Any?

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
        
        // Close button / Esc inside the panel posts a notification.
        closeObserver = NotificationCenter.default.addObserver(
            forName: .lanternClosePanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hidePanel()
        }

        // 注册服务实例到 FeatureRuntime
        registerServices()
        
        // 同步 feature 状态到 UserDefaults
        FeatureRuntime.shared.syncFromDefaults()
        
        // 权限监控：Permissions.shared 在 init 里启动 2.5s 轮询。
        // 这里显式触碰一次，让首次检查发生在启动时刻（而不是等面板第一次
        // 打开才惰性初始化）——菜单栏 Agent 可能很久不开面板。
        _ = Permissions.shared
        
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
        appMenu.addItem(NSMenuItem(title: L("menu.about", "About Lantern"), action: nil, keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: L("ui.quit", "Quit Lantern"), action: #selector(NSApp.terminate), keyEquivalent: "q"))

        NSApp.mainMenu = NSMenu()
        let applicationsMenuItem = NSMenuItem(title: L("app.name", "Lantern"), action: nil, keyEquivalent: "")
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
        installOutsideClickMonitor()

        UserDefaults.standard.setValue(true, forKey: DefaultsKey.panelVisible.rawValue)
    }

    /// Dismiss the panel when the user clicks anywhere outside it — the
    /// expected behaviour for a menu-bar popover. Skip clicks on the status
    /// bar item itself: those go through togglePanel() and would double-fire.
    private func installOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, let window = self.panelWindow, window.isVisible else { return }
            let mouse = NSEvent.mouseLocation
            // Clicks in the menu bar (above the visible frame) are handled by
            // the status item action; ignore them here to avoid toggling twice.
            let screen = window.screen ?? NSScreen.main
            if let visibleMaxY = screen?.visibleFrame.maxY, mouse.y > visibleMaxY { return }
            if window.frame.contains(mouse) { return }
            self.hidePanel()
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
    
    // MARK: - Service Registration
    
    private func registerServices() {
        let runtime = FeatureRuntime.shared

        // ── Stateful: real system effects on start/stop ─────────────

        // Power assertion — real IOKit sleep prevention.
        runtime.register(.keepAwake, service: KeepAwakeService(feature: .keepAwake), binding: {})

        // Clipboard history — real NSPasteboard polling.
        runtime.register(.clipboardHistory, service: ClipboardService(feature: .clipboardHistory), binding: {})

        // Paste as plain text — real pasteboard rich→plain rewrite.
        runtime.register(
            .pasteAsPlainText,
            service: PastePlainTextService(feature: .pasteAsPlainText),
            binding: {}
        )

        // iCloud clipboard sync — real NSUbiquitousKeyValueStore mirror.
        runtime.register(
            .syncClipboardAcrossDevices,
            service: ClipboardSyncService(feature: .syncClipboardAcrossDevices),
            binding: {}
        )

        // Dock preferences — real defaults writes + Dock restart.
        runtime.register(.autoHideDock, service: PreferenceToggleService(
            feature: .autoHideDock,
            on: { DockSettings.setAutoHide(true) },
            off: { DockSettings.setAutoHide(false) }
        ), binding: {})
        runtime.register(.minimizeOnClickDock, service: PreferenceToggleService(
            feature: .minimizeOnClickDock,
            on: { DockSettings.setMinimizeOnClick(true) },
            off: { DockSettings.setMinimizeOnClick(false) }
        ), binding: {})
        // Dock size toggle: on → larger tiles, off → system default (38).
        runtime.register(.dockSize, service: PreferenceToggleService(
            feature: .dockSize,
            on: { DockSettings.setSize(56) },
            off: { DockSettings.setSize(38) }
        ), binding: {})

        // Scroll direction — live inversion via event tap (no re-login needed,
        // and the user's system preference stays untouched).
        runtime.register(.invertScroll,
                         service: ScrollInversionService(feature: .invertScroll),
                         binding: {})

        // Pointer speed / key repeat — real defaults + open owning settings pane.
        runtime.register(.mouseSensitivity, service: PreferenceToggleService(
            feature: .mouseSensitivity,
            on: { _ = InputSettings.setPointerSpeed(1.5) },
            off: { _ = InputSettings.setPointerSpeed(1.0) }
        ), binding: {})
        runtime.register(.keyboardRepeatRate, service: PreferenceToggleService(
            feature: .keyboardRepeatRate,
            on: { InputSettings.setKeyRepeat(intervalMs: 2, initialMs: 15) },
            off: { InputSettings.setKeyRepeat(intervalMs: 6, initialMs: 25) }
        ), binding: {})
        // Double-click speed & cursor size have no public programmatic key:
        // honest behaviour is to open the owning settings pane.
        runtime.register(.doubleClickSpeed, service: PreferenceToggleService(
            feature: .doubleClickSpeed,
            on: { SettingsPane.mouse.open() },
            off: {}
        ), binding: {})
        runtime.register(.cursorSize, service: PreferenceToggleService(
            feature: .cursorSize,
            on: { SettingsPane.display.open() },
            off: {}
        ), binding: {})

        // Energy monitors — real Mach/IOKit telemetry.
        runtime.register(.cpuMonitor, service: EnergyMonitorService(feature: .cpuMonitor), binding: {})
        runtime.register(.memoryMonitor, service: EnergyMonitorService(feature: .memoryMonitor), binding: {})
        runtime.register(.networkMonitor, service: EnergyMonitorService(feature: .networkMonitor), binding: {})
        runtime.register(.batteryDisplay, service: EnergyMonitorService(feature: .batteryDisplay), binding: {})
        runtime.register(.gpuMonitor, service: EnergyMonitorService(feature: .gpuMonitor), binding: {})

        // Audio toggle — real Core Audio mute, persisted as state.
        let mixer = SoundMixerService(feature: .audioToggle)
        runtime.register(.audioToggle, service: mixer, binding: {})
        // Notification sound — real sound preference + open Sound pane.
        runtime.register(.notificationSound, service: PreferenceToggleService(
            feature: .notificationSound,
            on: { NSSound.beep(); SettingsPane.sound.open() },
            off: {}
        ), binding: {})
        // Volume mixer — open Sound pane (per-app mixer has no public API).
        runtime.register(.volumeMixer, service: PreferenceToggleService(
            feature: .volumeMixer,
            on: { SettingsPane.sound.open() },
            off: {}
        ), binding: {})

        // Tools: process killer / shredder / color picker / port control.
        runtime.register(.processKiller, service: ProcessKillerService(feature: .processKiller), binding: {})
        runtime.register(.fileShredder, service: FileShredderService(feature: .fileShredder), binding: {})
        runtime.register(.portControl, service: PreferenceToggleService(
            feature: .portControl,
            on: { _ = PortControlService.openNetworkSettings() },
            off: {}
        ), binding: {})

        // ── One-shot actions ───────────────────────────────────────

        let windows = WindowManagerService(feature: .windowMinimizeAll)
        runtime.register(.windowMinimizeAll, service: windows) { windows.minimizeAll() }
        runtime.register(.windowSwitchApp, service: windows) { windows.switchToNextApp() }
        runtime.register(.hideAllWindows, service: windows) { windows.hideAllWindows() }
        runtime.register(.forceQuitDialog, service: windows) { windows.openForceQuitDialog() }
        runtime.register(.windowSnap, service: windows) {
            self.showSnapMenu(using: windows)
        }

        let actionsMixer = SoundMixerService(feature: .soundMuteToggle)
        runtime.register(.soundVolumeUp, service: actionsMixer) { actionsMixer.increaseVolume() }
        runtime.register(.soundVolumeDown, service: actionsMixer) { actionsMixer.decreaseVolume() }
        runtime.register(.soundMuteToggle, service: actionsMixer) { actionsMixer.toggleMute() }

        // Input device select — real Core Audio, cycle to next device.
        let devicesMixer = SoundMixerService(feature: .inputDeviceSelect)
        runtime.register(.inputDeviceSelect, service: devicesMixer) {
            let devices = devicesMixer.inputDevices()
            guard !devices.isEmpty else { return }
            let current = devicesMixer.currentInputDeviceID()
            let index = devices.firstIndex { $0.id == current } ?? -1
            let next = devices[(index + 1) % devices.count]
            _ = devicesMixer.selectInputDevice(next.id)
        }

        // Colour picker action — open eyedropper, copy hex to clipboard.
        if #available(macOS 10.15, *) {
            let picker = ColorPickerService(feature: .colorPicker)
            runtime.register(.colorPicker, service: picker) {
                picker.pickAndCopyHex { _ in }
            }
        }

        // Process killer — real app list via a menu, terminate on selection.
        runtime.register(.processKiller, service: ProcessKillerService(feature: .processKiller)) {
            self.showProcessKillerMenu()
        }

        // File shredder — pick files and securely overwrite+delete them.
        runtime.register(.fileShredder, service: FileShredderService(feature: .fileShredder)) {
            self.shredFilesWithPanel()
        }

        // Dynamic Island — real telemetry (macOS 15+ hardware gate in catalog).
        if #available(macOS 15.0, *) {
            runtime.register(.dynamicIslandEnabled, service: DynamicIslandService(feature: .dynamicIslandEnabled), binding: {})
            runtime.register(.dynamicIslandShowCPU, service: DynamicIslandService(feature: .dynamicIslandShowCPU), binding: {})
            runtime.register(.dynamicIslandShowBattery, service: DynamicIslandService(feature: .dynamicIslandShowBattery), binding: {})
        }
    }
    
    // MARK: - Tool actions

    /// Show a real menu of running apps; selecting one terminates it.
    private func showProcessKillerMenu() {
        let menu = NSMenu()
        let processes = ProcessKillerService.runningApps().prefix(40)
        for proc in processes {
            let item = NSMenuItem(title: "\(proc.name) (\(proc.pid))", action: #selector(killProcess(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = proc.pid
            menu.addItem(item)
        }
        if menu.items.isEmpty {
            menu.addItem(NSMenuItem(title: L("tool.noApps", "No running apps"), action: nil, keyEquivalent: ""))
        }
        // Anchor the menu just below the status item.
        let anchor = statusItemController.statusItemWindow?.frame.origin ?? NSPoint(x: 100, y: 800)
        menu.popUp(positioning: nil, at: anchor, in: nil)
    }

    @objc private func killProcess(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int32 else { return }
        _ = ProcessKillerService.terminate(pid: pid, force: false)
    }

    /// Four-way window snap — one action button opens a localized direction menu.
    private func showSnapMenu(using windows: WindowManagerService) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L("snap.menuTitle", "Snap Window To"), action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        for target in SnapTarget.allCases {
            let item = NSMenuItem(title: target.localizedName,
                                  action: #selector(snapWindow(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = (windows, target)
            menu.addItem(item)
        }
        let anchor = statusItemController.statusItemWindow?.frame.origin ?? NSPoint(x: 100, y: 800)
        menu.popUp(positioning: nil, at: anchor, in: nil)
    }

    @objc private func snapWindow(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? (WindowManagerService, SnapTarget) else { return }
        payload.0.snapFrontWindow(payload.1)
    }

    /// Open a file chooser, then securely overwrite and delete the selection.
    private func shredFilesWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = L("tool.shred", "Shred")
        panel.message = L("tool.shredMessage", "Select files to securely overwrite and delete")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            try? FileShredderService.shred(path: url.path)
        }
    }

    /// 隐藏面板
    func hidePanel() {
        removeOutsideClickMonitor()
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
