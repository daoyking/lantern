// cli_test_main.swift — Standalone regression/edge-case driver.
// Compiled directly with swiftc (bypasses SwiftPM's sandboxed manifest step).
// Mirrors the XCTest cases so logic can be verified in this environment.

import Foundation

// Tiny assertion harness
struct Check {
    static var passed = 0
    static var failed = 0
    static func that(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passed += 1
        } else {
            failed += 1
            FileHandle.standardError.write("  ✗ FAIL: \(message)\n".data(using: .utf8)!)
        }
    }
    static func finish() {
        print("\n结果: \(passed) 通过, \(failed) 失败")
        exit(failed == 0 ? 0 : 1)
    }
}

func cleanFeaturePrefs() {
    for f in AppFeature.allCases {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.featureEnabledKey(f.rawValue))
    }
}

let runtime = FeatureRuntime.shared

// Start clean
cleanFeaturePrefs()
for f in Array(runtime.activeFeatures) { runtime.stop(f) }

print("▶ 1. 每个 stateful feature（含无 service 的）toggle 都能切换；动作型执行后不锁状态；未授权的门控型保持关闭")
for f in AppFeature.allCases {
    let meta = FeatureCatalog.shared.metadata(for: f)
    let perm = meta.requiresPermission
    let gated = perm != nil && perm != PermissionType.none
        && !Permissions.shared.isGranted(perm!)
    Check.that(!runtime.activeFeatures.contains(f), "\(f.rawValue) 初始应为关闭")
    runtime.toggle(f)
    if meta.isAction {
        // One-shot actions never latch into activeFeatures (no dead switch,
        // no stale "on" state) — they just fire their binding.
        Check.that(!runtime.activeFeatures.contains(f), "\(f.rawValue) 动作型不应锁存 on 状态")
    } else if gated {
        // The gate asks for the permission instead of activating.
        Check.that(!runtime.activeFeatures.contains(f), "\(f.rawValue) 未授权时不应激活（门控回归）")
    } else {
        Check.that(runtime.activeFeatures.contains(f), "\(f.rawValue) 打开失败（死开关回归）")
        runtime.toggle(f)
        Check.that(!runtime.activeFeatures.contains(f), "\(f.rawValue) 关闭失败")
    }
}

print("▶ 2. Clipboard 组三个开关都是活的（截图问题）")
for f in [AppFeature.clipboardHistory, .pasteAsPlainText, .syncClipboardAcrossDevices] {
    runtime.toggle(f)
    Check.that(runtime.activeFeatures.contains(f), "\(f.rawValue) 开关无反应")
}
Check.that(runtime.activeFeatures.count == 3, "Clipboard 组应恰好 3 个激活")
for f in Array(runtime.activeFeatures) { runtime.stop(f) }

print("▶ 3. 快速连续 toggle 101 次保持奇偶一致")
let stress: AppFeature = .pasteAsPlainText
for i in 1...101 {
    runtime.toggle(stress)
    Check.that(runtime.activeFeatures.contains(stress) == (i % 2 == 1), "第 \(i) 次快速切换状态不一致")
}
runtime.stop(stress)

print("▶ 4. start/stop 重复调用幂等")
let idem: AppFeature = .syncClipboardAcrossDevices
runtime.start(idem); runtime.start(idem)
Check.that(runtime.activeFeatures.contains(idem), "重复 start 后应为开启")
runtime.stop(idem); runtime.stop(idem)
Check.that(!runtime.activeFeatures.contains(idem), "重复 stop 后应为关闭")

print("▶ 5. 每个分组都有内容，无空组")
for g in FeatureGroup.allCases {
    Check.that(!runtime.orderedFeatures(in: g).isEmpty, "分组 \(g.rawValue) 为空")
}

print("▶ 6. 每个 feature 都出现在自己分组里，且排序唯一稳定")
for f in AppFeature.allCases {
    Check.that(runtime.orderedFeatures(in: f.group).contains(f), "\(f.rawValue) 不在自己分组")
}
for g in FeatureGroup.allCases {
    let a = runtime.orderedFeatures(in: g)
    let b = runtime.orderedFeatures(in: g)
    Check.that(a == b, "分组 \(g.rawValue) 排序不稳定")
    Check.that(Set(a).count == a.count, "分组 \(g.rawValue) 有重复 feature")
}

