# Lantern — macOS Menu Bar Agent

Clean-room Swift recreation of [vorssaint-utils](https://github.com/vorssaint/vorssaint-utils), a comprehensive macOS menu bar utility suite.

**Bundle ID:** `me.lantern.menubar`  
**License:** GPL-3.0  
**Minimum macOS:** 14.0 (Sonoma)  
**Swift version:** 6.4.2+  

## Overview

Lantern provides a single status item in your menu bar with accessible toggles for system utilities. The panel's seven tab bar groups let you control everything from window management to energy monitoring, with the island integrating realtime vitals on macOS 15+.

### What's Real

| Feature | State |
|---------|-------|
| Window management (minimize all, switch app, snap) | Real NSWorkspace calls, zero TCC |
| Clipboard history | Persisted across relaunches |
| Dynamic Island | Full 7-slot layout, shown on supported Macs |
| Per-app volume mute | CoreBluetooth/tap path, macOS 14.2+ |
| Bluetooth radar | Nearby device scan + signal strength |
| Focus session | 25-min countdown + best-effort DND |
| Quick launch | 6 preset app openers |
| File shelf + Download monitor | Drag‑drop + watcher |

### What's a Stub (no public API)

| Feature | Reason |
|---------|--------|
| Dynamic wallpaper | macOS has no public API |
| Per-app volume slide | Requires DSP bus undocumented |
| Any-file drag outside panel | Must use Finder |

## Quick Install (Recommended)

### Step 1: Open Native Terminal

⚠️ **Important**: The DSH web interface cannot compile Swift due to a ModuleCache sandbox restriction. You MUST use your native terminal (Terminal.app or iTerm2).

### Step 2: One-Line Install

```bash
cd /Users/jindy/Archive/WorkBuddy/Lantern && bash build.sh all && open Lantern-*.dmg
```

This will:
1. Clean any previous builds
2. Compile a Release binary (~150MB)
3. Create a signed `.app` bundle
4. Generate a drag-to-install `.dmg` file

### Step 3: Install & Run

Drag `Lantern.app` from the opened DMG to your `/Applications` folder, then launch it. The lantern icon will appear in your menu bar.

## 🏗️ Architecture

Lantern is built on a **four‑layer** architecture that clean‑rooms vorssaint‑utils:

| Layer | Responsibility |
|-------|----------------|
| **Core** | AppFeature enum (~76 cases, String‑backed, CaseIterable), FeatureCatalog (metadata map, permission use, installed‑by‑default whitelist), FeatureRuntime (bindings dict, lazy‑load services, isAvailable()/isActive()) |
| **Services** | Per‑feature services inheriting from `BaseFeatureService` (start/stop, persisted keys via `UserDefaults`), shared instances wired in `AppDelegate` |
| **UI** | SwiftUI views (`MenuPanelView`, `DynamicIslandView`) built from feature‑enabled keys (`@AppStorage`) and real system calls (NSWorkspace, CoreBluetooth) |
| **AppDelegate** | Startup sequence (.accessory → LSUIElement → main menu → status‑item → bindings sync) + TCC polling (every 2.5 s, graceful degrade, no crash on denied) |

### Feature Lifecycle

1. **Installation** — Features declared in `FeatureCatalog` with `installedByDefault true/false` and a display priority.
2. **Activation** — The runtime calls `start()` (or `toggle()` for state features). State features write `featureEnabledKey(rawValue)` to defaults; actions bind to closures that call `performAction()`.
3. **Availability** — `isAvailable()` checks both `isInstalled()` and hardware/permission preconditions (e.g., AX, screen‑recording). UI shows a lock badge when `.needsPermission`, but the action button stays dimmed—never crashes.
4. **Deactivation** — `stop()` tidies timers, removes persisted keys, and restores DND state where possible.

### Build Pipeline

All builds use the bundled `build.sh` (zsh, 954 lines). It compiles vendored C library first, then invokes `swiftc` in parallel over ~600 source files, applies three‑level signing (Developer ID / stable self‑sign / ad‑hoc fallback), and produces a DMG. The `--dev / --install / --test / --selftest` variants gate different code paths. The build targets `MacOSX26.sdk` (CLT 27 can break SwiftUI property‑wrapper macros).

### Feature Groups (tab bar, 7 tabs)

| Group | Short label | Typical features |
|-------|-------------|-----------------|
| `.windowsDock` | Windows | windowSnap, windowMinimizeAll, windowSwitchApp, hideAllWindows, forceQuitDialog |
| `.mouseKeyboard` | Mouse | mouseSensitivity, scrollDirection (invert), keyboardRepeatRate |
| `.clipboard` | Clipboard | clipboardHistory (persistent!), pasteAsPlainText, syncClipboardAcrossDevices |
| `.sound` | Sound | volumeMixer, inputDeviceSelect, per‑app mute, dynamicIsland audio |
| `.energyDisplay` | Energy | cpuMonitor, memoryMonitor, batteryMonitor, networkMonitor, bluetoothRadar |
| `.tools` | Tools | keepAwake, eyeBreak (focus), quickTimer, quickLaunch, fileShelf, downloadMonitor |
| `.dynamicIsland` | Island | time, date, weather, music, nextEvent, timer, focus, volume, cpu, memory, battery, network |

## 🎯 Feature Groups

The panel’s tab bar switches between 7 groups. Each tab shows only the features belonging to that group, filtered by `runtime.orderedFeatures(in: group)` and `@AppStorage slotEnabled`.

## ⚠️ Known Limitations

| Feature | Reason |
|---------|--------|
| **Dynamic wallpaper** | macOS has no public API for runtime wallpaper changes |
| **Per‑app volume slide** | Would require DSP bus / IOKit undocumented; current impl supports only global mute |
| **Cross‑app file drag** | Panel only accepts file‑URL drops; Finder needed for arbitrary drag |
| **Full Disk Access for all services** | Some features require TCC; on denial they gracefully degrade instead of crashing |
| **Continuous per‑app volume meter** | No public per‑process volume API on macOS; only global mute/unmute via CoreAudio taps |

## 🌐 Localization

- 15 languages supported via a pure‑Swift `struct`‑based string table (no `NSLocalizedString`).
- Each language lives in its own `.lproj` folder; compile‑time exhaustive `switch` guarantees coverage.
- Example English string: `"feature.fileShelf.name" = "File Shelf"`; zh‑Hans counterpart: `"feature.fileShelf.name" = "文件架"`.
- Two‑layer design: base `Strings` struct + per‑feature `FeatureStrings` enum (missing case = compile error).

## 📦 Development Status

- 18 提交累计 (`abb4d352 → 9aef2727`)，909 CLI 测试 0 失败
- 共同清单 16 项已覆盖 15 项（#14 壁纸引擎明确不做）
- App 已重启（pid 32481），岛 12 槽全部开关驱动+有值才占位
- 需要持续关注：壁纸引擎、蓝牙感知 macOS 27 IOBluetooth API 被摘除（已改用 CoreBluetooth）

## License

GPL-3.0 — free to use, modify, and distribute with attribution. No commercial warranty.

## Acknowledgments

Original design and architecture inspiration from [vorssaint-utils](https://github.com/vorssaint/vorssaint-utils). Zero‑third‑party Swift dependency policy maintained throughout.