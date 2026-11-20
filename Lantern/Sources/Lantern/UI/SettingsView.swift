// SettingsView.swift — Application settings panel

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.panelOpacity.rawValue) private var opacity: Double = 1.0
    @AppStorage(DefaultsKey.showAnimations.rawValue) private var showAnimations = true
    
    var body: some View {
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
        .frame(width: 400, height: 300)
    }
}
