// PanelLayout.swift — Pure geometry for placing the menu panel on screen.
// Kept free of AppKit side effects (only uses Foundation geometry types) so it
// can be unit-tested for the "panel opened off-screen" regression.

import Foundation

#if canImport(AppKit)
import AppKit
#endif

public enum PanelLayout {
    public static let panelSize = CGSize(width: 360, height: 440)

    /// Compute a panel origin guaranteed to be fully inside `visible`.
    ///
    /// - Parameters:
    ///   - visible: the screen's visibleFrame (menu bar / Dock excluded).
    ///   - anchorMidX: horizontal centre of the menu bar icon, if known.
    ///   - anchorMinY: bottom Y of the menu bar icon, if known.
    /// - Returns: an origin whose rect [origin, origin+panelSize] fits in `visible`.
    /// Effective panel size, shrunk to fit unusually small screens.
    public static func fittedSize(in visible: CGRect) -> CGSize {
        CGSize(
            width: min(panelSize.width, max(120, visible.width - 16)),
            height: min(panelSize.height, max(120, visible.height - 16))
        )
    }

    public static func origin(
        in visible: CGRect,
        anchorMidX: CGFloat? = nil,
        anchorMinY: CGFloat? = nil
    ) -> CGPoint {
        let size = fittedSize(in: visible)
        // Clamp so the panel's far edge never passes the visible edge.
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height)

        var x = maxX
        var y = maxY

        if let midX = anchorMidX {
            let anchored = midX - size.width / 2
            x = min(max(visible.minX, anchored), maxX)
        }
        if let minY = anchorMinY {
            let anchored = minY - size.height - 6
            // If the icon is low enough that the panel would overflow the
            // bottom, fall back to the top inside the visible frame.
            y = anchored >= visible.minY ? anchored : maxY
        }

        return CGPoint(x: x, y: y)
    }

    /// Verify a computed frame lies fully within the visible screen rect.
    public static func isFullyVisible(origin: CGPoint, in visible: CGRect) -> Bool {
        let size = fittedSize(in: visible)
        let frame = CGRect(origin: origin, size: size)
        return frame.minX >= visible.minX - 0.5 &&
               frame.minY >= visible.minY - 0.5 &&
               frame.maxX <= visible.maxX + 0.5 &&
               frame.maxY <= visible.maxY + 0.5
    }
}
