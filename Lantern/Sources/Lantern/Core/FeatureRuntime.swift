// FeatureRuntime.swift — Runtime feature management with lazy loading

import Foundation
import Combine

/// Handles the lifecycle of each registered feature service
public final class FeatureRuntime: ObservableObject {
    public static let shared = FeatureRuntime()

    @Published public var activeFeatures: Set<AppFeature> = []
    @Published public var availableFeatures: [AppFeature] = []

    // Service instances keyed by feature
    private var services: [AppFeature: any FeatureService] = [:]
    // Binding closures: feature → action to toggle it
    public var bindings: [AppFeature: () -> Void] = [:]

    // MARK: - Registration

    /// Register a feature service and its toggle binding
    public func register(
        _ feature: AppFeature,
        service: some FeatureService,
        binding: @escaping () -> Void
    ) {
        services[feature] = service
        bindings[feature] = binding

        // Update available features list after registration
        Task { @MainActor in
            refreshAvailableFeatures()
        }
    }

    /// Unregister a feature and stop its service
    public func unregister(_ feature: AppFeature) {
        try? services[feature]?.stop()
        services.removeValue(forKey: feature)
        bindings.removeValue(forKey: feature)

        Task { @MainActor in
            refreshAvailableFeatures()
        }
    }

    // MARK: - Activation

    /// Start all available features whose defaults say they should be enabled
    public func activateAll() {
        let catalog = FeatureCatalog.shared
        let defaults = UserDefaults.standard

        for feature in AppFeature.allCases {
            // Only activate if feature is available and marked as enabled by default
            guard catalog.isAvailable(feature) else { continue }
            let key = DefaultsKey.featureEnabledKey(feature.rawValue)
            guard defaults.bool(forKey: key) else { continue }

            start(feature)
        }
    }

    /// Start a single feature immediately
    public func start(_ feature: AppFeature) {
        guard let service = services[feature] else { return }
        guard !activeFeatures.contains(feature) else { return }

        try? service.start()
        activeFeatures.insert(feature)

        // Notify observers
        objectWillChange.send()
    }

    /// Stop a single feature
    public func stop(_ feature: AppFeature) {
        guard let service = services[feature] else { return }
        guard activeFeatures.contains(feature) else { return }

        try? service.stop()
        activeFeatures.remove(feature)

        objectWillChange.send()
    }

    /// Toggle a feature on/off (used by menu panel actions)
    public func toggle(_ feature: AppFeature) {
        if activeFeatures.contains(feature) {
            stop(feature)
        } else {
            start(feature)
        }
    }

    // MARK: - Refresh

    /// Re-evaluate which features are currently available and update the published list
    public func refreshAvailableFeatures() {
        let catalog = FeatureCatalog.shared
        availableFeatures = catalog.availableFeatures.sorted { lhs, rhs in
            let lhsMeta = catalog.metadata(for: lhs)
            let rhsMeta = catalog.metadata(for: rhs)
            return lhsMeta.displayPriority < rhsMeta.displayPriority
        }
    }

    /// Returns features sorted by display priority within a group
    public func orderedFeatures(in group: FeatureGroup) -> [AppFeature] {
        let catalog = FeatureCatalog.shared
        let groupFeatures = AppFeature.allCases.filter { $0.group == group }
        return groupFeatures.sorted { lhs, rhs in
            let lhsMeta = catalog.metadata(for: lhs)
            let rhsMeta = catalog.metadata(for: rhs)
            return lhsMeta.displayPriority < rhsMeta.displayPriority
        }
    }

    // MARK: - Sync with UserDefaults

    /// Called at launch to restore persisted enabled/disabled state
    public func syncFromDefaults() {
        let defaults = UserDefaults.standard
        let catalog = FeatureCatalog.shared

        for feature in AppFeature.allCases {
            let isEnabled = defaults.bool(forKey: DefaultsKey.featureEnabledKey(feature.rawValue))
            let isAvailable = catalog.isAvailable(feature)

            if isAvailable && isEnabled {
                start(feature)
            } else {
                stop(feature)
            }
        }
    }

    /// Persist current state to UserDefaults
    public func syncToDefaults() {
        let defaults = UserDefaults.standard
        for feature in AppFeature.allCases {
            let key = DefaultsKey.featureEnabledKey(feature.rawValue)
            defaults.set(activeFeatures.contains(feature), forKey: key)
        }
    }
}
