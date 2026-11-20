import AppKit

/// StatusItemController 管理菜单栏状态图标和交互：
/// 1. 创建 NSStatusItem
/// 2. 处理点击事件（toggle panel）
/// 3. 管理子图标（metrics、clipboard preview 等，Phase 2+ 实现）
class StatusItemController {
    
    // MARK: - Constants
    
    /// 菜单项标签前缀
    private enum MenuItemLabel {
        static let togglePanel = "Open Lantern"
        static let quit = "Quit Lantern"
    }
    
    // MARK: - Properties
    
    /// StatusItem 引用
    private var statusItem: NSStatusItem?
    
    weak var appDelegate: AppDelegate?
    
    // MARK: - Setup
    
    /// 初始化 StatusItem
    func setup() {
        let statusBar = NSStatusBar.system
        
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let item = statusItem else {
            fatalError("Failed to create status item")
        }
        
        // 设置图标（简单方块，后续可替换为 SVG/PNG）
        item.button?.image = NSImage(systemSymbolName: "square.on.rectangle.fill", accessibilityDescription: "Lantern")
        
        // 设置 context menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: MenuItemLabel.togglePanel, action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: MenuItemLabel.quit, action: #selector(NSApp.terminate), keyEquivalent: "q"))
        item.menu = menu
        
        // 点击行为
        item.action = #selector(togglePanel)
        
        print("[Lantern] StatusItem created")
    }
    
    // MARK: - Actions
    
    /// Toggle 面板可见性
    @objc func togglePanel() {
        let defaults = UserDefaults.standard
        let isVisible = defaults.bool(forKey: DefaultsKey.panelVisible.rawValue)
        
        if isVisible {
            appDelegate?.hidePanel()
        } else {
            appDelegate?.showPanel()
        }
    }
}
