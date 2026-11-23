import AppKit

/// StatusItemController 管理菜单栏状态图标和交互：
/// 1. 创建 NSStatusItem
/// 2. 处理点击事件（toggle panel）
/// 3. 管理子图标（metrics、clipboard preview 等，Phase 2+ 实现）
class StatusItemController {
    
    // MARK: - Constants
    
    /// 菜单项标签前缀
    private enum MenuItemLabel {
        static var togglePanel: String { L("menu.open", "Open Lantern") }
        static var quit: String { L("ui.quit", "Quit Lantern") }
    }
    
    // MARK: - Properties
    
    /// StatusItem 引用
    private var statusItem: NSStatusItem?

    /// The status item's button window — used to anchor the panel below it.
    var statusItemWindow: NSWindow? {
        statusItem?.button?.window
    }

    /// Right-click menu (kept separate — assigning item.menu would swallow clicks).
    private var contextMenu: NSMenu?

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
        item.button?.image = NSImage(systemSymbolName: "lightbulb.fill", accessibilityDescription: "Lantern")
        
        // IMPORTANT: DO NOT set item.menu here. When a status item has a menu,
        // macOS intercepts left-clicks to show the menu and never fires the
        // action — so clicking the icon appeared to "do nothing".
        // Instead use the button's target/action for left-click and handle
        // right-click ourselves to show the context menu.
        let button = item.button
        button?.target = self
        button?.action = #selector(togglePanel)
        // Right-click shows the context menu (left-click is handled by action).
        let rightClick = NSClickGestureRecognizer(target: self, action: #selector(showContextMenu(_:)))
        rightClick.buttonMask = 0x02 // right mouse button
        button?.addGestureRecognizer(rightClick)

        contextMenu = {
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: MenuItemLabel.togglePanel,
                                    action: #selector(togglePanel), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            let quit = NSMenuItem(title: MenuItemLabel.quit,
                                  action: #selector(NSApp.terminate), keyEquivalent: "q")
            quit.target = NSApp
            menu.addItem(quit)
            return menu
        }()

        print("[Lantern] StatusItem created")
    }
    
    // MARK: - Actions
    
    /// 右键弹出上下文菜单（Quit / Open）
    @objc private func showContextMenu(_ recognizer: NSClickGestureRecognizer) {
        guard let button = recognizer.view, let menu = contextMenu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    /// Toggle 面板可见性 —— 以真实窗口状态为准，不用持久化的默认值
    @objc func togglePanel() {
        if appDelegate?.isPanelVisible == true {
            appDelegate?.hidePanel()
        } else if FaceIDService.panelIsLocked() {
            // Face Lock armed: verify before the panel opens.
            FaceIDService.shared.presentVerification(
                onSuccess: { [weak appDelegate] in appDelegate?.showPanel() },
                onFailure: { _ in }
            )
        } else {
            appDelegate?.showPanel()
        }
    }
}
