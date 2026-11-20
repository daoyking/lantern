# Lantern Installation Guide

## Quick Install (Native Terminal Required)

The DSH web sandbox cannot compile Swift due to ModuleCache restrictions. You MUST run these commands in your **native terminal** (Terminal.app or iTerm).

### Step 1: Navigate to Project
```bash
cd /Users/jindy/Archive/WorkBuddy/Lantern
```

### Step 2: Build Release Binary
```bash
bash build.sh release
```
This will:
- Clean previous builds
- Resolve package dependencies  
- Compile with optimization
- Produce `.build/release/Lantern` binary (~150MB)

### Step 3: Run the App
```bash
.open .build/release/Lantern
```
The app will appear in your Menu Bar as a lantern icon.

### Step 4 (Optional): Install to Applications
```bash
bash build.sh install
```
This creates a proper `.app` bundle and places it in `/Applications/Lantern.app`.

## What You Get

- **Menu Bar Icon**: Click to open control panel
- **Feature Toggles**: Window management, sound control, clipboard history
- **Dynamic Island Preview**: Shows CPU/memory/battery metrics (macOS 15+)
- **Onboarding Flow**: 4-step setup for first-time users
- **Settings Panel**: Customize opacity, animations, language

## Troubleshooting

### "Operation not permitted" on ModuleCache
✓ This is EXPECTED in DSH sandbox. Use native terminal.

### Permission prompts appearing
The app requires:
- Accessibility (for window/sound control)
- Screen Recording (for window enumeration)

Grant these when macOS asks. The app will work immediately after.

### App not appearing in Menu Bar
Check System Settings → Control Center → Menu Bar App Visibility.
