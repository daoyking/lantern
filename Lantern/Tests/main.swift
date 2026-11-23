// cli_test_main.swift — Standalone regression/edge-case driver.
// Compiled directly with swiftc (bypasses SwiftPM's sandboxed manifest step).
// Mirrors the XCTest cases so logic can be verified in this environment.

import CryptoKit
import Foundation
import EventKit

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

// ▶23 天气槽：Open-Meteo 解析、WMO 符号映射、槽位开关接线
print("▶ 23. 天气槽（Open-Meteo 解析 + WMO 符号 + 开关持久化）")
let sampleJSON = #"{"current":{"time":"2026-11-22T14:00","temperature_2m":18.4,"weather_code":63,"is_day":1}}"#
let sampleData = sampleJSON.data(using: .utf8)!
if let parsed = IslandWeatherService.parse(sampleData) {
    Check.that(abs(parsed.temp - 18.4) < 0.001, "温度应解析为 18.4，实际 \(parsed.temp)")
    Check.that(parsed.code == 63, "天气码应解析为 63，实际 \(parsed.code)")
} else {
    Check.that(false, "样例 JSON 应解析成功")
}
Check.that(IslandWeatherService.parse(Data("{}".utf8)) == nil, "缺 current 字段应返回 nil")
Check.that(IslandWeatherService.parse(Data("not json".utf8)) == nil, "坏 JSON 应返回 nil")
// WMO 码 → SF Symbol
Check.that(IslandWeatherService.symbol(for: 0) == "sun.max.fill", "晴应映射 sun.max.fill")
Check.that(IslandWeatherService.symbol(for: 2) == "cloud.sun.fill", "少云应映射 cloud.sun.fill")
Check.that(IslandWeatherService.symbol(for: 45) == "cloud.fog.fill", "雾应映射 cloud.fog.fill")
Check.that(IslandWeatherService.symbol(for: 63) == "cloud.rain.fill", "雨应映射 cloud.rain.fill")
Check.that(IslandWeatherService.symbol(for: 73) == "cloud.snow.fill", "雪应映射 cloud.snow.fill")
Check.that(IslandWeatherService.symbol(for: 95) == "cloud.bolt.rain.fill", "雷暴应映射 cloud.bolt.rain.fill")
Check.that(IslandWeatherService.symbol(for: 999) == "cloud.fill", "未知码应兜底 cloud.fill")
// WMO 码 → 条件词（本地化键 + 英文兜底）
Check.that(IslandWeatherService.condition(for: 0).key == "wmo.clear", "0 应映射晴")
Check.that(IslandWeatherService.condition(for: 2).key == "wmo.partly", "2 应映射多云")
Check.that(IslandWeatherService.condition(for: 3).key == "wmo.overcast", "3 应映射阴")
Check.that(IslandWeatherService.condition(for: 63).key == "wmo.rain", "63 应映射雨")
Check.that(IslandWeatherService.condition(for: 95).key == "wmo.thunder", "95 应映射雷雨")
// 槽位：组归属 + 状态型 + 开关持久化（默认关）
Check.that(AppFeature.dynamicIslandShowWeather.group == .dynamicIsland, "天气开关应属于 dynamicIsland 组")
Check.that(!FeatureCatalog.shared.metadata(for: .dynamicIslandShowWeather).isAction, "天气开关应为状态型")
if runtime.activeFeatures.contains(.dynamicIslandShowWeather) { runtime.stop(.dynamicIslandShowWeather) }
runtime.register(.dynamicIslandShowWeather, service: PreferenceToggleService(
    feature: .dynamicIslandShowWeather,
    on: { UserDefaults.standard.set(true, forKey: DefaultsKey.islandShowWeather.rawValue) },
    off: { UserDefaults.standard.set(false, forKey: DefaultsKey.islandShowWeather.rawValue) }
), binding: {})
UserDefaults.standard.removeObject(forKey: DefaultsKey.islandShowWeather.rawValue)
Check.that(DynamicIslandService.slotEnabled(.islandShowWeather, defaultIfUnset: false) == false,
           "天气槽未设置时应默认关")
runtime.toggle(.dynamicIslandShowWeather)
Check.that(UserDefaults.standard.bool(forKey: DefaultsKey.islandShowWeather.rawValue),
           "天气槽 toggle ON 应写入 true")
runtime.toggle(.dynamicIslandShowWeather)
Check.that(!UserDefaults.standard.bool(forKey: DefaultsKey.islandShowWeather.rawValue),
           "天气槽 toggle OFF 应写入 false")
runtime.unregister(.dynamicIslandShowWeather)
UserDefaults.standard.removeObject(forKey: DefaultsKey.islandShowWeather.rawValue)

// ▶24 音乐控制：媒体键编码、now-playing 解析、三动作特征
print("▶ 24. 音乐控制（媒体键编码 + now-playing 解析 + 槽位接线）")
// 媒体键事件 data1 编码：高位 keyCode，低字节 0xA=按下 / 0xB=抬起
Check.that(MusicControllerService.mediaKeyEventData1(keyCode: 16, keyDown: true) == (16 << 16) | 0x0A,
           "播放键按下应编码 (16<<16)|0x0A")
