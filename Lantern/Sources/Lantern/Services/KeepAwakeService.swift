// KeepAwakeService.swift — Prevents system from sleeping

import Foundation
import IOKit.pwr_mgt

/// Service that prevents macOS from entering sleep mode
public final class KeepAwakeService: BaseFeatureService {
    private var assertionID: IOPMAssertionID = 0
    
    public override func start() throws {
        // Create an assertion to prevent idle sleep
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Lantern: Keeping system awake" as CFString,
            &assertionID
        )
        
        if result == kIOReturnSuccess {
            #if DEBUG
            print("[Lantern] KeepAwake: System sleep prevented (assertionID: \(assertionID))")
            #endif
        } else {
            #if DEBUG
            print("[Lantern] KeepAwake: Failed to prevent sleep, error code: \(result)")
            #endif
            throw KeepAwakeError.assertionFailed(result)
        }
    }
    
    public override func stop() throws {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            #if DEBUG
            print("[Lantern] KeepAwake: Sleep prevention released")
            #endif
        }
    }
    
    public override var isEnabled: Bool {
        assertionID != 0
    }
}

// MARK: - Error Handling

enum KeepAwakeError: Error, LocalizedError {
    case assertionFailed(Int32)
    
    var errorDescription: String? {
        switch self {
        case .assertionFailed(let code):
            return "Failed to create sleep assertion (error: \(code))"
        }
    }
}
