// SettingsView.swift — Application settings panel

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.panelOpacity.rawValue) private var opacity: Double = 1.0
    @AppStorage(DefaultsKey.showAnimations.rawValue) private var showAnimations = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Explicit header with a Done button — a borderless/nonactivating
            // status-bar panel does not reliably auto-dismiss a sheet on ESC
            // or outside click, so give the user an obvious way out.
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Form {
            Section("Panel") {
                Slider(value: $opacity, in: 0.5...1.0, step: 0.05) {
                    Text("Panel Opacity: \(String(format: "%.0f", opacity * 100))%")
                }
                
                Toggle("Show Animations", isOn: $showAnimations)
            }
            
            Section("Notifications") {
                Toggle("Enable Notifications", isOn: .constant(false))
                    .disabled(!Permissions.shared.isGranted(.notifications))
                
                if !Permissions.shared.isGranted(.notifications) {
                    Button("Grant Permission") {
                        Permissions.shared.request(.notifications)
                    }
                    .foregroundStyle(.primary)
                }
            }
            
            Section("About") {
                LabeledContent("Version", value: MenuPanelView.appVersion)
                LabeledContent("Bundle ID", value: "me.lantern.menubar")
                LabeledContent("License", value: "GPL-3.0")
            }
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 340)
    }
}
