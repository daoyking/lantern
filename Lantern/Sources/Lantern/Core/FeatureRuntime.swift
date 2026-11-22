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
            // One-shot actions have no persistent state.
            guard !catalog.metadata(for: feature).isAction else { continue }
            // Only activate if feature is available and marked as enabled by default
            guard catalog.isAvailable(feature) else { continue }
            let key = DefaultsKey.featureEnabledKey(feature.rawValue)
            guard defaults.bool(forKey: key) else { continue }

            start(feature)
        }
    }

    /// Start a single feature immediately.
    /// The service is optional: catalog-only / not-yet-implemented features
    /// still toggle their persisted preference so the UI switch is never dead.
    public func start(_ feature: AppFeature) {
        guard !activeFeatures.contains(feature) else { return }

        if let service = services[feature] {
            try? service.start()
        }
        activeFeatures.insert(feature)
        persist(feature, enabled: true)

        objectWillChange.send()
    }

    /// Stop a single feature (service optional — see start(_:)).
    public func stop(_ feature: AppFeature) {
        guard activeFeatures.contains(feature) else { return }

        if let service = services[feature] {
            try? service.stop()
        }
        activeFeatures.remove(feature)
        persist(feature, enabled: false)

        objectWillChange.send()
    }

    /// Persist a single feature's enabled state without rewriting every key.
    private func persist(_ feature: AppFeature, enabled: Bool) {
        UserDefaults.standard.set(
            enabled,
            forKey: DefaultsKey.featureEnabledKey(feature.rawValue)
        )
    }

    /// Toggle a feature on/off (used by menu panel actions).
    /// Action-type features (volume step, switch app, minimize all) run their
    /// one-shot effect instead of latching a state.
    /// Starting a gated feature without its macOS permission opens the
    /// permission prompt instead of running something that would fail.
    public func toggle(_ feature: AppFeature) {
        if FeatureCatalog.shared.metadata(for: feature).isAction {
            performAction(feature)
            return
        }
        if activeFeatures.contains(feature) {
            stop(feature)
        } else {
            guard gate(feature) else { return }
            start(feature)
        }
    }

    /// Execute a one-shot action through its registered binding. Action
    /// features do not persist an "on" state — clicking is the whole effect.
    /// Gated actions check their permission first for the same reason.
    public func performAction(_ feature: AppFeature) {
        guard gate(feature) else { return }
        bindings[feature]?()
        objectWillChange.send()
    }

    // MARK: - Permission gate

    /// Single permission checkpoint for every user-initiated activation.
    /// Returns true when the feature may run; when blocked, asks for the
    /// missing permission (opening the relevant System Settings pane) so the
    /// click still has visible effect instead of failing silently.
    /// Only user-initiated paths route through here — syncFromDefaults →
    /// start() deliberately bypasses it so a revoked permission never pops a
    /// System Settings window at app launch.
    private func gate(_ feature: AppFeature) -> Bool {
        guard let perm = FeatureCatalog.shared.metadata(for: feature).requiresPermission,
              perm != .none,
              !Permissions.shared.isGranted(perm)
        else { return true }
        Permissions.shared.request(perm)
        return false
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
            // One-shot actions have no persistent on/off state — skip them so
            // launching the app never fires volume/window actions.
            if catalog.metadata(for: feature).isAction { continue }

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