print("▶ 7. tab 短标签足够短（360pt 栏宽）")
for g in FeatureGroup.allCases {
    Check.that(g.shortLabel.count <= 10, "\(g.rawValue) 短标签过长: \(g.shortLabel)")
}

print("▶ 8. toggle 立即持久化，且 syncFromDefaults 能恢复")
let persist: AppFeature = .pasteAsPlainText
let key = DefaultsKey.featureEnabledKey(persist.rawValue)
runtime.toggle(persist)
Check.that(UserDefaults.standard.bool(forKey: key), "开启状态未持久化")
runtime.stop(persist)
Check.that(!UserDefaults.standard.bool(forKey: key), "关闭状态未持久化")
UserDefaults.standard.set(true, forKey: key)
runtime.syncFromDefaults()
Check.that(runtime.activeFeatures.contains(persist), "持久化状态未被恢复")
runtime.stop(persist)

print("▶ 9. .none 权限恒为允许（Optional.none 歧义回归）")
Check.that(Permissions.shared.isGranted(.none), ".none 权限应为允许")
Check.that(FeatureCatalog.shared.isAvailable(.syncClipboardAcrossDevices), ".none 权限 feature 不应被拦截")

print("▶ 10. 所有 feature 元数据可查，无崩溃")
for f in AppFeature.allCases {
    Check.that(FeatureCatalog.shared.metadata(for: f).displayPriority >= 0, "\(f.rawValue) 元数据异常")
}

print("▶ 11. 面板定位：任何屏幕尺寸都完全落在可见区域内（off-screen 回归）")
let screenCases: [(name: String, screen: CGRect, anchorX: CGFloat?, anchorY: CGFloat?)] = [
    ("普通 1440x900", CGRect(x: 0, y: 0, width: 1440, height: 900), 1350, 880),
    ("菜单栏图标在正中央", CGRect(x: 0, y: 0, width: 1440, height: 900), 720, 880),
    ("图标贴最左边缘", CGRect(x: 0, y: 0, width: 1440, height: 900), 10, 880),
    ("图标贴最右边缘", CGRect(x: 0, y: 0, width: 1440, height: 900), 1435, 880),
    ("无锚点（图标窗口未知）", CGRect(x: 0, y: 0, width: 1440, height: 900), nil, nil),
    ("小屏 1024x768", CGRect(x: 0, y: 0, width: 1024, height: 768), 1000, 748),
    ("屏幕比面板还小 300x200", CGRect(x: 0, y: 0, width: 300, height: 200), 150, 190),
    ("带 Dock 偏移的可见区", CGRect(x: 0, y: 25, width: 1440, height: 850), 1400, 870),
]
for c in screenCases {
    let o = PanelLayout.origin(in: c.screen, anchorMidX: c.anchorX, anchorMinY: c.anchorY)
    Check.that(PanelLayout.isFullyVisible(origin: o, in: c.screen),
               "\(c.name) 面板跑到屏幕外: origin=(\(o.x), \(o.y))")
    Check.that(o.x >= 0 && o.y >= 0, "\(c.name) 坐标为负: (\(o.x), \(o.y))")
}
// The exact old bug: origin used visible.maxX/maxY directly → off-screen.
let oldBugScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
let oldBugOrigin = CGPoint(x: oldBugScreen.maxX, y: oldBugScreen.maxY)
Check.that(!PanelLayout.isFullyVisible(origin: oldBugOrigin, in: oldBugScreen),
           "旧 bug 坐标本应被判定为屏幕外（证明测试有效）")

print("▶ 12. 实现状态标注：每个 feature 都有明确 level，动作型都有真实 binding")
let catalog = FeatureCatalog.shared
for f in AppFeature.allCases {
    let meta = catalog.metadata(for: f)
    // badge 与实现级别一致
    switch meta.implementation {
    case .native: Check.that(meta.implementation.badge.isEmpty, "\(f.rawValue) native 不应有 badge")
    case .simulated: Check.that(meta.implementation.badge == "DEMO", "\(f.rawValue) 应为 DEMO badge")
    case .stub: Check.that(meta.implementation.badge == "未实现", "\(f.rawValue) 应为 未实现 badge")
    }
    // 动作型功能必须都不是默认激活的持久状态
    if meta.isAction {
        Check.that(!meta.installedByDefault, "动作型 \(f.rawValue) 不应默认激活")
    }
}

