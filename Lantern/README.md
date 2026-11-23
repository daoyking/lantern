# Lantern — macOS Menu Bar Agent (Final Build)

## Overview

Lantern is a clean-room Swift recreation of [vorssaint-utils](https://github.com/vorssaint/vorssaint-utils), a comprehensive macOS menu bar utility suite. It implements 15 of 16 shared features and provides a clean API for macOS system control.

- **Bundle ID**: `me.lantern.menubar`
- **License**: GPL-3.0
- **Minimum macOS**: 14.0 (Sonoma)
- **Swift**: 6.4.2+

## What's Real

| Feature | Implementation |
|---------|---------------|
| Window management | NSWorkspace calls (minimize all, switch app, snap) |
| Clipboard history | Persisted JSON in UserDefaults, max 50 entries |
| Per-app volume mute | CoreAudio ProcessTap + muteBehavior=.muted; global mute/unmute only |
| Dynamic Island | 7-slot layout (time/date/weather/music/nextEvent/timer/focus/volume+), featureEnabledKey-driven |
| Wake lock | IOKit preventSleep |
| System monitoring | Real IOKit.ps/Mach telemetry; battery dual-shape compat |
| Weather | Open-Meteo free API + CoreLocation when-in-use |
| Music control | NX system media keys + CGEventPost; all players; no TCC |
| Calendar | EventKit read-only; 7-day window; nextEvent HH:mm |
| 20-20-20 break | 25-min timer + 20-s mask; DND best-effort post |
| Quick timer | start(minutes:) dual semantics (same-key cancel, different-key change); NSSound + corner card |
| Focus session | 25-min countdown + DistributedNotificationCenter DND post (best-effort); FocusDoneCard |
| Quick launch | 6 preset app openers via LaunchServices |
| File shelf | Drag-and-drop (up to 12 items); bookmarks via security-scoped bookmark data; reveal/open in Finder |
| Bluetooth radar | CoreBluetooth scan nearby advertising devices; RSSI sorting (>-70dBm green) |

## Known Limitations

| Feature | Reason |
|---------|--------|
| Dynamic wallpaper | macOS has no public API for runtime wallpaper changes |
| Per-app volume slide | Would require DSP bus; current impl supports only global mute/unmute |
| Full Disk Access for all services | Some features degrade gracefully on denial |
| Continuous per-app volume meter | No public per-process volume API on macOS |

## Build & Install

```bash
# From terminal (DSH web interface cannot compile Swift due to ModuleCache sandbox restriction)
cd /Users/jindy/Archive/WorkBuddy/Lantern
bash build.sh all     # produces .dmg
# Then drag Lantern.app to /Applications
# First launch: right-click → "Open" to trust unsigned Developer ID
```

## Architecture

Lantern uses a **four-layer** architecture clean-room inspired by vorssaint-utils:

| Layer | Responsibility |
|-------|----------------|
| **Core** | AppFeature enum (~76 cases, String‑backed, CaseIterable), FeatureCatalog (metadata map, permission use, installed‑by‑default whitelist), FeatureRuntime (bindings dict, lazy‑load services, isAvailable()/isActive()) |
| **Services** | Per‑feature services inheriting from BaseFeatureService (start/stop, persisted keys via UserDefaults), shared instances wired in AppDelegate |
| **UI** | SwiftUI views (MenuPanelView, DynamicIslandView) built from feature‑enabled keys (@AppStorage) and real system calls |
| **AppDelegate** | Startup sequence (.accessory → LSUIElement → main menu → status‑item → bindings sync) + TCC polling (every 2.5 s, graceful degrade, no crash on denied) |

## Feature Groups (tab bar, 7 tabs)

| Group | Short label | Typical features |
|-------|-------------|-----------------|
| `.windowsDock` | Windows | windowSnap, windowMinimizeAll, windowSwitchApp, hideAllWindows, forceQuitDialog |
| `.mouseKeyboard` | Mouse | mouseSensitivity, scrollDirection (invert), keyboardRepeatRate |
| `.clipboard` | Clipboard | clipboardHistory (persistent!), pasteAsPlainText |
| `.sound` | Sound | volumeMixer, inputDeviceSelect, per‑app mute, dynamicIsland audio |
| `.energyDisplay` | Energy | cpuMonitor, memoryMonitor, batteryMonitor, networkMonitor, bluetoothRadar |
| `.tools` | Tools | keepAwake, eyeBreak (focus), quickTimer, quickLaunch, fileShelf, downloadMonitor |
| `.dynamicIsland` | Island | time, date, weather, music, nextEvent, timer, focus, volume, cpu, memory, battery, network |

## Localization

- 15 languages via pure‑Swift `struct`-based string table (no `NSLocalizedString`).
- Two‑layer design: base `Strings` struct + per‑feature `FeatureStrings` enum (missing case = compile error).
- Example: `"feature.fileShelf.name" = "File Shelf"` (EN) / `"文件架"` (zh‑Hans).

## License

GPL-3.0 — free to use, modify, and distribute with attribution. No commercial warranty.

## Acknowledgments

Original design inspiration from [vorssaint-utils](https://github.com/vorssaint/vorssaint-utils). Zero‑third‑party Swift dependency policy maintained throughout (vendored `cgif` C library only).