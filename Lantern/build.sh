#!/usr/bin/env bash
# =============================================================================
# Lantern Build Script — Direct swiftc Compilation (bypasses SPM ModuleCache bug)
#
# Uses the same approach as vorssaint-utils: direct swiftc + output-file-map.json
# completely avoids SPM manifest compilation which hits the CLT27 ModuleCache
# sandbox restriction (/var/folders/.../C/clang/ModuleCache/).
#
# Commands: clean | build | sign | dmg | notarize | install | run | all
# Usage:    bash build.sh all
# =============================================================================

set -euo pipefail

# Ensure /usr/sbin is in PATH (sandbox strips it)
case ":$PATH:" in
    *":/usr/sbin:"*) ;;
    *) export PATH="$PATH:/usr/sbin" ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")"

readonly APP_NAME="Lantern"
readonly BUNDLE_ID="me.lantern.menubar"
readonly VERSION="$({ plutil -extract CFBundleShortVersionString raw -o - Resources/Info.plist 2>/dev/null || echo '0.1.0'; })-$({ plutil -extract CFBundleVersion raw -o - Resources/Info.plist 2>/dev/null || echo '1'; })"
readonly TARGET="arm64-apple-macosx14.0"
readonly SDK="$(xcrun --sdk macosx --show-sdk-path)"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()   { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
log_step()   { echo -e "${BLUE}[STEP]${NC} $*"; }

# ─── Write output-file-map.json (same shape as vorssaint-utils) ──────────────
write_output_file_map() {
    local out="$1" obj_dir="$2"; shift 2
    {
        printf '{\n  "": {\n    "swift-dependencies": "%s/master.swiftdeps"\n  }\n' "$obj_dir"
        for src in "$@"; do
            local artifact="${src//\//__}"
            artifact="${artifact%.swift}"
            printf ',\n  "%s": {\n    "object": "%s/%s.o",\n    "swift-dependencies": "%s/%s.swiftdeps"\n  }\n' \
                "$src" "$obj_dir" "$artifact" "$obj_dir" "$artifact"
        done
        printf '\n}\n'
    } > "$out"
}

# ─── Clean ─────────────────────────────────────────────────────────────────────
clean() {
    log_step "Cleaning..."
    rm -rf .build build "Lantern.app" "*.dmg"
    log_info "Clean complete."
}

# ─── Build (direct swiftc, no SPM) ─────────────────────────────────────────────
build() {
    local mode="${1:-release}"
    local opt_flags="-O"
    [[ "$mode" == "debug" ]] && opt_flags="-Onone"

    log_step "Building ${APP_NAME} (${mode})..."
    local obj_dir=".build/${mode}/objects"
    mkdir -p "$obj_dir"

    # Collect Swift sources
    local -a SOURCES=(
        Sources/Lantern/AppDelegate.swift
        Sources/Lantern/LanternApp.swift
        Sources/Lantern/Core/AppFeature.swift
        Sources/Lantern/Core/DefaultsKey.swift
        Sources/Lantern/Core/FeatureCatalog.swift
        Sources/Lantern/Core/FeatureRuntime.swift
        Sources/Lantern/Core/FeatureService.swift
        Sources/Lantern/Core/Permissions.swift
        Sources/Lantern/Core/PanelLayout.swift
        Sources/Lantern/Core/StatusItemController.swift
        Sources/Lantern/Core/StringTable.swift
        Sources/Lantern/Core/WindowSnapGeometry.swift
        Sources/Lantern/Services/ClipboardEnhancementService.swift
        Sources/Lantern/Services/ClipboardService.swift
        Sources/Lantern/Services/DynamicIslandService.swift
        Sources/Lantern/Services/EnergyMonitorService.swift
        Sources/Lantern/Services/ScrollInversionService.swift
        Sources/Lantern/Services/KeepAwakeService.swift
        Sources/Lantern/Services/PerAppAudioService.swift
        Sources/Lantern/Services/SoundMixerService.swift
        Sources/Lantern/Services/SystemMetrics.swift
        Sources/Lantern/Services/SystemSettingsService.swift
        Sources/Lantern/Services/ToolsServices.swift
        Sources/Lantern/Services/WindowManagerService.swift
        Sources/Lantern/UI/DynamicIslandView.swift
        Sources/Lantern/UI/MenuPanelView.swift
        Sources/Lantern/UI/OnboardingView.swift
        Sources/Lantern/UI/SettingsView.swift
    )

    local file_map="$obj_dir/output-file-map.json"
    write_output_file_map "$file_map" "$obj_dir" "${SOURCES[@]}"

    # Compile — parallel batch mode on all cores (see vorssaint-utils comment:
    # "without -j batches share parsing work across every core, keeping optimisation per-file")
    log_info "Compiling with $(sysctl -n hw.logicalcpu) cores, batch mode…"
    # -disable-sandbox: lets SwiftUI macro plugin server run in sandboxed shells (DSH)
    # -client_name AppKit: SwiftUICore.tbd only allows listed clients (AppKit/SwiftUI/...).
    #   Manual swiftc builds produce "Lantern" which is not on that list, so ld refuses
    #   to link SwiftUICore directly. Pretend to be AppKit to satisfy allowable-clients.
    # -F SDK frameworks: CoreAudioTypes/CoreTransferable are auto-linked and must resolve.
    swiftc "$opt_flags" -incremental -enable-batch-mode \
        -disable-sandbox \
        -j "$(sysctl -n hw.logicalcpu)" \
        -output-file-map "$file_map" \
        -target "$TARGET" -sdk "$SDK" \
        -module-name Lantern \
        -F "$SDK/System/Library/Frameworks" \
        -framework SwiftUI \
        -Xlinker -client_name -Xlinker AppKit \
        -Xcc -fPIC \
        "${SOURCES[@]}" \
        -o ".build/${mode}/${APP_NAME}"

    # Copy binary into the .app bundle structure
    local app_path=".build/${mode}/${APP_NAME}.app"
    rm -rf "$app_path"
    mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
    cp ".build/${mode}/${APP_NAME}" "$app_path/Contents/MacOS/${APP_NAME}"
    cp Resources/Info.plist "$app_path/Contents/Info.plist"
    # Fix Info.plist placeholders
    plutil -replace CFBundleExecutable -string "${APP_NAME}" "$app_path/Contents/Info.plist"
    plutil -replace CFBundleIdentifier -string "${BUNDLE_ID}" "$app_path/Contents/Info.plist"
    plutil -replace CFBundleShortVersionString -string "${VERSION%-*}" "$app_path/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "${VERSION#*-}" "$app_path/Contents/Info.plist"
    plutil -replace CFBundleName -string "${APP_NAME}" "$app_path/Contents/Info.plist"
    plutil -replace LSMinimumSystemVersion -string "14.0" "$app_path/Contents/Info.plist"

    # Bundle .lproj resources — without these every L() call falls back to
    # the English literal embedded in Swift source.
    for lproj in Resources/*.lproj; do
        [[ -d "$lproj" ]] || continue
        cp -R "$lproj" "$app_path/Contents/Resources/"
    done

    log_info "Binary built at: ${app_path}"
}

# ─── Sign ───────────────────────────────────────────────────────────────────────
sign() {
    local config="${1:-release}"
    local app=".build/${config}/${APP_NAME}.app"
    [[ ! -d "$app" ]] && log_error "App not found. Run 'bash build.sh build' first."

    local identity="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk '/Developer ID|Apple Development/{print $2; exit}')"
    identity="${identity:-\-}"

    log_step "Signing ${app} …"
    cat > "/tmp/${APP_NAME}.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key><false/>
    <key>com.apple.security.device.audio-input</key><true/>
    <key>com.apple.security.device.camera</key><true/>
</dict>
</plist>
EOF
    if [[ "$identity" != "-" ]]; then
        codesign --force --sign "$identity" \
            --entitlements "/tmp/${APP_NAME}.entitlements" \
            --options runtime \
            "$app" || log_warn "Code-signing failed (certificate unavailable)"
    else
        # Ad-hoc sign so it still runs
        codesign --force --sign - --options runtime "$app" || true
    fi
    rm -f "/tmp/${APP_NAME}.entitlements"
}

# ─── DMG ───────────────────────────────────────────────────────────────────────
create_dmg() {
    local config="${1:-release}"
    local app=".build/${config}/${APP_NAME}.app"
    [[ ! -d "$app" ]] && log_error "App not found. Run 'bash build.sh build' first."

    local dmg="${APP_NAME}-${VERSION:-unknown}.dmg"
    local staging="$(mktemp -d)"

    log_step "Creating DMG → ${dmg}"
    cp -R "$app" "$staging/${APP_NAME}.app"
    ln -s /Applications "$staging/Applications"

    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "$staging" -ov -format UDZO \
        "$dmg" >/dev/null 2>&1 || \
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "$staging" -ov -format UDCO \
        "$dmg"

    rm -rf "$staging"
    log_info "DMG created: ${dmg}"
}

# ─── Notarize (requires Apple Developer account + notarytool) ────────────────
notarize() {
    local dmg="${APP_NAME}-${VERSION:-unknown}.dmg"
    [[ -f "$dmg" ]] || log_error "DMG not found. Run 'bash build.sh dmg' first."

    log_step "Notarizing ${dmg}…"
    xcrun notarytool submit "$dmg" \
        --team-id "${TEAM_ID:-}" \
        --apple-id "${APPLE_ID:-}" \
        --password "@env:NOTARY_PASSWORD" \
        --wait || log_warn "Notarization failed or credentials missing"
}

# ─── Install ───────────────────────────────────────────────────────────────────
# Ad-hoc signed apps dragged from a DMG are blocked by Gatekeeper
# ("this Mac can't verify this App"). Installing via this function clears
# quarantine attributes, re-signs, and launches — no manual Finder steps.
install_app() {
    local config="${1:-release}"
    local src=".build/${config}/${APP_NAME}.app"
    local dst="/Applications/${APP_NAME}.app"
    [[ -d "$src" ]] || log_error "App not built yet. Run 'bash build.sh build ${config}' first."

    log_step "Installing ${APP_NAME} → /Applications …"
    # Clear any stale process from a previous copy
    pkill -f "${dst}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
    rm -rf "$dst"
    cp -R "$src" "$dst"

    # Strip quarantine / Finder metadata that triggers Gatekeeper
    xattr -cr "$dst" 2>/dev/null || true
    # Re-sign ad-hoc so the copied bundle has a valid signature in its new location
    codesign --force --deep --sign - "$dst" 2>/dev/null \
        || log_warn "Re-sign failed (installing anyway)"

    open "$dst"
    log_info "✅ Installed and launched: ${dst}"
    log_info "   If a stale copy in the menu bar remains, it was killed above."
}

# ─── Run ───────────────────────────────────────────────────────────────────────
run_app() {
    local config="${1:-debug}"
    local bin=".build/${config}/${APP_NAME}.app"
    [[ -d "$bin" ]] || log_error "App not built yet. Run 'bash build.sh build ${config}' first."
    open "$bin"
    log_info "Launched ${APP_NAME}."
}

# ─── Main dispatcher ───────────────────────────────────────────────────────────
cmd="${1:-all}"
shift || true

case "$cmd" in
    clean) clean ;;
    build) build "${1:-release}" ;;
    debug) build debug ;;
    release) build release ;;
    sign)  sign "${1:-release}" ;;
    dmg)   create_dmg "${1:-release}" ;;
    notarize) notarize ;;
    install) install_app "${1:-release}" ;;
    run)   run_app "${1:-debug}" ;;
    all)
        clean
        build release
        sign release
        create_dmg release
        log_info "✅ Done! Artefacts:"
        log_info "   App:  .build/release/${APP_NAME}.app"
        ls -lh "${APP_NAME}"*.dmg 2>/dev/null && true
        ;;
    *) log_error "Unknown command: $cmd  (use: clean|build|sign|dmg|notarize|install|run|all)" ;;
esac
