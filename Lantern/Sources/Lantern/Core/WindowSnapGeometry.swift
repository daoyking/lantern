// WindowSnapGeometry.swift — Pure geometry for window snapping.
// Kept UI-independent so CLI regression tests can exercise edge cases
// (menu bar / Dock insets, tiny screens, odd widths) without Accessibility.

import Foundation

public enum SnapTarget: String, CaseIterable {
    case left, right, top, bottom, full

    public var localizedName: String {
        switch self {
        case .left: return L("snap.left", "Left Half")
        case .right: return L("snap.right", "Right Half")
        case .top: return L("snap.top", "Top Half")
        case .bottom: return L("snap.bottom", "Bottom Half")
        case .full: return L("snap.full", "Fill Screen")
        }
    }
}

public enum SnapGeometry {
    /// Convert Cocoa screen rectangles into Accessibility (top-left origin)
    /// window coordinates and split the *usable* area (excluding menu bar and
    /// Dock), so snapped windows never hide behind system chrome.
    public static func rect(for target: SnapTarget, screen: CGRect, visible: CGRect) -> CGRect {
        let topInset = max(0, screen.maxY - visible.maxY)
        let bottomInset = max(0, visible.minY - screen.minY)
        let leftInset = max(0, visible.minX - screen.minX)
        let usableWidth = max(1, min(visible.width, screen.width - leftInset))
        let usableHeight = max(1, screen.height - topInset - bottomInset)
        let x = screen.minX + leftInset
        let y = screen.minY + topInset

        switch target {
        case .left:
            return CGRect(x: x, y: y, width: usableWidth / 2, height: usableHeight)
        case .right:
            let half = usableWidth / 2
            return CGRect(x: x + half, y: y, width: usableWidth - half, height: usableHeight)
        case .top:
            return CGRect(x: x, y: y, width: usableWidth, height: usableHeight / 2)
        case .bottom:
            let half = usableHeight / 2
            return CGRect(x: x, y: y + half, width: usableWidth, height: usableHeight - half)
        case .full:
            return CGRect(x: x, y: y, width: usableWidth, height: usableHeight)
        }
    }
}
