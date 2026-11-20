// SoundMixerService.swift — System audio control via Core Audio APIs

import Foundation
import AppKit
import CoreAudio

/// Manages system volume and mute state via Core Audio hardware properties.
public final class SoundMixerService: BaseFeatureService {
    
    // MARK: - Constants
    
    private static let volumeStep: Float32 = 0.05  // 5% per step
    
    // Core Audio property selectors as UInt32 values
    private static let kAudioHardwarePropertyDefaultOutputDevice: UInt32 = 0x68617264  // 'harr'
    private static let kAudioDevicePropertyScalarVolumeLevel: UInt32 = 0x64736C66  // 'dsld'
    private static let kAudioDevicePropertyMute: UInt32 = 0x6D757465  // 'mute'
    private static let kAudioDevicePropertyScopeOutput: UInt32 = 0x6F757470  // 'outp'
    
    // MARK: - Properties
    
    /// Current master volume (0.0–1.0)
    public private(set) var volume: CGFloat = 0.5
    
    /// Whether the system is currently muted
    public private(set) var isMuted: Bool = false
    
    // MARK: - Lifecycle
    
    override public func start() throws {
        refreshState()
    }
    
    override public func stop() throws {}
    
    // MARK: - Public Methods
    
    /// Set volume to exact value (clamped 0.0–1.0)
    public func setVolume(_ vol: CGFloat) {
        let clamped = max(0.0, min(1.0, vol))
        setMasterVolume(Float32(clamped))
        volume = clamped
    }
    
    /// Increase volume by 5%
    public func increaseVolume() {
        setVolume(volume + CGFloat(SoundMixerService.volumeStep))
    }
    
    /// Decrease volume by 5%
    public func decreaseVolume() {
        setVolume(volume - CGFloat(SoundMixerService.volumeStep))
    }
    
    /// Toggle mute state
    public func toggleMute() {
        isMuted.toggle()
        setMute(isMuted)
    }
    
    // MARK: - Private State Refresh
    
    private func refreshState() {
        volume = CGFloat(getMasterVolume())
        isMuted = isSystemMuted()
    }
    
    // MARK: - Core Audio helpers
    
    private func getDefaultDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: Self.kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var defaultDevice = AudioObjectID(kAudioObjectSystemObject)
        let size = UInt32(MemoryLayout<AudioObjectID>.stride)
        
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &defaultDevice
        ) == noErr else { return nil }
        
        return defaultDevice
    }
    
    private func getMasterVolume() -> Float32 {
        guard let device = getDefaultDevice() else { return 0.5 }
        
        var address = AudioObjectPropertyAddress(
            mSelector: Self.kAudioDevicePropertyScalarVolumeLevel,
            mScope: Self.kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var volume: Float32 = 0.5
        let size = UInt32(MemoryLayout<Float32>.stride)
        
        guard AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            &volume
        ) == noErr else { return 0.5 }
        
        return volume
    }
    
    private func setMasterVolume(_ vol: Float32) {
        guard let device = getDefaultDevice() else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: Self.kAudioDevicePropertyScalarVolumeLevel,
            mScope: Self.kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var volValue = vol
        let size = UInt32(MemoryLayout<Float32>.stride)
        AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            size,
            &volValue
        )
    }
    
    private func isSystemMuted() -> Bool {
        guard let device = getDefaultDevice() else { return false }
        
        var address = AudioObjectPropertyAddress(
            mSelector: Self.kAudioDevicePropertyMute,
            mScope: Self.kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var muted: Int32 = 0
        let size = UInt32(MemoryLayout<Int32>.stride)
        
        let status = AudioObjectGetPropertyData(
            device,
            &address,
            0,
            nil,
            &size,
            &muted
        )
        
        return status == noErr && muted != 0
    }
    
    private func setMute(_ muted: Bool) {
        guard let device = getDefaultDevice() else { return }
        
        var address = AudioObjectPropertyAddress(
            mSelector: Self.kAudioDevicePropertyMute,
            mScope: Self.kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var boolValue: Int32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<Int32>.stride)
        
        AudioObjectSetPropertyData(
            device,
            &address,
            0,
            nil,
            size,
            &boolValue
        )
    }
}