Check.that(MusicControllerService.mediaKeyEventData1(keyCode: 16, keyDown: false) == (16 << 16) | 0x0B,
           "播放键抬起应编码 (16<<16)|0x0B")
Check.that(MusicControllerService.mediaKeyEventData1(keyCode: 17, keyDown: true) == (17 << 16) | 0x0A,
           "下一首键按下应编码 (17<<16)|0x0A")
Check.that(MusicControllerService.mediaKeyEventData1(keyCode: 18, keyDown: false) == (18 << 16) | 0x0B,
           "上一首键抬起应编码 (18<<16)|0x0B")
Check.that(MusicControllerService.keyPlay == 16 && MusicControllerService.keyNext == 17
           && MusicControllerService.keyPrevious == 18,
           "NX 媒体键码应为 16/17/18")
// now-playing 解析："title<US>artist<US>state"
let us = "\u{001F}"
Check.that(MusicControllerService.parseNowPlaying("歌名\(us)歌手\(us)playing", stateKey: "playing")?.title == "歌名",
           "播放中应解析出歌名")
Check.that(MusicControllerService.parseNowPlaying("歌名\(us)歌手\(us)playing", stateKey: "playing")?.artist == "歌手",
           "播放中应解析出歌手")
Check.that(MusicControllerService.parseNowPlaying("\(us)\(us)paused", stateKey: "playing") == nil,
           "暂停态应返回 nil")
Check.that(MusicControllerService.parseNowPlaying("歌名\(us)歌手\(us)playing".replacingOccurrences(of: "playing", with: "stopped"), stateKey: "playing") == nil,
           "停止态应返回 nil")
Check.that(MusicControllerService.parseNowPlaying("no-separator", stateKey: "playing") == nil,
           "无分隔符应返回 nil")
Check.that(MusicControllerService.parseNowPlaying("a\(us)b", stateKey: "playing") == nil,
           "字段不足应返回 nil")
