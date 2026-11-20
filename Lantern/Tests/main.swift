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

print("▶ 1. 每个 feature（含无 service 的）toggle 都能切换")
for f in AppFeature.allCases {
    Check.that(!runtime.activeFeatures.contains(f), "\(f.rawValue) 初始应为关闭")
    runtime.toggle(f)
    Check.that(runtime.activeFeatures.contains(f), "\(f.rawValue) 打开失败（死开关回归）")
    runtime.toggle(f)
    Check.that(!runtime.activeFeatures.contains(f), "\(f.rawValue) 关闭失败")
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

cleanFeaturePrefs()
Check.finish()
