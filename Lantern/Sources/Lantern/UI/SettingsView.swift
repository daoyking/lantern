// SettingsView.swift — Application settings panel

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.panelOpacity.rawValue) private var opacity: Double = 1.0
    @AppStorage(DefaultsKey.showAnimations.rawValue) private var showAnimations = true
    @AppStorage("lantern.appLanguage") private var language: AppLanguage = .simplifiedChinese

    var body: some View {
        VStack(spacing: 0) {
            // Explicit header with a Done button — a borderless/nonactivating
            // status-bar panel does not reliably auto-dismiss a sheet on ESC
            // or outside click, so give the user an obvious way out.
            HStack {
                Text(L("ui.settings", "Settings"))
                    .font(.headline)
                Spacer()
                Button(L("ui.done", "Done")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Form {
                Section(L("settings.general", "General")) {
                    Picker(L("settings.language", "Language"), selection: $language) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .onChange(of: language) { _, newValue in
                        AppLanguage.current = newValue
                    }
                    Text(L("hint.languageNote", "Panel text updates immediately; right-click menu labels need a restart."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section(L("settings.panel", "Panel")) {
                    Slider(value: $opacity, in: 0.5...1.0, step: 0.05) {
                        Text(String(format: L("settings.panelOpacity", "Panel Opacity: %d%%"),
                                    Int(opacity * 100)))
                    }

                    Toggle(L("settings.animations", "Show Animations"), isOn: $showAnimations)
                }

                Section(L("settings.notifications", "Notifications")) {
                    Toggle(L("settings.enableNotifications", "Enable Notifications"), isOn: .constant(false))
                        .disabled(!Permissions.shared.isGranted(.notifications))

                    if !Permissions.shared.isGranted(.notifications) {
                        Button(L("ui.grantPermission", "Grant Permission")) {
                            Permissions.shared.request(.notifications)
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section(L("settings.about", "About")) {
                    LabeledContent(L("settings.version", "Version"), value: MenuPanelView.appVersion)
                    LabeledContent(L("settings.bundleId", "Bundle ID"), value: "me.lantern.menubar")
                    LabeledContent(L("settings.license", "License"), value: "GPL-3.0")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 380)
    }
}
