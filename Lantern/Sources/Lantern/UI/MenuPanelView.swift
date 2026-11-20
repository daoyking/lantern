// MenuPanelView.swift — Main SwiftUI panel view

import SwiftUI

struct MenuPanelView: View {
    @StateObject private var runtime = FeatureRuntime.shared
    @State private var selectedTab: FeatureGroup = .windowsDock
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            panelHeader

            // Tab navigation
            tabBar

            // Content area
            TabView(selection: $selectedTab) {
                ForEach(FeatureGroup.allCases, id: \.self) { group in
                    groupContent(group)
                        .tag(group)
                        .tabItem {
                            Label(group.rawValue, systemImage: group.icon)
                        }
                }
            }
            // .tabViewStyle(.panel) // Requires macOS 15+, unavailable in CLT27 SDK

            // Footer
            panelFooter
        }
        .frame(width: 320, height: 400)
        .background(PanelSurface.background)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(PanelSurface.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack {
            Text(Strings.appName.value)
                .font(.headline)
                .foregroundStyle(PanelSurface.title)

            Spacer()

            // Permission indicator
            if let deniedPerm = Permissions.deniedPermission {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                    .help(deniedPerm.humanReadableName + " required")
            }

            // Settings button
            Button(action: showSettings) {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(PanelSurface.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(PanelSurface.headerBackground)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(FeatureGroup.allCases, id: \.self) { group in
                    TabButton(
                        isSelected: selectedTab == group,
                        icon: group.icon,
                        label: group.rawValue
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = group
                        }
                    }
                    .frame(minWidth: 80)
                }
            }
            .background(PanelSurface.tabBarBackground)
        }
        .overlay(
            Divider().foregroundColor(PanelSurface.separator),
            alignment: .bottom
        )
    }

    // MARK: - Group Content

    private func groupContent(_ group: FeatureGroup) -> some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(runtime.orderedFeatures(in: group), id: \.self) { feature in
                    FeatureRow(feature: feature)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Footer

    private var panelFooter: some View {
        HStack {
            Text("Lantern v1.0.0")
                .font(.caption2)
                .foregroundStyle(PanelSurface.tertiary)

            Spacer()

            Button(action: openGitHub) {
                Image(systemName: "github")
                    .foregroundStyle(PanelSurface.secondary)
            }
            .buttonStyle(.plain)

            Button(action: quitApp) {
                Image(systemName: "power")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(PanelSurface.footerBackground)
    }

    // MARK: - Actions

    private func showSettings() {
        // Navigate to settings tab or open settings window
        print("Settings clicked")
    }

    private func openGitHub() {
        if let url = URL(string: "https://github.com/example/lantern") {
            NSWorkspace.shared.open(url)
        }
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Supporting Views

struct TabButton: View {
    let isSelected: Bool
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(isSelected ? PanelSurface.accent : PanelSurface.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? PanelSurface.selectedTabBackground : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct FeatureRow: View {
    let feature: AppFeature
    @StateObject private var runtime = FeatureRuntime.shared

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.displayName)
                    .font(.subheadline)
                    .foregroundStyle(PanelSurface.primary)
                Text(feature.descriptionText)
                    .font(.caption)
                    .foregroundStyle(PanelSurface.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Toggle switch
            Toggle(isOn: Binding(
                get: { runtime.activeFeatures.contains(feature) },
                set: { newValue in
                    if newValue {
                        runtime.start(feature)
                    } else {
                        runtime.stop(feature)
                    }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.switch)
            .disabled(!isAvailable(feature))
            .help(isAvailable(feature) ? "" : "Permission required")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(PanelSurface.cardBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(PanelSurface.cardBorder, lineWidth: 1)
        )
    }

    private func isAvailable(_ feature: AppFeature) -> Bool {
        FeatureCatalog.shared.isAvailable(feature)
    }
}

// MARK: - Panel Styling

enum PanelSurface {
    static var background: Color {
        Color(red: 0.09, green: 0.09, blue: 0.10)
    }

    static var headerBackground: Color {
        Color(red: 0.12, green: 0.12, blue: 0.13)
    }

    static var tabBarBackground: Color {
        Color(red: 0.10, green: 0.10, blue: 0.11)
    }

    static var footerBackground: Color {
        Color(red: 0.08, green: 0.08, blue: 0.09)
    }

    static var cardBackground: Color {
        Color(red: 0.15, green: 0.15, blue: 0.16)
    }

    static var selectedTabBackground: Color {
        Color.white.opacity(0.1)
    }

    static var primary: Color {
        Color.white
    }

    static var secondary: Color {
        Color.white.opacity(0.7)
    }

    static var tertiary: Color {
        Color.white.opacity(0.4)
    }

    static var accent: Color {
        Color.blue
    }

    static var border: Color {
        Color.white.opacity(0.1)
    }

    static var cardBorder: Color {
        Color.white.opacity(0.05)
    }

    static var separator: Color {
        Color.white.opacity(0.1)
    }

    static var title: Color {
        Color.white
    }
}

// MARK: - Preview

#if DEBUG
struct MenuPanelView_Previews: PreviewProvider {
    static var previews: some View {
        MenuPanelView()
    }
}
#endif