print("▶ 13. 动作型与状态型分类完整（音量/窗口为动作，KeepAwake/剪贴板为状态）")
Check.that(catalog.metadata(for: .soundVolumeUp).isAction, "音量+应为动作型")
Check.that(catalog.metadata(for: .soundMuteToggle).isAction, "静音应为动作型")
Check.that(catalog.metadata(for: .windowMinimizeAll).isAction, "最小化应为动作型")
Check.that(catalog.metadata(for: .windowSwitchApp).isAction, "切换 App 应为动作型")
Check.that(!catalog.metadata(for: .keepAwake).isAction, "KeepAwake 应为状态型")
Check.that(!catalog.metadata(for: .clipboardHistory).isAction, "剪贴板历史应为状态型")
Check.that(catalog.metadata(for: .keepAwake).implementation == .native, "KeepAwake 应为原生实现")
Check.that(catalog.metadata(for: .cpuMonitor).implementation == .native, "CPU 监控应为真实指标")
Check.that(catalog.metadata(for: .autoHideDock).implementation == .native, "Dock 自动隐藏应为真实设置")
Check.that(catalog.metadata(for: .pasteAsPlainText).implementation == .native, "纯文本粘贴应为真实实现")
Check.that(catalog.metadata(for: .keepAwake).implementation == .native, "防休眠应为真实实现")

print("▶ 15. 原生化后：一次性动作型功能完整分类")
for f in [AppFeature.windowSnap, .hideAllWindows, .forceQuitDialog,
          .colorPicker, .inputDeviceSelect, .processKiller, .fileShredder] {
    Check.that(catalog.metadata(for: f).isAction, "\(f.rawValue) 应为一次性动作型")
    Check.that(catalog.metadata(for: f).implementation == .native, "\(f.rawValue) 应为原生实现")
}
// 受系统限制、诚实降级的仍是 stub（打开设置面板，非假数据）
Check.that(catalog.metadata(for: .doubleClickSpeed).implementation == .stub, "双击速度应诚实标注为降级")
Check.that(catalog.metadata(for: .cursorSize).implementation == .stub, "光标大小应诚实标注为降级")
Check.that(catalog.metadata(for: .portControl).implementation == .stub, "端口管控需 root，应诚实标注")
Check.that(catalog.metadata(for: .gpuMonitor).implementation == .stub, "GPU 利用率无公开 API，应诚实标注")
// Dynamic Island 已是真窗口 + 真指标：悬浮面板渲染 SystemMetrics 实时遥测
Check.that(catalog.metadata(for: .dynamicIslandEnabled).implementation == .native,
           "Dynamic Island 应为原生实现（真窗口+真数据）")

print("▶ 16. 真实指标数学：CPU/网络/内存计算正确（极端边界）")
// CPU：全 idle → 0%；全 active → 100%
Check.that(MetricMath.cpuPercent(current: (0,0,100,0), previous: (0,0,0,0)) == 0, "全空闲 CPU 应为 0%")
Check.that(MetricMath.cpuPercent(current: (60,40,0,0), previous: (0,0,0,0)) == 100, "全占用 CPU 应为 100%")
Check.that(MetricMath.cpuPercent(current: (25,25,50,0), previous: (0,0,0,0)) == 50, "半占用 CPU 应为 50%")
// 无 delta（计数器未变）应安全返回 0，不除零
Check.that(MetricMath.cpuPercent(current: (10,10,10,10), previous: (10,10,10,10)) == 0, "CPU 无 delta 应为 0")
// 网络：1024KB/1s = 1024 KB/s；计数器回绕（重置）应返回 0
Check.that(MetricMath.rateKBps(current: 1024*1024, previous: 0, interval: 1.0) == 1024, "网络速率计算错误")
Check.that(MetricMath.rateKBps(current: 100, previous: 200, interval: 1.0) == 0, "网络计数器回绕应为 0")
Check.that(MetricMath.rateKBps(current: 100, previous: 100, interval: 0) == 0, "网络零间隔应为 0")
// 内存百分比边界
Check.that(MetricMath.percent(used: 50, total: 100) == 50, "内存百分比应为 50%")
Check.that(MetricMath.percent(used: 200, total: 100) == 100, "内存百分比应封顶 100%")
Check.that(MetricMath.percent(used: 10, total: 0) == 0, "内存总量为 0 应安全返回 0")
// 网络速率格式化
Check.that(EnergyMonitorService.formatRate(512) == "512 KB/s", "KB 速率格式化错误")
Check.that(EnergyMonitorService.formatRate(2048).contains("MB/s"), "MB 速率格式化错误")

