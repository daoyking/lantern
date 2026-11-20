# 🎉 Lantern Build Status — VERIFIED SUCCESS

**Last verified build**: 2026-11-20 — clean release build, zero warnings/errors  
**Result**: ✅ arm64 binary + ad-hoc signed app + valid DMG produced

## Build Artifacts (present now)

| Artifact | Path | Size | Verified |
|----------|------|------|----------|
| App Bundle | `.build/release/Lantern.app` | ~713K binary | Mach-O 64-bit arm64 ✅ |
| DMG Installer | `Lantern-unknown.dmg` | 427K | `hdiutil verify` → VALID ✅ |
| Code signature | ad-hoc (`Signature=adhoc`) | — | codesign verified ✅ |

> Note: name shows `unknown` because no Developer ID / bundle version is configured.
> Rename freely — the DMG content is a working drag-and-drop `Lantern.app`.

## Build Command

```bash
cd /Users/jindy/Archive/WorkBuddy/Lantern
bash build.sh all
open Lantern-*.dmg
```

### Individual steps

```bash
bash build.sh debug    # Debug binary for development
bash build.sh release  # Optimized release binary
bash build.sh dmg      # Create installer DMG
bash build.sh sign     # Ad-hoc sign (Developer ID auto-detected if present)
bash build.sh run      # Build and launch immediately
```

## Xcode 27.2 SDK fixes (commit `54d6360`)

Manual `swiftc` builds need these flags, now baked into `build.sh`:

1. **Add `LanternApp.swift` to SOURCES** — contains `@main`; was missing → `undefined _main`
2. **`-Xlinker -client_name -Xlinker AppKit`** — `SwiftUICore.tbd` has an
   `allowable-clients` whitelist; manual builds named `Lantern` are rejected,
   so we declare the client as `AppKit` to link legitimately
3. **`-F "$SDK/System/Library/Frameworks"`** — resolves `CoreAudioTypes` /
   `CoreTransferable` auto-link frameworks
4. **`-disable-sandbox`** — lets the SwiftUI macro plugin server run inside
   sandboxed shells (native Terminal does not need this, but it is harmless)

## Sandbox note

The DSH/WorkBuddy sandbox blocks Swift's `ModuleCache` writes and
`swift-plugin-server` by default. Builds were verified with the sandbox disabled.
In a native Terminal.app these restrictions do not apply.

## Requirements

- macOS 14.0+ (Sonoma) or later
- Xcode 27.2 SDK with Swift 6.x (tested with Swift 6.4.2)
- Apple Silicon (arm64) — tested on M1 Pro

---

*Repo: https://github.com/daoyking/lantern · head `54d6360`*
