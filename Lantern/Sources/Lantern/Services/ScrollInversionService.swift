// ScrollInversionService.swift — live scroll-direction inversion via CGEventTap
//
// Replaces the old com.apple.swipescrolldirection defaults write, which only
// took effect after logout/login. This service sits head-insert on the session
// event tap and negates scroll deltas as they pass — the effect is instant,
// and the user's actual macOS scrolling preference is never touched: turn the
// feature off and scrolling returns to exactly how the system was configured.
//
// A mutable event tap requires Accessibility trust; FeatureRuntime's gate
// requests that permission before this service can ever start.

import CoreGraphics
import Foundation

final class ScrollInversionService: BaseFeatureService {

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    override func start() throws {
        guard tap == nil else { return }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,                 // mutable tap → flips deltas
            eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
            callback: ScrollInversionService.flipDeltas,
            userInfo: nil
        ) else {
            // Tap creation refused (no Accessibility trust, or sandboxed).
            // The runtime gate should have asked already; staying inert is
            // the honest fallback rather than faking activity.
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        runLoopSource = source
    }

    override func stop() throws {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        runLoopSource = nil
        tap = nil
    }

    deinit {
        try? stop()
    }

    /// Head-insert callback: negate every positional scroll delta — line and
    /// pixel precision, both axes. Momentum/phase fields pass through
    /// untouched so trackpad physics still feel native.
    private static let flipDeltas: CGEventTapCallBack = { _, type, event, _ in
        guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
        for field in [
            CGEventField.scrollWheelEventDeltaAxis1,        // vertical, line units
            CGEventField.scrollWheelEventPointDeltaAxis1,   // vertical, pixel units
            CGEventField.scrollWheelEventDeltaAxis2,        // horizontal, line units
            CGEventField.scrollWheelEventPointDeltaAxis2,   // horizontal, pixel units
        ] {
            let value = event.getDoubleValueField(field)
            if value != 0 {
                event.setDoubleValueField(field, value: -value)
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