print("▶ 14. 动作型 toggle 不改变持久状态（不会把音量+锁在 on）")
let action = AppFeature.soundVolumeUp
Check.that(!runtime.activeFeatures.contains(action), "动作型初始不应在 activeFeatures")
runtime.toggle(action) // 无 binding 时应安全 no-op，不崩溃、不锁状态
Check.that(!runtime.activeFeatures.contains(action), "动作型 toggle 后不应进入 activeFeatures")

print("▶ 17. 简体中文资源完整：每个功能名称/描述、分组、通用文案都有译文")
let stringsPath = FileManager.default.currentDirectoryPath
    + "/Resources/zh-Hans.lproj/Localizable.strings"
let translationTable = NSDictionary(contentsOfFile: stringsPath) as? [String: String]
Check.that(translationTable != nil, "zh-Hans Localizable.strings 应能解析")
if let table = translationTable {
    Check.that(table.count >= 150, "译文条目数应覆盖全部 UI，实际 \(table.count)")
    for f in AppFeature.allCases {
        let nameKey = "feature.\(f.rawValue).name"
        let descKey = "feature.\(f.rawValue).desc"
        Check.that(!(table[nameKey] ?? "").isEmpty, "\(f.rawValue) 缺少中文名称")
        Check.that(!(table[descKey] ?? "").isEmpty, "\(f.rawValue) 缺少中文描述")
    }
    for g in FeatureGroup.allCases {
        Check.that(!(table["group.\(g.rawValue).name"] ?? "").isEmpty, "\(g.rawValue) 缺少中文组名")
        Check.that(!(table["group.\(g.rawValue).short"] ?? "").isEmpty, "\(g.rawValue) 缺少中文短标签")
    }
    for key in ["ui.settings", "ui.done", "ui.quit", "ui.runNow", "settings.language",
                "hint.needsPermission", "hint.closePanel", "permission.accessibility",
                "badge.simulated", "badge.stub", "onboarding_welcome",
                "snap.left", "snap.right", "snap.top", "snap.bottom", "snap.full", "snap.menuTitle"] {
        Check.that(!(table[key] ?? "").isEmpty, "通用文案 \(key) 缺少译文")
    }
    Check.that(table["hint.needsPermission"]?.contains("%@") == true,
               "带参数的提示文案必须保留格式占位符")
    Check.that(table["settings.panelOpacity"]?.contains("%d%%") == true,
               "百分比文案必须保留格式占位符")
}

print("▶ 18. 语言默认值与真实 bundle 查表")
UserDefaults.standard.removeObject(forKey: "lantern.appLanguage")
Check.that(AppLanguage.current == .simplifiedChinese, "未设置语言时应默认简体中文")
Check.that(AppLanguage.resolved == .simplifiedChinese, "默认解析语言应为简体中文")
AppLanguage.current = .english
Check.that(AppLanguage.current == .english, "语言选择应可持久化")
Check.that(L("ui.settings", "Settings") == "Settings", "英文模式应回退到代码兜底文案")
UserDefaults.standard.removeObject(forKey: "lantern.appLanguage")

// 真实 app bundle（构建后存在）里的 .lproj 必须能被查到并返中文
let builtApp = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent(".build/release/Lantern.app")
if FileManager.default.fileExists(atPath: builtApp.path),
   let bundle = Bundle(url: builtApp),
   bundle.path(forResource: "zh-Hans", ofType: "lproj") != nil,
   let zhBundle = Bundle(path: bundle.path(forResource: "zh-Hans", ofType: "lproj")!) {
    Check.that(zhBundle.localizedString(forKey: "ui.settings", value: "Settings", table: nil) == "设置",
               "构建产物中的中文查表应返回「设置」")
    Check.that(zhBundle.localizedString(forKey: "feature.cpuMonitor.name", value: "CPU Monitor", table: nil) == "CPU 监控",
               "构建产物中的功能名应为中文")
}

