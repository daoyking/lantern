// MenuPanelView.swift — Main SwiftUI panel view

import SwiftUI

struct MenuPanelView: View {
    @StateObject private var runtime = FeatureRuntime.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var selectedTab: FeatureGroup = .windowsDock
    @State private var showSettings = false

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
                .help("\(deniedPerm.humanReadableName) permission required — click to grant")
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(PanelSurface.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")

            // Close button — the panel is a borderless NSPanel with no titlebar
            // controls, so without this there was no in-panel way to dismiss it.
            Button {
                NotificationCenter.default.post(name: .lanternClosePanel, object: nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(PanelSurface.secondary)
            }
            .buttonStyle(.plain)
            .help("Close panel (Esc)")
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
                    Text("No features in this group")
                        .font(.caption)
                        .foregroundStyle(PanelSurface.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
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
            Text("Lantern v\(MenuPanelView.appVersion)")
                .font(.caption2)
                .foregroundStyle(PanelSurface.tertiary)

            Spacer()

            Button(action: openGitHub) {
                Image(systemName: "link.circle")
                    .foregroundStyle(PanelSurface.secondary)
            }
            .buttonStyle(.plain)
            .help("View source on GitHub")

            Button(action: quitApp) {
                Image(systemName: "power")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Quit Lantern")
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
                        .help("Needs \(perm.humanReadableName) permission — click to grant")
                    }

                    // Honest implementation badge so users can tell real
                    // integrations from demos and placeholders.
                    if !metadata.implementation.badge.isEmpty {
                        Text(metadata.implementation.badge)
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

            // One-shot actions render as a button; stateful features as a switch.
            if metadata.isAction {
                Button {
                    runtime.performAction(feature)
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .foregroundStyle(PanelSurface.accent)
                }
                .buttonStyle(.plain)
                .help("Run now")
            } else {
                Toggle(isOn: Binding(
                    get: { runtime.activeFeatures.contains(feature) },
                    set: { newValue in
                        if newValue, let perm = requiredPermission, !permissionGranted {
                            permissions.request(perm)
                        }
                        runtime.toggle(feature)
                    }
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