// AppleScript 模板：两个播放器同构，只差应用名
Check.that(MusicControllerService.musicScript().contains(#"tell application "Music""#),
           "Music 脚本应指向 Music.app")
Check.that(MusicControllerService.spotifyScript().contains(#"tell application "Spotify""#),
           "Spotify 脚本应指向 Spotify.app")
Check.that(MusicControllerService.musicScript().contains("player state as text"),
           "脚本应查询播放状态")
// 特征接线：三动作属于 sound 组且都是动作型；音乐槽开关属于岛组且默认关
Check.that(AppFeature.musicPlayPause.group == .sound
           && AppFeature.musicNextTrack.group == .sound
           && AppFeature.musicPrevTrack.group == .sound,
           "三个音乐动作应属于 sound 组")
Check.that(FeatureCatalog.shared.metadata(for: .musicPlayPause).isAction
           && FeatureCatalog.shared.metadata(for: .musicNextTrack).isAction
           && FeatureCatalog.shared.metadata(for: .musicPrevTrack).isAction,
           "三个音乐动作应为动作型特征")
Check.that(AppFeature.dynamicIslandShowMusic.group == .dynamicIsland,
           "音乐槽开关应属于 dynamicIsland 组")
Check.that(!FeatureCatalog.shared.metadata(for: .dynamicIslandShowMusic).isAction,
           "音乐槽开关应为状态型")
if runtime.activeFeatures.contains(.dynamicIslandShowMusic) { runtime.stop(.dynamicIslandShowMusic) }
runtime.register(.dynamicIslandShowMusic, service: PreferenceToggleService(
    feature: .dynamicIslandShowMusic,
    on: { UserDefaults.standard.set(true, forKey: DefaultsKey.islandShowMusic.rawValue) },
    off: { UserDefaults.standard.set(false, forKey: DefaultsKey.islandShowMusic.rawValue) }
), binding: {})
UserDefaults.standard.removeObject(forKey: DefaultsKey.islandShowMusic.rawValue)
Check.that(DynamicIslandService.slotEnabled(.islandShowMusic, defaultIfUnset: false) == false,
           "音乐槽未设置时应默认关")
runtime.toggle(.dynamicIslandShowMusic)
Check.that(UserDefaults.standard.bool(forKey: DefaultsKey.islandShowMusic.rawValue),
           "音乐槽 toggle ON 应写入 true")
runtime.toggle(.dynamicIslandShowMusic)
Check.that(!UserDefaults.standard.bool(forKey: DefaultsKey.islandShowMusic.rawValue),
           "音乐槽 toggle OFF 应写入 false")
runtime.unregister(.dynamicIslandShowMusic)
UserDefaults.standard.removeObject(forKey: DefaultsKey.islandShowMusic.rawValue)

// ▶25 日历槽：next-event 选择纯函数 + 槽位接线（EventKit 只读，TCC 由用户驱动）
do {
    print("▶25 日历（next-event）")
    // Build real EKEvents against a throwaway store — title/start/allDay are writable.
    let store = EKEventStore()
    let now = Date()
    func ev(_ title: String?, _ start: Date, allDay: Bool = false) -> EKEvent {
        let e = EKEvent(eventStore: store)
        e.title = title
        e.startDate = start
        e.endDate = start.addingTimeInterval(3600)
        e.isAllDay = allDay
        return e
    }

    let cal = Calendar.current
    // 1. earliest event wins
    let a = ev("早会", now.addingTimeInterval(7200))
    let b = ev("晚些", now.addingTimeInterval(10800))
    let picked = CalendarService.nextEvent(from: [b, a], after: now, calendar: cal)
    Check.that(picked?.title == "早会", "应选中最早的事件")
    Check.that(picked?.allDay == false, "普通事件 allDay 应为 false")
    // 2. all-day events surface with the allDay flag (sorted by start)
    let allDay = ev("全天假", now.addingTimeInterval(-3600), allDay: true)
    let picked2 = CalendarService.nextEvent(from: [b, allDay], after: now, calendar: cal)
    Check.that(picked2?.allDay == true, "全天事件应标记 allDay")
    // 3. same-day started-in-past event still counts (isDate inSameDayAs)
    let earlierToday = ev("今早已开始", now.addingTimeInterval(-1800))
    let picked3 = CalendarService.nextEvent(from: [earlierToday], after: now, calendar: cal)
    Check.that(picked3?.title == "今早已开始", "今天已开始的事件仍在窗口内")
    // 4. empty list → nil
    Check.that(CalendarService.nextEvent(from: [], after: now, calendar: cal) == nil,
               "无事件应返回 nil")
    // 5. time caption: normal → HH:mm zero-padded; all-day → bullet
    if let reading = picked {
        let caption = CalendarService.timeCaption(for: reading, calendar: cal)
        Check.that(caption.count == 5 && caption.contains(":"), "时间题注应为 HH:mm 形式: \(caption)")
    }
    let bullet = CalendarService.timeCaption(
        for: CalendarService.Reading(title: "x", start: now, allDay: true), calendar: cal)
    Check.that(bullet == "•", "全天事件题注应为圆点")
    // 6. feature wiring
    Check.that(AppFeature.dynamicIslandShowNextEvent.group == .dynamicIsland,
               "下一日程开关应属于 dynamicIsland 组")
    Check.that(!FeatureCatalog.shared.metadata(for: .dynamicIslandShowNextEvent).isAction,
               "下一日程开关应为状态型")
    if runtime.activeFeatures.contains(.dynamicIslandShowNextEvent) { runtime.stop(.dynamicIslandShowNextEvent) }
    runtime.register(.dynamicIslandShowNextEvent, service: PreferenceToggleService(
        feature: .dynamicIslandShowNextEvent,
        on: { UserDefaults.standard.set(true, forKey: DefaultsKey.islandShowNextEvent.rawValue) },
        off: { UserDefaults.standard.set(false, forKey: DefaultsKey.islandShowNextEvent.rawValue) }
    ), binding: {})
    UserDefaults.standard.removeObject(forKey: DefaultsKey.islandShowNextEvent.rawValue)
    Check.that(DynamicIslandService.slotEnabled(.islandShowNextEvent, defaultIfUnset: false) == false,
               "下一日程槽未设置时应默认关")
    runtime.toggle(.dynamicIslandShowNextEvent)
    Check.that(UserDefaults.standard.bool(forKey: DefaultsKey.islandShowNextEvent.rawValue),
               "下一日程槽 toggle ON 应写入 true")
    runtime.toggle(.dynamicIslandShowNextEvent)
    Check.that(!UserDefaults.standard.bool(forKey: DefaultsKey.islandShowNextEvent.rawValue),
               "下一日程槽 toggle OFF 应写入 false")
    runtime.unregister(.dynamicIslandShowNextEvent)
    UserDefaults.standard.removeObject(forKey: DefaultsKey.islandShowNextEvent.rawValue)
}

// ▶26 护眼 20-20-20：间隔/时长常量、状态型特征、toggle 持久化
do {
    print("▶26 护眼（20-20-20）")
    Check.that(EyeBreakService.breakInterval == 20 * 60, "休息间隔应为 20 分钟")
    Check.that(EyeBreakService.breakDuration == 20, "遮罩时长应为 20 秒")
    Check.that(AppFeature.eyeBreak.group == .tools, "护眼应属于 tools 组")
    Check.that(!FeatureCatalog.shared.metadata(for: .eyeBreak).isAction,
               "护眼应为状态型（周期开关而非动作）")
    // Toggle persists; the service never shows UI in tests (no start()).
    if runtime.activeFeatures.contains(.eyeBreak) { runtime.stop(.eyeBreak) }
    runtime.register(.eyeBreak, service: EyeBreakService.shared, binding: {})
    UserDefaults.standard.removeObject(forKey: DefaultsKey.featureEnabledKey("eyeBreak"))
    Check.that(!runtime.activeFeatures.contains(.eyeBreak), "注册后默认未激活")
    runtime.toggle(.eyeBreak)
    Check.that(runtime.activeFeatures.contains(.eyeBreak), "toggle ON 应激活护眼")
    Check.that(UserDefaults.standard.bool(forKey: DefaultsKey.featureEnabledKey("eyeBreak")),
               "toggle ON 应持久化")
    // start() schedules a timer; stop() must tear it down and not reschedule.
    runtime.stop(.eyeBreak)
    Check.that(!runtime.activeFeatures.contains(.eyeBreak), "toggle OFF 应停用护眼")
    Check.that(!UserDefaults.standard.bool(forKey: DefaultsKey.featureEnabledKey("eyeBreak")),
               "toggle OFF 应清除持久化")
    runtime.unregister(.eyeBreak)
    UserDefaults.standard.removeObject(forKey: DefaultsKey.featureEnabledKey("eyeBreak"))
}

// ▶27 快速计时器：时长启动/同键取消/换键重开、mm:ss 题注、特征接线
do {
    print("▶27 快速计时器")
    let t = QuickTimerService(feature: .quickTimer)
    // Start 5 → running with endAt ≈ now+300
    t.start(minutes: 5)
    Check.that(t.durationMinutes == 5, "启动 5 分钟后 durationMinutes 应为 5")
    Check.that(t.endAt != nil && abs(t.endAt!.timeIntervalSinceNow - 300) < 2,
               "endAt 应约在 300 秒后")
    Check.that(t.remainingSeconds > 295 && t.remainingSeconds <= 300,
               "剩余秒数应接近 300")
    Check.that(t.caption.hasPrefix("04:") || t.caption.hasPrefix("05:"),
               "mm:ss 题注应接近 05:00: \(t.caption)")
    // Tap same duration again → cancel
    t.start(minutes: 5)
    Check.that(t.endAt == nil && t.durationMinutes == nil, "同键再按应取消")
    // Restart with a different duration → replaced
    t.start(minutes: 10)
    t.start(minutes: 25)
    Check.that(t.durationMinutes == 25 && abs(t.endAt!.timeIntervalSinceNow - 1500) < 2,
               "换时长应重开为 25 分钟")
    t.cancel()
    Check.that(t.endAt == nil, "cancel 应清空 endAt")
    // Feature wiring: state toggle gates; three actions are action-type
    Check.that(AppFeature.quickTimer.group == .tools &&
               AppFeature.timerStart5.group == .tools &&
               AppFeature.timerStart10.group == .tools &&
               AppFeature.timerStart25.group == .tools,
               "计时器特征应全部属于 tools 组")
    Check.that(!FeatureCatalog.shared.metadata(for: .quickTimer).isAction,
               "quickTimer 应为状态型")
    Check.that(FeatureCatalog.shared.metadata(for: .timerStart5).isAction &&
               FeatureCatalog.shared.metadata(for: .timerStart10).isAction &&
               FeatureCatalog.shared.metadata(for: .timerStart25).isAction,
               "三个时长按钮应为动作型")
    if runtime.activeFeatures.contains(.quickTimer) { runtime.stop(.quickTimer) }
    runtime.register(.quickTimer, service: QuickTimerService.shared, binding: {})
    let key = DefaultsKey.featureEnabledKey("quickTimer")
    UserDefaults.standard.removeObject(forKey: key)
    runtime.toggle(.quickTimer)
    Check.that(runtime.activeFeatures.contains(.quickTimer) &&
               UserDefaults.standard.bool(forKey: key),
               "quickTimer toggle ON 应激活并持久化")
    runtime.toggle(.quickTimer)
    Check.that(!runtime.activeFeatures.contains(.quickTimer), "quickTimer toggle OFF 应停用")
    runtime.unregister(.quickTimer)
    UserDefaults.standard.removeObject(forKey: key)
    // The three action features exist in the catalog metadata map
    Check.that(FeatureCatalog.shared.metadata(for: .timerStart25).displayPriority == 10,
               "timerStart25 应有目录元数据")
}

// ▶28 专注会话：25 分钟会话/剩余秒计算/中断恢复/特征接线
do {
    print("▶28 专注会话")
    let focus = FocusService.shared
    // Idle: nothing running
    focus.setRunning(false)
    Check.that(focus.endAt == nil && focus.remainingSeconds == 0, "空闲态无会话")
    // Start a session via the service lifecycle
    try? focus.start()
    Check.that(focus.endAt != nil, "start() 应开启会话")
    let remaining = focus.remainingSeconds
    Check.that(remaining > FocusService.sessionSeconds - 5 && remaining <= FocusService.sessionSeconds,
               "剩余秒应接近 25 分钟整 (\(remaining))")
    let cap = focus.caption
    Check.that(cap == "25:00" || (cap.hasSuffix(":59") || cap.hasSuffix(":58")),
               "mm:ss 题注应格式正确 (\(cap))")
    // Interrupt restores
    focus.interrupt()
    Check.that(focus.endAt == nil && focus.interrupted, "interrupt() 应中止会话")
    // Lifecycle stop while idle is a no-op
    try? focus.stop()
    Check.that(focus.endAt == nil, "stop() 空闲无副作用")
    // Wiring: group, state type, priority, persistence
    Check.that(AppFeature.focusMode.group == .tools &&
               !FeatureCatalog.shared.metadata(for: .focusMode).isAction &&
               FeatureCatalog.shared.metadata(for: .focusMode).implementation == .native,
               "focusMode 应为 tools 组状态型 .native")
    let runtime = FeatureRuntime.shared
    if runtime.activeFeatures.contains(.focusMode) { runtime.stop(.focusMode) }
    runtime.register(.focusMode, service: FocusService.shared, binding: {})
    let key = DefaultsKey.featureEnabledKey("focusMode")
    UserDefaults.standard.removeObject(forKey: key)
    runtime.toggle(.focusMode)
    Check.that(runtime.activeFeatures.contains(.focusMode) &&
               UserDefaults.standard.bool(forKey: key),
               "focusMode toggle ON 应激活并持久化")
    runtime.toggle(.focusMode)
    Check.that(!runtime.activeFeatures.contains(.focusMode), "focusMode toggle OFF 应停用")
    runtime.unregister(.focusMode)
    UserDefaults.standard.removeObject(forKey: key)
}

// ▶29 快捷启动：六预设 LaunchServices 解析/接线
do {
    print("▶29 快捷启动")
    // Every preset resolves to an installed app on a stock macOS.
    for feature in [AppFeature.launchSafari, .launchTerminal, .launchNotes,
                    .launchCalculator, .launchCalendar, .launchMail] {
        Check.that(QuickLaunchService.appURL(for: feature) != nil,
                   "\(feature.rawValue) 应能通过 LaunchServices 解析")
    }
    Check.that(QuickLaunchService.appURL(for: .keepAwake) == nil,
               "非预设特征应返回 nil")
    // Wiring: tools group, action type, priorities
    let launchFeatures: [AppFeature] = [.launchSafari, .launchTerminal, .launchNotes,
                                        .launchCalculator, .launchCalendar, .launchMail]
    Check.that(launchFeatures.allSatisfy { $0.group == .tools },
               "快捷启动应全部属于 tools 组")
    Check.that(launchFeatures.allSatisfy { FeatureCatalog.shared.metadata(for: $0).isAction },
               "快捷启动应全部为动作型")
    Check.that(FeatureCatalog.shared.metadata(for: .launchSafari).displayPriority == 12 &&
               FeatureCatalog.shared.metadata(for: .launchMail).displayPriority == 17,
               "快捷启动优先级应递增")
}

// ▶30 剪贴板历史持久化：写入→新实例恢复→清空持久化
do {
    print("▶30 剪贴板持久化")
    UserDefaults.standard.removeObject(forKey: ClipboardService.storageKey)
    let itemA = ClipboardItem(type: .string, content: "hello-lantern", timestamp: Date())
    let itemB = ClipboardItem(type: .url, content: "https://example.com", timestamp: Date())
    let data = try JSONEncoder().encode([itemA, itemB])
    UserDefaults.standard.set(data, forKey: ClipboardService.storageKey)
    let service = ClipboardService(feature: .clipboardHistory)
    Check.that(service.getHistory().count == 2 &&
               service.getHistory().first?.content == "hello-lantern",
               "新实例应恢复已持久化的历史")
    service.clearHistory()
    let cleared = try? JSONDecoder().decode([ClipboardItem].self,
        from: UserDefaults.standard.data(forKey: ClipboardService.storageKey) ?? Data())
    Check.that(cleared != nil && cleared?.isEmpty == true,
               "清空应持久化空数组")
    Check.that(service.getHistory().isEmpty, "清空后内存历史为空")
    UserDefaults.standard.removeObject(forKey: ClipboardService.storageKey)
}

// ▶31 Gemini Live：协议帧构造/解析、特征接线、defaults 键
do {
    print("▶31 Gemini Live")
    // setup 帧：模型、TEXT 模态、可选 systemInstruction
    let setupData = GeminiLiveSession.setupMessage(config: .init(
        apiKey: "k", model: "gemini-2.0-flash-live-001",
        modality: .text, voiceName: nil, systemPrompt: "be brief"))
    let setupObj = try JSONSerialization.jsonObject(with: setupData) as! [String: Any]
    let setup = setupObj["setup"] as! [String: Any]
    Check.that(setup["model"] as? String == "models/gemini-2.0-flash-live-001",
               "setup 帧应带 models/ 前缀模型名")
    let gen = setup["generationConfig"] as! [String: Any]
    Check.that((gen["responseModalities"] as? [String]) == ["TEXT"],
               "M1 setup 应声明 TEXT 模态")
    let si = setup["systemInstruction"] as! [String: Any]
    Check.that(((si["parts"] as! [[String: Any]])[0])["text"] as? String == "be brief",
               "setup 帧应携带 systemInstruction")
    let setupNoPrompt = GeminiLiveSession.setupMessage(
        config: .init(apiKey: "k", model: "m", modality: .text, voiceName: nil, systemPrompt: nil))
    let noPromptObj = try JSONSerialization.jsonObject(with: setupNoPrompt) as! [String: Any]
    Check.that((noPromptObj["setup"] as! [String: Any])["systemInstruction"] == nil,
               "无 system prompt 时 setup 帧不应带 systemInstruction")

    // clientContent 帧
    let turnData = GeminiLiveSession.clientContentMessage(text: "hi")
    let turn = try JSONSerialization.jsonObject(with: turnData) as! [String: Any]
    let cc = turn["clientContent"] as! [String: Any]
    let turns = cc["turns"] as! [[String: Any]]
    Check.that(turns[0]["role"] as? String == "user" &&
               ((turns[0]["parts"] as! [[String: Any]])[0])["text"] as? String == "hi" &&
               (cc["turnComplete"] as? Bool) == true,
               "clientContent 帧应为 user turn + turnComplete")

    // 下行解析
    func frame(_ json: String) -> GeminiLiveSession.ServerEvent? {
        GeminiLiveSession.parseServer(Data(json.utf8))
    }
    Check.that(frame(#"{"setupComplete":{}}"#) == .setupComplete, "setupComplete 解析")
    Check.that(frame(#"{"serverContent":{"modelTurn":{"parts":[{"text":"he"},{"text":"llo"}]}}}"#)
               == .modelText("hello"), "modelTurn 文本应拼接")
    Check.that(frame(#"{"serverContent":{"turnComplete":true}}"#) == .turnComplete,
               "turnComplete 解析")
    Check.that(frame(#"{"serverContent":{"interrupted":true}}"#) == .interrupted,
               "interrupted 解析")
    Check.that(frame(#"{"error":{"message":"boom"}}"#) == .error("boom"), "error 解析")
    Check.that(frame(#"{"serverContent":{"other":1}}"#) == nil &&
               frame("not json") == nil,
               "未知形状/坏 JSON 应返回 nil")
    Check.that(frame(#"{"serverContent":{"outputTranscription":{"text":"hi","finished":false}}}"#)
               == .outputTranscription("hi", finished: false), "outputTranscription 解析")

    // 特征接线
    Check.that(AppFeature.geminiLiveEnabled.group == .tools &&
               FeatureCatalog.shared.metadata(for: .geminiLiveEnabled).implementation == .native &&
               !FeatureCatalog.shared.metadata(for: .geminiLiveEnabled).isAction,
               "geminiLiveEnabled 应为 tools 组状态型 native")
    Check.that(AppFeature.dynamicIslandShowGemini.group == .dynamicIsland,
               "dynamicIslandShowGemini 应属灵动岛组")

    // defaults 键 + service 快照
    Check.that(!DefaultsKey.islandShowGemini.rawValue.isEmpty &&
               !DefaultsKey.geminiAPIKey.rawValue.isEmpty &&
               !DefaultsKey.geminiModel.rawValue.isEmpty,
               "Gemini defaults 键齐备")
    let gemini = GeminiLiveService.shared
    UserDefaults.standard.set("  test-key  ", forKey: DefaultsKey.geminiAPIKey.rawValue)
    Check.that(gemini.apiKey == "test-key", "API key 应去空白")
    UserDefaults.standard.removeObject(forKey: DefaultsKey.geminiModel.rawValue)
    Check.that(gemini.model == GeminiLiveService.defaultModel, "未设模型应回默认")
    Check.that(!gemini.isOpen, "未连接时 isOpen 为 false")
    UserDefaults.standard.removeObject(forKey: DefaultsKey.geminiAPIKey.rawValue)
}


// ▶32 Gemini Live M2：语音 setup 帧/音频解析/PCM 转换/接线
do {
    print("▶32 Gemini Live M2")
    // 音频 setup 帧：AUDIO 模态 + 声音名 + 双向转写
    let audioSetup = GeminiLiveSession.setupMessage(config: .init(
        apiKey: "k", model: "gemini-2.5-flash-native-audio-preview-12-2025",
        modality: .audio, voiceName: "Aoede", systemPrompt: nil))
    let obj = try JSONSerialization.jsonObject(with: audioSetup) as! [String: Any]
    let setup = obj["setup"] as! [String: Any]
    let gen = setup["generationConfig"] as! [String: Any]
    Check.that((gen["responseModalities"] as? [String]) == ["AUDIO"], "语音 setup 应声明 AUDIO 模态")
    let speech = gen["speechConfig"] as! [String: Any]
    let voiceCfg = speech["voiceConfig"] as! [String: Any]
    let prebuilt = voiceCfg["prebuiltVoiceConfig"] as! [String: Any]
    Check.that(prebuilt["voiceName"] as? String == "Aoede", "语音 setup 应带 Aoede 声音")
    Check.that(setup["inputAudioTranscription"] != nil && setup["outputAudioTranscription"] != nil,
               "语音 setup 应开双向转写")

    // realtimeInput 上行帧
    let up = GeminiLiveSession.realtimeAudioMessage(pcm16: Data([0x01, 0x02]))
    let upObj = try JSONSerialization.jsonObject(with: up) as! [String: Any]
    let ri = upObj["realtimeInput"] as! [String: Any]
    let audio = ri["audio"] as! [String: Any]
    Check.that(audio["mimeType"] as? String == "audio/pcm;rate=16000" &&
               audio["data"] as? String == Data([0x01, 0x02]).base64EncodedString(),
               "上行帧应为 16k PCM + base64")

    // 下行音频解析（用序列化构造帧，避免裸字符串引号拼接）
    let payload = Data([0x10, 0x20]).base64EncodedString()
    let downFrame: [String: Any] = ["serverContent": [
        "modelTurn": ["parts": [["inlineData": [
            "mimeType": "audio/pcm;rate=24000",
            "data": payload,
        ]]]]
    ]]
    let ev = GeminiLiveSession.parseServer(try! JSONSerialization.data(withJSONObject: downFrame))
    Check.that(ev == .modelAudio(base64: payload, mimeType: "audio/pcm;rate=24000"),
               "inlineData 音频应解析为 modelAudio")
    Check.that(GeminiLiveSession.parseServer(Data(
        #"{"serverContent":{"inputTranscription":{"text":"你好"}}}"#.utf8))
        == .inputTranscription("你好"), "inputTranscription 解析")

    // mimeType 速率解析
    Check.that(GeminiAudioPipe.pcmRate(fromMimeType: "audio/pcm;rate=24000") == 24000 &&
               GeminiAudioPipe.pcmRate(fromMimeType: "audio/L16;rate=16000") == 16000 &&
               GeminiAudioPipe.pcmRate(fromMimeType: "audio/pcm") == nil,
               "pcmRate 应从 mimeType 提取速率")

    // Int16 → Float32 缓冲
    let samples: [Int16] = [0, 16384, -16384, 32767, -32768]
    let buf = GeminiAudioPipe.floatBuffer(
        fromPCM16: samples.withUnsafeBufferPointer { Data(buffer: $0) }, sampleRate: 24000)
    Check.that(buf != nil && buf?.frameLength == 5 &&
               abs(buf!.floatChannelData![0][1] - 0.5) < 0.01 &&
               abs(buf!.floatChannelData![0][4] - (-1.0)) < 0.001,
               "Int16 PCM 应转 Float32 并归一化")

    // 接线：geminiLiveTalk = tools 状态型；voice gate 翻转 voiceMode
    Check.that(AppFeature.geminiLiveTalk.group == .tools &&
               FeatureCatalog.shared.metadata(for: .geminiLiveTalk).implementation == .native &&
               !FeatureCatalog.shared.metadata(for: .geminiLiveTalk).isAction,
               "geminiLiveTalk 应为 tools 组状态型 native")
    let voice = GeminiVoiceService.shared
    try voice.start()
    Check.that(GeminiLiveService.shared.voiceMode == true, "voice gate start 应切语音模式")
    try voice.stop()
    Check.that(GeminiLiveService.shared.voiceMode == false, "voice gate stop 应回文本模式")
    Check.that(!DefaultsKey.geminiVoiceModel.rawValue.isEmpty &&
               GeminiLiveService.shared.voiceModel == GeminiLiveService.defaultVoiceModel,
               "语音模型键齐备且回默认")
}


// ▶33 Gemini Live M3：工具声明/toolCall 解析/toolResponse 帧/工具执行/屏幕帧协议
do {
    print("▶33 Gemini Live M3")
    // setup 帧带 tools 声明
    let setupData = GeminiLiveSession.setupMessage(config: .init(
        apiKey: "k", model: "m", modality: .text, voiceName: nil, systemPrompt: nil))
    let obj = try JSONSerialization.jsonObject(with: setupData) as! [String: Any]
    let setup = obj["setup"] as! [String: Any]
    let tools = setup["tools"] as! [[String: Any]]
    let decls = tools[0]["functionDeclarations"] as! [[String: Any]]
    Check.that(decls.count >= 8, "工具声明应不少于 8 个")
    let names = Set(decls.compactMap { $0["name"] as? String })
    Check.that(names.contains("start_timer") && names.contains("open_app") &&
               names.contains("music_play_pause") && names.contains("battery_level"),
               "核心工具应齐备")

    // toolCall 下行解析（argsJSON 往返）
    let callFrame: [String: Any] = ["toolCall": ["functionCalls": [
        ["id": "call-1", "name": "start_timer", "args": ["minutes": 5]]
    ]]]
    let ev = GeminiLiveSession.parseServer(try! JSONSerialization.data(withJSONObject: callFrame))
    let ok: Bool
    if case .toolCall(let id, let name, let argsJSON) = ev {
        let args = (try? JSONSerialization.jsonObject(with: Data(argsJSON.utf8))) as? [String: Any]
        ok = id == "call-1" && name == "start_timer" && (args?["minutes"] as? Int) == 5
    } else { ok = false }
    Check.that(ok, "toolCall 应解析出 id/name/args")

    // toolResponse 帧
    let respData = GeminiLiveSession.toolResponseMessage(
        id: "call-1", name: "start_timer", result: "{\"result\": \"ok\"}")
    let resp = try JSONSerialization.jsonObject(with: respData) as! [String: Any]
    let fr = (resp["toolResponse"] as! [String: Any])["functionResponses"] as! [[String: Any]]
    Check.that(fr[0]["id"] as? String == "call-1" && fr[0]["name"] as? String == "start_timer" &&
               ((fr[0]["response"] as! [String: Any])["result"] as? String) == "{\"result\": \"ok\"}",
               "toolResponse 帧形状正确")

    // realtimeInput.video 帧
    let vidData = GeminiLiveSession.realtimeVideoMessage(jpeg: Data([0xFF, 0xD8]))
    let vid = try JSONSerialization.jsonObject(with: vidData) as! [String: Any]
    let vframe = (vid["realtimeInput"] as! [String: Any])["video"] as! [String: Any]
    Check.that(vframe["mimeType"] as? String == "image/jpeg" &&
               vframe["data"] as? String == Data([0xFF, 0xD8]).base64EncodedString(),
               "video 帧应为 jpeg + base64")

    // 工具执行：计时器开/关走真服务
    let started = GeminiToolRegistry.execute(name: "start_timer", args: ["minutes": 7])
    Check.that(started.contains("timer started for 7 minutes") &&
               QuickTimerService.shared.endAt != nil, "start_timer 应启动计时器")
    _ = GeminiToolRegistry.execute(name: "cancel_timer", args: [:])
    Check.that(QuickTimerService.shared.endAt == nil, "cancel_timer 应取消计时器")
    Check.that(GeminiToolRegistry.execute(name: "open_app", args: ["name": "NotAnApp"])
               .contains("unknown app"), "未知 app 应报错")
    Check.that(GeminiToolRegistry.execute(name: "no_such_tool", args: [:])
               .contains("unknown tool"), "未知工具应报错")
    Check.that(GeminiToolRegistry.appURL(forName: "Safari") != nil &&
               GeminiToolRegistry.appURL(forName: "  terminal ") != nil &&
               GeminiToolRegistry.appURL(forName: "Nonexistent") == nil,
               "appURL 应大小写/空白容错")

    // 接线
    Check.that(AppFeature.geminiScreenFrames.group == .tools &&
               FeatureCatalog.shared.metadata(for: .geminiScreenFrames).implementation == .native &&
               !FeatureCatalog.shared.metadata(for: .geminiScreenFrames).isAction,
               "geminiScreenFrames 应为 tools 组状态型 native")
    Check.that(!DefaultsKey.geminiScreenFrames.rawValue.isEmpty,
               "屏幕帧 defaults 键齐备")
}


// ▶34 Nearby Share：帧协议/密钥协商/加密往返/分块重组/接线
do {
    print("▶34 Nearby Share")
    // 帧构造/解析往返
    let frames: [NearbyFrame] = [
        .hello(name: "MacBook", pubKey: "abc123"),
        .offer(id: "t1", sender: "A", kind: "text", text: "hi there", fileNames: []),
        .accept(id: "t1"),
        .reject(id: "t2"),
        .chunk(id: "t1", index: 3, data: Data([0x00, 0xFF, 0x7F, 0x80]), last: false),
        .chunk(id: "t1", index: 9, data: Data([0x01]), last: true),
        .done(id: "t1"),
    ]
    for frame in frames {
        Check.that(NearbyFrame.parse(frame.data) == frame,
                   "帧往返应等值：\(frame)")
    }
    Check.that(NearbyFrame.parse(Data("junk".utf8)) == nil &&
               NearbyFrame.parse(Data(#"{"t":"unknown"}"#.utf8)) == nil,
               "坏帧应解析为 nil")

    // 密钥协商：双方从固定私钥推导出相同会话密钥
    let privA = try! P256.KeyAgreement.PrivateKey(rawRepresentation: Data((0..<32).map { UInt8($0 + 1) }))
    let privB = try! P256.KeyAgreement.PrivateKey(rawRepresentation: Data((0..<32).map { UInt8($0 + 100) }))
    let keyA = NearbyCrypto.sessionKey(privateKey: privA, peerPublicKeyData: privB.publicKey.x963Representation)
    let keyB = NearbyCrypto.sessionKey(privateKey: privB, peerPublicKeyData: privA.publicKey.x963Representation)
    Check.that(keyA != nil && keyB != nil &&
               keyA!.withUnsafeBytes { Data($0) } == keyB!.withUnsafeBytes { Data($0) },
               "双方应推导出相同会话密钥")

    // 加密往返 + 篡改检测
    let secret = Data("round trip".utf8)
    let sealedBox = NearbyCrypto.seal(secret, key: keyA!)
    Check.that(sealedBox != nil && NearbyCrypto.open(sealedBox!, key: keyB!) == secret,
               "A 加密 B 应能解密原文")
    var tampered = sealedBox!
    tampered[tampered.count - 1] ^= 0xFF
    Check.that(NearbyCrypto.open(tampered, key: keyB!) == nil,
               "被篡改的帧应解密失败")

    // 4 字节大端长度前缀
    let wire = NearbyCrypto.prefixed(Data([0xAA, 0xBB]))
    Check.that(Array(wire.prefix(4)) == [0, 0, 0, 2] &&
               NearbyCrypto.unprefix([UInt8](wire))?.payload == Data([0xAA, 0xBB]) &&
               NearbyCrypto.unprefix([0, 0]) == nil,
               "长度前缀编解码应正确")

    // 分块重组
    let long = Data((0..<200_000).map { UInt8($0 % 251) })
    let chunks = NearbyPeerSession.chunks(of: long)
    Check.that(chunks.count == 5 && chunks.allSatisfy { $0.count <= NearbyShareService.chunkSize } &&
               Data(chunks.joined()) == long,
               "200KB 应分 5 块且重组等值")
    Check.that(NearbyPeerSession.chunks(of: Data()) == [Data()], "空数据应为单空块")

    // 接线：clipboard 组状态型 native
    Check.that(AppFeature.nearbyShare.group == .clipboard &&
               FeatureCatalog.shared.metadata(for: .nearbyShare).implementation == .native &&
               !FeatureCatalog.shared.metadata(for: .nearbyShare).isAction,
               "nearbyShare 应为 clipboard 组状态型 native")
}

cleanFeaturePrefs()
Check.finish()