print("▶ 19. 四向窗口吸附几何：避开菜单栏/Dock，半屏严格互补")
let fullScreen = CGRect(x: 0, y: 0, width: 1440, height: 900)
let usable = CGRect(x: 0, y: 0, width: 1440, height: 845) // 顶部菜单栏占 55pt
let left = SnapGeometry.rect(for: .left, screen: fullScreen, visible: usable)
let right = SnapGeometry.rect(for: .right, screen: fullScreen, visible: usable)
let top = SnapGeometry.rect(for: .top, screen: fullScreen, visible: usable)
let bottom = SnapGeometry.rect(for: .bottom, screen: fullScreen, visible: usable)
let full = SnapGeometry.rect(for: .full, screen: fullScreen, visible: usable)
Check.that(left.minX == 0 && right.maxX == 1440, "左右吸附应贴住屏幕边缘")
Check.that(left.width + right.width == 1440, "左右半屏宽度应互补")
Check.that(left.maxX == right.minX, "左右半屏不应重叠或留缝")
Check.that(left.height == 845 && right.height == 845, "左右吸附应占满可用高度")
Check.that(top.minY == 55 && bottom.maxY == 900, "上下吸附应避开菜单栏/Dock")
Check.that(top.height + bottom.height == 845, "上下半屏高度应互补")
Check.that(top.maxY == bottom.minY, "上下半屏不应重叠或留缝")
Check.that(full.origin.x == 0 && full.origin.y == 55 && full.width == 1440 && full.height == 845,
           "铺满屏幕应等于可用区域")
// 极端：极小屏幕 / Dock 在侧边 / visible 为空都不应产生负尺寸
for (name, screen, vis) in [
    ("极小屏幕", CGRect(x: 0, y: 0, width: 320, height: 240), CGRect(x: 0, y: 20, width: 320, height: 220)),
    ("侧边 Dock", CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 80, y: 0, width: 1360, height: 870)),
    ("异常 visible", CGRect(x: 0, y: 0, width: 1000, height: 700), CGRect.zero)
] {
    for target in SnapTarget.allCases {
        let r = SnapGeometry.rect(for: target, screen: screen, visible: vis)
        Check.that(r.width > 0 && r.height > 0, "\(name) \(target.rawValue) 尺寸应为正")
        Check.that(r.minX >= screen.minX && r.minY >= screen.minY, "\(name) \(target.rawValue) 不应越出屏幕左上")
    }
}

print("▶ 20. 权限门控：未授权 feature 的 action 被拦截，不执行 binding")

/// Minimal probe service for gate tests (keeps run-tests.sh compile list
/// Core-only — no real service files needed).
final class GateProbeService: BaseFeatureService {}

var gateBindingFired = false
runtime.register(.windowSnap,
                 service: GateProbeService(feature: .windowSnap),
                 binding: { gateBindingFired = true })
runtime.performAction(.windowSnap)
if Permissions.shared.isGranted(.accessibility) {
    Check.that(gateBindingFired, "辅助功能已授权时 action 应正常执行")
} else {
    Check.that(!gateBindingFired, "辅助功能未授权时 action 应被拦截（而非静默失败）")
}
runtime.unregister(.windowSnap)

// 状态型：门控发生在 start 之前，未授权时既不激活也不持久化
if let gated = AppFeature.allCases.first(where: {
    let p = FeatureCatalog.shared.metadata(for: $0).requiresPermission
    return p != nil && p != PermissionType.none && !Permissions.shared.isGranted(p!)
}) {
    UserDefaults.standard.removeObject(forKey: DefaultsKey.featureEnabledKey(gated.rawValue))
    runtime.toggle(gated)
    Check.that(!runtime.activeFeatures.contains(gated),
               "\(gated.rawValue) 未授权时 toggle 不应激活")
    Check.that(!UserDefaults.standard.bool(forKey: DefaultsKey.featureEnabledKey(gated.rawValue)),
               "\(gated.rawValue) 未授权时 toggle 不应持久化 enabled")
}

cleanFeaturePrefs()

