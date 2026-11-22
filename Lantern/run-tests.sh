#!/usr/bin/env bash
# Run Lantern core logic regression tests without SwiftPM.
# SwiftPM's manifest compiler invokes sandbox-exec internally, which is blocked
# in sandboxed shells — so we compile the Core sources + Tests/main.swift
# directly with swiftc and execute the resulting binary.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
OUT="${TMPDIR:-/tmp}/lantern_cli_tests"

echo "[TEST] Compiling core logic test driver…"
xcrun swiftc -target arm64-apple-macosx14.0 -sdk "$SDK" \
    -disable-sandbox \
    -module-cache-path "$(pwd)/.build/mc" \
    -F "$SDK/System/Library/Frameworks" \
    -Xlinker -client_name -Xlinker AppKit \
    -o "$OUT" \
    Sources/Lantern/Core/AppFeature.swift \
    Sources/Lantern/Core/DefaultsKey.swift \
    Sources/Lantern/Core/FeatureCatalog.swift \
    Sources/Lantern/Core/Permissions.swift \
    Sources/Lantern/Core/FeatureService.swift \
    Sources/Lantern/Core/FeatureRuntime.swift \
    Sources/Lantern/Core/StringTable.swift \
    Sources/Lantern/Core/PanelLayout.swift \
    Sources/Lantern/Core/WindowSnapGeometry.swift \
    Sources/Lantern/Services/SystemMetrics.swift \
    Sources/Lantern/Services/EnergyMonitorService.swift \
    Sources/Lantern/Services/SystemSettingsService.swift \
    Sources/Lantern/Services/ScrollInversionService.swift \
    Sources/Lantern/Services/DynamicIslandService.swift \
    Sources/Lantern/Services/IslandWeatherService.swift \
    Sources/Lantern/Services/MusicControllerService.swift \
    Sources/Lantern/Services/CalendarService.swift \
    Sources/Lantern/Services/EyeBreakService.swift \
    Sources/Lantern/Services/QuickTimerService.swift \
    Sources/Lantern/Services/FocusService.swift \
    Sources/Lantern/Services/QuickLaunchService.swift \
    Sources/Lantern/Services/FileShelfService.swift \
    Sources/Lantern/Services/DownloadMonitorService.swift \
    Sources/Lantern/Services/BluetoothRadarService.swift \
    Sources/Lantern/UI/EyeBreakOverlay.swift \
    Sources/Lantern/UI/TimerDoneCard.swift \
    Sources/Lantern/UI/FocusDoneCard.swift \
    Sources/Lantern/UI/DynamicIslandView.swift \
    Tests/main.swift

echo "[TEST] Running…"
"$OUT"
