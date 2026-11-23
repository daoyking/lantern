# P19 — GitHub 发布 + 应用内更新检查
日期：2026-11-23 · 提交 caf98248 · 1071 测试全绿 · Release v0.1.0

## 发布
- 仓库：daoyking/lantern（gh CLI 已登录，tracked 内容只有 Lantern/ 77 文件，secret 扫描干净）
- push 22 提交（abb4d352→caf98248）；DMG 51MB（hdiutil 需 danger-full-access，沙箱拒绝）
- **Release v0.1.0：https://github.com/daoyking/lantern/releases/tag/v0.1.0**（DMG + 中文发布说明：24 功能/权限一览/ad-hoc 安装提示）

## 应用内更新器（UpdateChecker.swift，零依赖 ~140 行）
- URLSession 读 api.github.com/repos/daoyking/lantern/releases/latest，Accept: vnd.github+json，10s 超时
- 纯函数 parseVersion（v 前缀/-build 后缀/垃圾输入 nil）+ isNewer（补零对齐字典序；**首版方向写反 lexicographicallyPrecedes 比较对象，▶37 3 断言抓出**）
- 入口：面板 .onAppear 静默检查（失败不上屏）+ 设置页"检查更新"按钮（isChecking 转圈/lastError 展示/已是最新文案）
- 新版呈现：面板 footer 蓝胶囊 pill（版本号+下载图标）+ 设置页 prominent 按钮 → 打开 release 页
- **诚实边界：不做自动替换安装**——ad-hoc 签名自替换有 Gatekeeper 拦截+TCC 身份重置（权限全部重问）风险；等 Developer ID 签名后再升级为下载+替换+重启
- zh-Hans 5 条（update.check/upToDate/available/openRelease/badPayload）
- ▶37 10 断言（解析 3/比较 6/接线 1）；坑：Tests/main.swift 无 section() helper（是直接 print，照 ▶35/36 样式）