// ▶21 电池解析：同时理解 macOS 27+ 带空格键名与旧版键名（岛电池缺失回归）
print("▶ 21. 电池解析双形状（macOS 27 数组新形状 + 旧字典形状）")
let modernSource: [String: Any] = [
    "Is Present": true, "Current Capacity": 80, "Max Capacity": 100,
    "Is Charging": false, "Power Source State": "AC Power",
]
let legacySource: [String: Any] = [
    "Is Present": true, "CurrentCapacity": 55, "MaxCapacity": 100,
    "Power Source State": "AC Power",
]
if let modern = MetricMath.battery(from: modernSource) {
    Check.that(modern.percent == 80.0, "新形状 80/100 → 80%")
    Check.that(modern.charging == false, "新形状 Is Charging=false → 未充电")
} else {
    Check.that(false, "新形状应解析成功")
}
if let legacy = MetricMath.battery(from: legacySource) {
    Check.that(legacy.percent == 55.0, "旧形状 55/100 → 55%")
    Check.that(legacy.charging == true, "旧形状 AC Power → 视为充电中")
} else {
    Check.that(false, "旧形状应解析成功")
}
Check.that(MetricMath.battery(from: ["CurrentCapacity": 50]) == nil, "缺 MaxCapacity 应拒绝")
Check.that(MetricMath.battery(from: ["CurrentCapacity": 50, "MaxCapacity": 0]) == nil, "MaxCapacity=0 应拒绝")
Check.that(MetricMath.battery(from: ["Is Present": false, "Current Capacity": 80, "Max Capacity": 100])?.percent == 80.0,
           "Is Present 由调用方过滤，解析只看容量")

// ▶22 岛槽位：新增时间/日期/音量/内存/网络开关，默认语义 + 持久化 + 组归属
print("▶ 22. 岛槽位可自定义（时间/日期/音量/内存/网络开关持久化）")
let slotFeatures: [AppFeature] = [
    .dynamicIslandShowVolume, .dynamicIslandShowTime, .dynamicIslandShowDate,
    .dynamicIslandShowMemory, .dynamicIslandShowNetwork,
]
let slotKeys: [DefaultsKey] = [
    .islandShowVolume, .islandShowTime, .islandShowDate, .islandShowMemory, .islandShowNetwork,
]
for f in slotFeatures {
    Check.that(f.group == .dynamicIsland, "\(f.rawValue) 应属于 dynamicIsland 组")
    Check.that(!FeatureCatalog.shared.metadata(for: f).isAction, "\(f.rawValue) 应为状态型开关")
}
// 默认语义：未写键时 time/memory/network 开、volume/date 关
for (key, expected) in [
    (DefaultsKey.islandShowTime, true), (DefaultsKey.islandShowMemory, true),
    (DefaultsKey.islandShowNetwork, true), (DefaultsKey.islandShowVolume, false),
    (DefaultsKey.islandShowDate, false),
] {
    UserDefaults.standard.removeObject(forKey: key.rawValue)
    Check.that(DynamicIslandService.slotEnabled(key, defaultIfUnset: expected) == expected,
               "\(key.rawValue) 未设置时应按默认 \(expected)")
}
// 开关持久化：测试进程没有跑 AppDelegate.registerServices，需先注册；
// 再停掉 ▶1 留下的 active 态，toggle ON → 键为 true，OFF → false
for (f, key) in zip(slotFeatures, slotKeys) {
    if runtime.activeFeatures.contains(f) { runtime.stop(f) }
    runtime.register(f, service: PreferenceToggleService(
        feature: f,
        on: { UserDefaults.standard.set(true, forKey: key.rawValue) },
        off: { UserDefaults.standard.set(false, forKey: key.rawValue) }
    ), binding: {})
    UserDefaults.standard.removeObject(forKey: DefaultsKey.featureEnabledKey(f.rawValue))
    UserDefaults.standard.removeObject(forKey: key.rawValue)
    runtime.toggle(f)
    Check.that(UserDefaults.standard.bool(forKey: key.rawValue),
               "\(f.rawValue) toggle ON 应写入 \(key.rawValue)=true")
    runtime.toggle(f)
    Check.that(!UserDefaults.standard.bool(forKey: key.rawValue),
               "\(f.rawValue) toggle OFF 应写入 \(key.rawValue)=false")
    runtime.unregister(f)
    UserDefaults.standard.removeObject(forKey: DefaultsKey.featureEnabledKey(f.rawValue))
    UserDefaults.standard.removeObject(forKey: key.rawValue)
}
// 音量快照：-1（无主音量设备）或 0–100
let vol = SystemMetrics().snapshot().volumePercent
Check.that(vol == -1 || (vol >= 0 && vol <= 100), "volumePercent 应为 -1 或 0–100，实际 \(vol)")
// 恢复时间槽默认开（试用机上面板常用态）
UserDefaults.standard.set(true, forKey: DefaultsKey.islandShowTime.rawValue)

cleanFeaturePrefs()
Check.finish()
