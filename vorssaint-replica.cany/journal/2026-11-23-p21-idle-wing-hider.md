# P21 — 待机时钟翼 + 菜单栏收纳（Hidden Bar 整合）
日期：2026-11-23 · 1089 测试全绿 · pid 86198

## ①时间/日期/天气 → 待机态（用户 m02989）
- 待机岛从 184×32（纯刘海幻觉）→ **460×32 黑板**：真刘海占中 184，右翼放时钟行（HH:mm 12pt rounded semibold + 日期 10pt 55% + 天气 icon+温度 cyan），右对齐 trailing 14pt
- **展开态彻底移除 time/date/weather 三芯片**（hero 时钟已覆盖时间+日期）；enabledSlots 只剩 nextEvent/timer/focus/gemini/volume/cpu/memory/battery/network
- DynamicIslandService：compactSize 460 常量（宽度稳定不随天气可用性抖动）；enabledSlotCount 删除（无人引用）；展开尺寸 340 不变（展开时左右收 60pt 动画）

## ②MenuBarHiderService（Hidden Bar 整合，机制移植自 consolelabs/hidden MIT）
- **上游考古**：原版 Hidden Bar 已更名 consolelabs/hidden（15.5k 星）；其 LegacyLengthEngine（≤26 分离符膨胀法）+ NativeVisibilityEngine（27+ 原生法）+ HBNativeVisibilityShim.m 全读
- **macOS 27 机制**：私有 MenuBarClientCore 框架（考试锁屏模式复用）——dlopen → MBAssessmentModeConfiguration(initWithAllowedSystemItems:allowedBundleIdentifiers:) → MBAssessmentModeAssertion(activateWithConfiguration:completionHandler:) → 持 assertion 期间 macOS 只显示 allow-list 内的状态项；invalidate 恢复
- **纯 Swift 绑定**（无 ObjC shim）：dlsym objc_msgSend unsafeBitCast 成 @convention(c) 闭包；availability 门=框架+两类+三选择器全 resolve 才走 native；selector 全 NSSelectorFromString 防改名崩溃
- allow-list=Array(0..<64)（系统项：时钟/Spotlight/控制中心）+ 本 bundle（自家箭头）
- **≤26 回退**：separator NSStatusItem（箭头先建=最右、分离符后建）膨胀 max(500, min(屏宽×2, 10000))（macOS 27 会 eject 膨胀分离符 #360，故仅回退用）
- AppFeature menuBarHider（tools 状态型 priority 25 native）；start=建项+引擎选择；stop=expand+摘项；deinit fail-safe invalidate
- zh 2 条（feature.menuBarHider.name/desc）
- ▶38 18 断言：**本机实测 MenuBarClientCore resolve+assertion 持有/释放往返成功**（测试进程真实持有又释放）；引擎选择/长度数学/组归属/teardown
- build.sh:100 + run-tests.sh:48 登记（python 批量插行曾造成 FaceIDService 重复行+缺续行符，已手修）

## 验证
- 1089 通过 0 失败；探针：待机岛 460×32 @x=526（1512 屏居中）；部署 pid 86198，time/date/weather 三槽预置 true
