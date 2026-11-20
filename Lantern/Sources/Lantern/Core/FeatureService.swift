// FeatureService.swift — Protocol defining the service layer interface

import Foundation
import Combine

/// Protocol that all feature services must conform to
public protocol FeatureService: ObservableObject {
    /// The feature this service implements
    var feature: AppFeature { get }
    
    /// Whether the service is currently active/enabled
    var isEnabled: Bool { get }
    
    /// Start the service (called when feature is enabled)
    func start() throws
    
    /// Stop the service (called when feature is disabled)
    func stop() throws
}

/// Extension providing default implementations
public extension FeatureService {
    /// Called when the service is first registered
    func onRegister() {}
    
    /// Called when the service is unregistered
    func onDestroy() {}
    
    /// Default implementation using UserDefaults
    func loadSetting<T>(for key: DefaultsKey, defaultValue: T) -> T {
        return UserDefaults.standard.object(forKey: key.rawValue) as? T ?? defaultValue
    }

    func saveSetting<T>(_ value: T, for key: DefaultsKey) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }
}

/// Base class for features that need additional lifecycle management
open class BaseFeatureService: FeatureService {
    public let feature: AppFeature
    
    public init(feature: AppFeature) {
        self.feature = feature
    }
    
    public var isEnabled: Bool { false }
    
    open func start() throws {}
    
    open func stop() throws {}
    
    deinit {
        onDestroy()
    }
}
