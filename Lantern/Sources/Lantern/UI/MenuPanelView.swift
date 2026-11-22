// MenuPanelView.swift — Main SwiftUI panel view

import SwiftUI

struct MenuPanelView: View {
    @StateObject private var runtime = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var selectedTab: FeatureGroup = .windowsDock
    @State private var showSettings = false
    /// Increment on in-app language change so every Text/Button re-evaluates L().
    @State private var languageTick = 0

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            tabBar

            // Single content view driven by selectedTab. No nested TabView —
            // the earlier version stacked a custom tab bar AND a native
            // TabView(.tabItem), which rendered two rows and squeezed the
            // labels together ("Windows & DockMouse & Keyboard").
            groupContent(selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            panelFooter
        }
        .frame(width: 360, height: 440)
        .background(PanelSurface.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(PanelSurface.border, lineWidth: 1)
        )
        // Esc closes the panel. onExitCommand is the macOS SwiftUI hook for Escape.
        .onExitCommand {
            NotificationCenter.default.post(name: .lanternClosePanel, object: nil)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(permissions)
        }
        .onReceive(NotificationCenter.default.publisher(for: .lanternLanguageChanged)) { _ in
            languageTick += 1
        }
        .id(languageTick)
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 10) {
            Text(Strings.appName.value)
                .font(.headline)
                .foregroundStyle(PanelSurface.title)

            Spacer()

            // Permission indicator — tappable to open the relevant settings
            if let deniedPerm = Permissions.deniedPermission {
                Button {
                    permissions.request(deniedPerm)
                } label: {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help(String(format: L("hint.permissionRequired", "%@ permission required — click to grant"),
                             deniedPerm.humanReadableName))
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(PanelSurface.secondary)
            }
            .buttonStyle(.plain)
            .help(L("ui.settings", "Settings"))

            // Close button — the panel is a borderless NSPanel with no titlebar
            // controls, so without this there was no in-panel way to dismiss it.
            Button {
                NotificationCenter.default.post(name: .lanternClosePanel, object: nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(PanelSurface.secondary)
            }
            .buttonStyle(.plain)
            .help(L("hint.closePanel", "Close panel (Esc)"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(PanelSurface.headerBackground)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(FeatureGroup.allCases, id: \.self) { group in
                TabButton(
                    isSelected: selectedTab == group,
                    icon: group.icon,
                    label: group.shortLabel
                ) {
                    selectedTab = group
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(PanelSurface.tabBarBackground)
        .overlay(
            Divider().foregroundColor(PanelSurface.separator),
            alignment: .bottom
        )
    }

    // MARK: - Group Content

    private func groupContent(_ group: FeatureGroup) -> some View {
        let features = runtime.orderedFeatures(in: group)
        return Group {
            if features.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(PanelSurface.tertiary)
                    Text(L("ui.emptyGroup", "No features in this group"))
                        .font(.caption)
                        .foregroundStyle(PanelSurface.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        // Clipboard tab gains a live history list above the
                        // feature rows — the collected entries were previously
                        // invisible to the user. Observed so new captures
                        // re-render the list live.
                        if group == .clipboard, let clipboard = ClipboardService.shared {
                            ClipboardHistorySection(service: clipboard)
                        }
                        if group == .sound, let perApp = PerAppAudioService.shared {
                            PerAppAudioSection(service: perApp)
                        }
                        ForEach(features, id: \.self) { feature in
                            FeatureRow(feature: feature)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .id(group) // reset scroll position when switching tabs
    }

    // MARK: - Footer

    private var panelFooter: some View {
        HStack(spacing: 12) {
            Text(String(format: L("ui.version", "Lantern v%@"), MenuPanelView.appVersion))
                .font(.caption2)
                .foregroundStyle(PanelSurface.tertiary)

            Spacer()

            Button(action: openGitHub) {
                Image(systemName: "link.circle")
                    .foregroundStyle(PanelSurface.secondary)
            }
            .buttonStyle(.plain)
            .help(L("hint.viewSource", "View source on GitHub"))

            Button(action: quitApp) {
                Image(systemName: "power")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help(L("ui.quit", "Quit Lantern"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PanelSurface.footerBackground)
    }

    // MARK: - Version / Actions

    /// Read the real bundled version instead of a hard-coded string.
    static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (s?, b?): return "\(s) (\(b))"
        case let (s?, nil): return s
        case (nil, let b?): return "build \(b)"
        default: return "dev"
        }
    }

    private func openGitHub() {
        if let url = URL(string: "https://github.com/daoyking/lantern") {
            NSWorkspace.shared.open(url)
        }
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when the panel's close button / Esc is pressed; AppDelegate
    /// listens and calls hidePanel().
    static let lanternClosePanel = Notification.Name("lanternClosePanel")
}

// MARK: - Supporting Views

struct TabButton: View {
    let isSelected: Bool
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                Text(label)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? PanelSurface.accent : PanelSurface.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(isSelected ? PanelSurface.selectedTabBackground : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

struct FeatureRow: View {
    let feature: AppFeature
    @StateObject private var runtime = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared

    private var metadata: FeatureMetadata {
        FeatureCatalog.shared.metadata(for: feature)
    }

    private var requiredPermission: PermissionType? {
        guard let perm = metadata.requiresPermission, perm != .none else { return nil }
        return perm
    }

    private var permissionGranted: Bool {
        guard let perm = requiredPermission else { return true }
        return permissions.isGranted(perm)
    }

    private var isLocked: Bool { !permissionGranted }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(feature.displayName)
                        .font(.subheadline)
                        .foregroundStyle(PanelSurface.primary)

                    // Lock = this needs a macOS permission the user hasn't granted.
                    // Tap it to open the relevant System Settings pane.
                    if isLocked, let perm = requiredPermission {
                        Button {
                            permissions.request(perm)
                        } label: {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                        .help(String(format: L("hint.needsPermission", "Needs %@ permission — click to grant"),
                                     perm.humanReadableName))
                    }

                    // Honest implementation badge so users can tell real
                    // integrations from demos and placeholders.
                    if !metadata.implementation.localizedBadge.isEmpty {
                        Text(metadata.implementation.localizedBadge)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(metadata.implementation == .simulated ? .orange : .secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(metadata.implementation == .simulated
                                          ? Color.orange.opacity(0.15)
                                          : Color.white.opacity(0.08))
                            )
                    }
                }
                Text(feature.descriptionText)
                    .font(.caption)
                    .foregroundStyle(PanelSurface.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            // One-shot actions render as a button; stateful features as a
            // switch. Permission gating lives in FeatureRuntime — a click on
            // a locked row asks for the permission instead of running an
            // action that would silently fail. (The UI used to request the
            // permission too, opening System Settings twice.)
            if metadata.isAction {
                Button {
                    runtime.performAction(feature)
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(isLocked ? .orange : PanelSurface.accent)
                }
                .buttonStyle(.plain)
                .help(isLocked
                      ? String(format: L("hint.needsPermission", "Needs %@ permission — click to grant"),
                               requiredPermission?.humanReadableName ?? "")
                      : L("ui.runNow", "Run now"))
            } else {
                Toggle(isOn: Binding(
                    get: { runtime.activeFeatures.contains(feature) },
                    set: { _ in runtime.toggle(feature) }
                )) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(PanelSurface.cardBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(PanelSurface.cardBorder, lineWidth: 1)
        )
    }
}

// MARK: - Clipboard History

/// Live clipboard history list shown at the top of the Clipboard tab.
/// Reads the shared ClipboardService registered at launch; nothing renders
/// before registration, and a hint replaces the list until the feature's
/// switch is on (collection only runs while the service is started).
struct ClipboardHistorySection: View {
    @ObservedObject var service: ClipboardService
    @StateObject private var runtime = FeatureRuntime.shared
    @State private var copiedItemID: UUID?

    private var isActive: Bool { runtime.activeFeatures.contains(.clipboardHistory) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "clipboard")
                    .font(.caption)
                    .foregroundStyle(PanelSurface.accent)
                Text(L("clipboard.history.title", "Clipboard History"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PanelSurface.secondary)
                Spacer()
                if !service.history.isEmpty {
                    Button {
                        service.clearHistory()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(PanelSurface.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help(L("clipboard.history.clear", "Clear history"))
                }
            }

            if !isActive {
                Text(L("clipboard.history.hintOff",
                       "Turn on the switch below to start recording"))
                    .font(.caption2)
                    .foregroundStyle(PanelSurface.tertiary)
            } else if service.history.isEmpty {
                Text(L("clipboard.history.empty",
                       "Copy anything anywhere — it will show up here"))
                    .font(.caption2)
                    .foregroundStyle(PanelSurface.tertiary)
            } else {
                ForEach(Array(service.history.prefix(8))) { item in
                    ClipboardHistoryRow(
                        item: item,
                        copied: copiedItemID == item.id
                    ) {
                        service.copy(item)
                        copiedItemID = item.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            if copiedItemID == item.id { copiedItemID = nil }
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(PanelSurface.cardBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(PanelSurface.cardBorder, lineWidth: 1)
        )
    }
}

/// One tappable history entry: click copies the content back to the
/// clipboard (the standard restore behaviour of history managers).
struct ClipboardHistoryRow: View {
    let item: ClipboardItem
    let copied: Bool
    let action: () -> Void

    private static let relativeTime: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var typeIcon: String {
        switch item.type {
        case .string: return "doc.plaintext"
        case .url: return "link"
        case .image: return "photo"
        case .fileURL: return "folder"
        case .rtfd: return "doc.richtext"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: copied ? "checkmark.circle.fill" : typeIcon)
                    .font(.caption)
                    .foregroundStyle(copied ? .green : PanelSurface.tertiary)
                    .frame(width: 16)

                Text(item.content)
                    .font(.caption)
                    .foregroundStyle(PanelSurface.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                Text(Self.relativeTime.localizedString(for: item.timestamp, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(PanelSurface.tertiary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(copied ? 0.12 : 0.04))
            )
        }
        .buttonStyle(.plain)
        .help(L("clipboard.history.copyBack", "Copy back to clipboard"))
    }
}

// MARK: - Panel Styling

enum PanelSurface {
    static var background: Color { Color(red: 0.09, green: 0.09, blue: 0.10) }
    static var headerBackground: Color { Color(red: 0.12, green: 0.12, blue: 0.13) }
    static var tabBarBackground: Color { Color(red: 0.10, green: 0.10, blue: 0.11) }
    static var footerBackground: Color { Color(red: 0.08, green: 0.08, blue: 0.09) }
    static var cardBackground: Color { Color(red: 0.15, green: 0.15, blue: 0.16) }
    static var selectedTabBackground: Color { Color.white.opacity(0.1) }
    static var primary: Color { .white }
    static var secondary: Color { .white.opacity(0.7) }
    static var tertiary: Color { .white.opacity(0.4) }
    static var accent: Color { .blue }
    static var border: Color { .white.opacity(0.1) }
    static var cardBorder: Color { .white.opacity(0.05) }
    static var separator: Color { .white.opacity(0.1) }
    static var title: Color { .white }
}

// MARK: - Per-app audio (sound tab)

/// Live per-app audio list: which apps emit sound, mute each individually.
/// Passive enumeration costs nothing; muting creates/destroys one process tap.
struct PerAppAudioSection: View {
    @ObservedObject var service: PerAppAudioService
    @StateObject private var runtime = FeatureRuntime.shared

    private var isActive: Bool { runtime.activeFeatures.contains(.volumeMixer) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2")
                    .font(.caption)
                    .foregroundStyle(PanelSurface.accent)
                Text(L("perapp.title", "Per-app audio"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PanelSurface.secondary)
                Spacer()
                Text("\(service.apps.count)")
                    .font(.caption2)
                    .foregroundStyle(PanelSurface.tertiary)
            }

            if !isActive {
                Text(L("perapp.hint.off",
                       "Turn on Volume Mixer to see which apps are playing sound"))
                    .font(.caption)
                    .foregroundStyle(PanelSurface.tertiary)
                    .padding(.vertical, 2)
            } else if service.apps.isEmpty {
                Text(L("perapp.empty", "No app is playing audio right now"))
                    .font(.caption)
                    .foregroundStyle(PanelSurface.tertiary)
                    .padding(.vertical, 2)
            } else {
                ForEach(service.apps) { app in
                    PerAppAudioRow(app: app, service: service)
                }
            }
        }
        .padding(10)
        .background(PanelSurface.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(PanelSurface.cardBorder, lineWidth: 1)
        )
    }
}

struct PerAppAudioRow: View {
    let app: AudioApp
    @ObservedObject var service: PerAppAudioService

    private var muted: Bool { service.isMuted(app.pid) }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let running = NSRunningApplication(processIdentifier: app.pid) {
                    Image(nsImage: running.icon ?? NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "app.dashed")
                        .font(.caption)
                }
            }
            .frame(width: 16, height: 16)

            Text(app.name)
                .font(.caption)
                .foregroundStyle(muted ? PanelSurface.tertiary : PanelSurface.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if app.isRunningOutput && !muted {
                Image(systemName: "waveform")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .help(L("perapp.playing", "Playing audio"))
            }

            Button {
                service.toggleMute(app)
            } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(muted ? Color.orange : PanelSurface.secondary)
            }
            .buttonStyle(.plain)
            .help(muted ? L("perapp.unmute", "Unmute this app")
                        : L("perapp.mute", "Mute this app"))
        }
    }
}


// MARK: - File Shelf Section (drag-and-drop, common checklist #3)

struct FileShelfSection: View {
    @ObservedObject var service: FileShelfService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("shelf.title", "File Shelf"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PanelSurface.secondary)
                Spacer()
                if !service.items.isEmpty {
                    Button {
                        service.clear()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(PanelSurface.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help(L("ui.clear", "Clear"))
                }
            }
            if service.items.isEmpty {
                Text(L("shelf.empty", "Drop files here"))
                    .font(.system(size: 11))
                    .foregroundStyle(PanelSurface.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(PanelSurface.cardBackground)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                            .foregroundStyle(PanelSurface.tertiary)
                    )
            } else {
                ForEach(service.items) { item in
                    ShelfRow(service: service, item: item)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(PanelSurface.cardBackground)
        .cornerRadius(8)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            var handled = false
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { service.add(url: url) }
                }
                handled = true
            }
            return handled
        }
    }
}

struct ShelfRow: View {
    @ObservedObject var service: FileShelfService
    let item: ShelfItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
                .font(.system(size: 11))
                .foregroundStyle(PanelSurface.accent)
            Text(item.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(PanelSurface.primary)
            Spacer()
            Button {
                service.reveal(item.id)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(PanelSurface.secondary)
            }
            .buttonStyle(.plain)
            .help(L("shelf.reveal", "Reveal in Finder"))
            Button {
                service.remove(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(PanelSurface.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { service.open(item.id) }
    }
}

// MARK: - Downloads Section (common checklist #7)

struct DownloadsSection: View {
    @ObservedObject var service: DownloadMonitorService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("downloads.title", "Recent Downloads"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PanelSurface.secondary)
            if service.items.isEmpty {
                Text(L("downloads.empty", "No downloads in 24h"))
                    .font(.system(size: 11))
                    .foregroundStyle(PanelSurface.tertiary)
            } else {
                ForEach(service.items) { item in
                    DownloadRow(service: service, item: item)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(PanelSurface.cardBackground)
        .cornerRadius(8)
    }
}

struct DownloadRow: View {
    @ObservedObject var service: DownloadMonitorService
    let item: DownloadItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isPartial ? "arrow.down.circle" : "doc.fill")
                .font(.system(size: 11))
                .foregroundStyle(item.isPartial ? Color.orange : PanelSurface.accent)
            Text(item.name)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(PanelSurface.primary)
            Spacer()
            if item.isPartial {
                Text(L("downloads.partial", "downloading"))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.orange)
            } else {
                Text(DownloadMonitorService.formatSize(item.sizeBytes))
                    .font(.system(size: 9))
                    .foregroundStyle(PanelSurface.tertiary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { service.reveal(item) }
    }
}


// MARK: - Bluetooth Radar Section (common checklist #16)

struct BluetoothRadarSection: View {
    @ObservedObject var service: BluetoothRadarService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L("radar.title", "Bluetooth Radar"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PanelSurface.secondary)
                Spacer()
                Button {
                    service.rescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(PanelSurface.secondary)
                }
                .buttonStyle(.plain)
                .help(L("radar.rescan", "Rescan"))
            }
            if service.radioOn == false {
                Text(L("radar.off", "Bluetooth is off"))
                    .font(.system(size: 11))
                    .foregroundStyle(PanelSurface.tertiary)
            } else if service.entries.isEmpty {
                Text(L("radar.empty", "Scanning, no devices nearby"))
                    .font(.system(size: 11))
                    .foregroundStyle(PanelSurface.tertiary)
            } else {
                ForEach(service.entries) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 11))
                            .foregroundStyle(PanelSurface.accent)
                        Text(entry.name)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(PanelSurface.primary)
                        Spacer()
                        Text("\(entry.rssi) dBm")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(entry.rssi > -70 ? Color.green : PanelSurface.tertiary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(PanelSurface.cardBackground)
        .cornerRadius(8)
    }
}
