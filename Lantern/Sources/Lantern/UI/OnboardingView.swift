// OnboardingView.swift — First-run onboarding flow

import SwiftUI

struct OnboardingView: View {
    @AppStorage(DefaultsKey.onboarded.rawValue) private var hasOnboarded = false
    @State private var currentStep: Int = 0
    
    let totalSteps = 4
    
    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator
            progressView
            
            // Content based on current step
            stepContent
            
            Spacer()
            
            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if currentStep < totalSteps - 1 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        finishOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 32)
        }
        .padding()
        .frame(width: 400, height: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Progress View
    
    private var progressView: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(index <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
    
    // MARK: - Step Content
    
    private var stepContent: some View {
        Group {
            switch currentStep {
            case 0:
                welcomeStep
            case 1:
                purposeStep
            case 2:
                permissionsStep
            case 3:
                doneStep
            default:
                EmptyView()
            }
        }
        .transition(.opacity)
    }
    
    // MARK: - Individual Steps
    
    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
            
            Text(Strings.onboardingWelcome.value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Your all-in-one menu bar companion for macOS.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var purposeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
            
            Text("Quick Access to Useful Tools")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(Strings.onboardingPurpose.value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var permissionsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            Text("Permissions Required")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(Strings.onboardingPermissions.value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Open System Preferences") {
                Permissions.shared.openSystemPreferences()
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            
            Text(Strings.onboardingDone.value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Lantern is ready to use!")
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Actions
    
    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: DefaultsKey.onboarded.rawValue)
        NSApplication.shared.mainWindow?.close()
    }
}
